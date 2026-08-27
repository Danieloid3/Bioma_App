from collections.abc import Sequence
from typing import Annotated
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.application.use_cases.answer_copilot_question import AnswerCopilotQuestion
from app.domain.errors import RateLimitExceeded
from app.domain.models import Actor, CopilotAnswer, CopilotSource
from app.infrastructure.ai.factory import build_ai_gateway
from app.infrastructure.config import Settings, get_settings
from app.infrastructure.db.database import Database
from app.infrastructure.db.repositories import (
    PostgresCopilotAuditRepository,
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


class CopilotSourceResponse(BaseModel):
    sighting_id: str
    observation_reference: str
    species_common_name: str
    field_notes: str
    similarity: float


class CopilotAnswerResponse(BaseModel):
    answer: str
    model_name: str
    input_tokens: int
    output_tokens: int
    sources: list[CopilotSourceResponse]


def _response(answer: CopilotAnswer) -> CopilotAnswerResponse:
    return CopilotAnswerResponse(
        answer=answer.text,
        model_name=answer.model_name,
        input_tokens=answer.input_tokens,
        output_tokens=answer.output_tokens,
        sources=[
            CopilotSourceResponse(
                sighting_id=str(source.sighting_id),
                observation_reference=source.observation_reference,
                species_common_name=source.species_common_name,
                field_notes=source.field_notes,
                similarity=source.similarity,
            )
            for source in answer.sources
        ],
    )


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

    async def retrieve_context(embedding: Sequence[float]) -> list[CopilotSource]:
        async with database.actor_transaction(actor.researcher_id) as connection:
            return await PostgresSightingRepository(connection).retrieve_context(embedding, limit=5)

    async def record_audit(**kwargs: object) -> UUID:
        async with database.actor_transaction(actor.researcher_id) as connection:
            return await PostgresCopilotAuditRepository(connection).record(**kwargs)

    answer = await AnswerCopilotQuestion(
        embeddings=embeddings,
        copilot=copilot,
        context=retrieve_context,
        audit=record_audit,
    ).execute(actor=actor, question=payload.question)
    return _response(answer)


@router.get("/usage", responses=COMMON_ERROR_RESPONSES)
async def usage_summary(
    actor_connection: ActorConnection,
) -> dict[str, object]:
    _, connection = actor_connection
    row = await connection.fetchrow("SELECT * FROM bio_fn_copilot_usage_summary()")
    return {"item": dict(row) if row else None}
