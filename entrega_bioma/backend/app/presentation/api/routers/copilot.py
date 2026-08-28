from collections.abc import Sequence
from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Response, status
from pydantic import BaseModel, Field

from app.application.use_cases.answer_copilot_question import AnswerCopilotQuestion
from app.domain.errors import RateLimitExceeded
from app.domain.models import Actor, CatalogKnowledgeItem, CopilotSource
from app.infrastructure.ai.factory import build_ai_gateway
from app.infrastructure.ai.redis_memory import RedisConversationMemory
from app.infrastructure.config import Settings, get_settings
from app.infrastructure.db.database import Database
from app.infrastructure.db.repositories import (
    PostgresCopilotAuditRepository,
    PostgresCopilotConversationRepository,
    PostgresSightingRepository,
)
from app.infrastructure.rate_limit import RedisRateLimiter
from app.presentation.api.dependencies import (
    get_actor_connection,
    get_current_actor,
    get_database,
    get_rate_limiter,
)
from app.presentation.api.errors import COMMON_ERROR_RESPONSES

router = APIRouter(prefix="/v1/copilot", tags=["copilot"])
ActorConnection = Annotated[tuple[Actor, asyncpg.Connection], Depends(get_actor_connection)]
SettingsDependency = Annotated[Settings, Depends(get_settings)]
ActorDependency = Annotated[Actor, Depends(get_current_actor)]
DatabaseDependency = Annotated[Database, Depends(get_database)]
RateLimiterDependency = Annotated[RedisRateLimiter, Depends(get_rate_limiter)]


class CopilotQuestionRequest(BaseModel):
    question: str = Field(min_length=1, max_length=2000)
    conversation_id: str | None = None


class CreateConversationRequest(BaseModel):
    title: str | None = Field(default=None, max_length=120)


class CopilotSourceResponse(BaseModel):
    sighting_id: str
    observation_reference: str
    species_common_name: str
    field_notes: str
    similarity: float
    source_type: str = "sighting"


class CopilotAnswerResponse(BaseModel):
    answer: str
    model_name: str
    input_tokens: int
    output_tokens: int
    sources: list[CopilotSourceResponse]
    conversation_id: str


class CopilotConversationResponse(BaseModel):
    conversation_id: str
    title: str
    created_at: datetime
    updated_at: datetime
    message_count: int


class CopilotConversationListResponse(BaseModel):
    items: list[CopilotConversationResponse]


class CopilotMessageResponse(BaseModel):
    message_id: str
    conversation_id: str
    sender_role: str
    message_text: str
    model_name: str | None = None
    created_at: datetime
    citations: list[CopilotSourceResponse]


class CopilotMessageListResponse(BaseModel):
    items: list[CopilotMessageResponse]


def _source_response(source: CopilotSource) -> CopilotSourceResponse:
    return CopilotSourceResponse(
        sighting_id=str(source.sighting_id),
        observation_reference=source.observation_reference,
        species_common_name=source.species_common_name,
        field_notes=source.field_notes,
        similarity=source.similarity,
        source_type=source.source_type,
    )


@router.get(
    "/conversations",
    response_model=CopilotConversationListResponse,
    responses=COMMON_ERROR_RESPONSES,
)
async def list_conversations(
    actor_connection: ActorConnection,
) -> CopilotConversationListResponse:
    _, connection = actor_connection
    items = await PostgresCopilotConversationRepository(connection).list_conversations(limit=50)
    return CopilotConversationListResponse(
        items=[
            CopilotConversationResponse(
                conversation_id=str(c.conversation_id),
                title=c.title,
                created_at=c.created_at,
                updated_at=c.updated_at,
                message_count=c.message_count,
            )
            for c in items
        ]
    )


@router.post(
    "/conversations",
    response_model=CopilotConversationResponse,
    status_code=status.HTTP_201_CREATED,
    responses=COMMON_ERROR_RESPONSES,
)
async def create_conversation(
    payload: CreateConversationRequest,
    actor: ActorDependency,
    database: DatabaseDependency,
) -> CopilotConversationResponse:
    title = payload.title or "Nueva consulta"
    async with database.actor_transaction(actor.researcher_id) as connection:
        conv_id = await PostgresCopilotConversationRepository(connection).create_conversation(title=title)
    return CopilotConversationResponse(
        conversation_id=str(conv_id),
        title=title,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
        message_count=0,
    )



@router.get(
    "/conversations/{conversation_id}/messages",
    response_model=CopilotMessageListResponse,
    responses=COMMON_ERROR_RESPONSES,
)
async def get_conversation_messages(
    conversation_id: UUID,
    actor: ActorDependency,
    database: DatabaseDependency,
) -> CopilotMessageListResponse:
    async with database.actor_transaction(actor.researcher_id) as connection:
        messages = await PostgresCopilotConversationRepository(connection).get_messages(conversation_id)
    return CopilotMessageListResponse(
        items=[
            CopilotMessageResponse(
                message_id=str(m.message_id),
                conversation_id=str(m.conversation_id),
                sender_role=m.sender_role,
                message_text=m.message_text,
                model_name=m.model_name,
                created_at=m.created_at,
                citations=[_source_response(s) for s in m.citations],
            )
            for m in messages
        ]
    )


@router.delete(
    "/conversations/{conversation_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    responses=COMMON_ERROR_RESPONSES,
)
async def delete_conversation(
    conversation_id: UUID,
    actor: ActorDependency,
    database: DatabaseDependency,
    rate_limiter: RateLimiterDependency,
) -> Response:
    async with database.actor_transaction(actor.researcher_id) as connection:
        await PostgresCopilotConversationRepository(connection).delete_conversation(conversation_id)
    memory = RedisConversationMemory(rate_limiter._redis)
    await memory.clear_conversation(actor.researcher_id, conversation_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)



@router.post("/ask", response_model=CopilotAnswerResponse, responses=COMMON_ERROR_RESPONSES)
async def ask(
    payload: CopilotQuestionRequest,
    actor: ActorDependency,
    database: DatabaseDependency,
    settings: SettingsDependency,
    rate_limiter: RateLimiterDependency,
) -> CopilotAnswerResponse:
    decision = await rate_limiter.check(
        key=f"bioma:rl:copilot:{actor.researcher_id}",
        limit=settings.rate_limit_copilot,
        window_seconds=settings.rate_limit_window_seconds,
    )
    if not decision.allowed:
        raise RateLimitExceeded(decision.retry_after)

    embeddings, copilot = build_ai_gateway(settings)
    memory = RedisConversationMemory(rate_limiter._redis)

    # 1. Resolve conversation ID (create one if not provided or invalid)
    target_conversation_id: UUID | None = None
    if payload.conversation_id:
        try:
            target_conversation_id = UUID(payload.conversation_id)
        except ValueError:
            target_conversation_id = None

    if target_conversation_id is None:
        async with database.actor_transaction(actor.researcher_id) as connection:
            target_conversation_id = await PostgresCopilotConversationRepository(
                connection
            ).create_conversation(title=payload.question.strip())

    # 2. Retrieve recent 16 messages context from Redis (or fallback to DB)
    recent_messages = await memory.get_recent_messages(actor.researcher_id, target_conversation_id)
    if not recent_messages:
        async with database.actor_transaction(actor.researcher_id) as connection:
            db_messages = await PostgresCopilotConversationRepository(
                connection
            ).get_messages(target_conversation_id)
            if db_messages:
                from app.domain.models import ConversationMessage
                recent_messages = [
                    ConversationMessage(role=m.sender_role, content=m.message_text)
                    for m in db_messages[-16:]
                ]

    # 3. Context retrieval with PostgreSQL RLS
    async def retrieve_context(embedding: Sequence[float]) -> list[CopilotSource]:
        async with database.actor_transaction(actor.researcher_id) as connection:
            return await PostgresSightingRepository(connection).retrieve_context(embedding, limit=5)

    async def retrieve_catalog(embedding: Sequence[float]) -> list[CatalogKnowledgeItem]:
        async with database.actor_transaction(actor.researcher_id) as connection:
            return await PostgresSightingRepository(connection).get_knowledge_catalog(embedding)

    async def record_audit(**kwargs: object) -> UUID:
        async with database.actor_transaction(actor.researcher_id) as connection:
            return await PostgresCopilotAuditRepository(connection).record(**kwargs)

    async with database.actor_transaction(actor.researcher_id) as connection:
        field_prompt = await connection.fetchrow("SELECT * FROM bio_fn_get_active_system_prompt('field')")
        greeting_prompt = await connection.fetchrow("SELECT * FROM bio_fn_get_active_system_prompt('greeting')")

    # 4. Execute copilot question with conversation history and catalog knowledge
    answer = await AnswerCopilotQuestion(
        embeddings=embeddings,
        copilot=copilot,
        context=retrieve_context,
        audit=record_audit,
        catalog=retrieve_catalog,
    ).execute(
        actor=actor, question=payload.question, history=recent_messages,
        system_prompt=field_prompt["prompt_text"], system_prompt_version=field_prompt["version_key"],
        greeting_prompt=greeting_prompt["prompt_text"],
    )

    if answer.audit_usage_id is None:
        raise RuntimeError("copilot audit did not return a usage identifier")

    # 5. Persist turn in PostgreSQL under RLS
    async with database.actor_transaction(actor.researcher_id) as connection:
        await PostgresCopilotConversationRepository(connection).record_turn(
            conversation_id=target_conversation_id,
            usage_id=answer.audit_usage_id,
            prompt=payload.question.strip(),
            answer=answer.text,
        )

    # 6. Append turn to Redis 16-message context
    await memory.append_turn(
        actor.researcher_id,
        target_conversation_id,
        payload.question.strip(),
        answer.text,
        max_messages=16,
    )

    return CopilotAnswerResponse(
        answer=answer.text,
        model_name=answer.model_name,
        input_tokens=answer.input_tokens,
        output_tokens=answer.output_tokens,
        sources=[_source_response(s) for s in answer.sources],
        conversation_id=str(target_conversation_id),
    )


@router.get("/usage", responses=COMMON_ERROR_RESPONSES)
async def usage_summary(
    actor_connection: ActorConnection,
) -> dict[str, object]:
    _, connection = actor_connection
    row = await connection.fetchrow("SELECT * FROM bio_fn_copilot_usage_summary()")
    return {"item": dict(row) if row else None}
