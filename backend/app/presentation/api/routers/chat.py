import json
import re
from dataclasses import asdict
from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from app.application.use_cases.answer_copilot_question import AnswerCopilotQuestion
from app.domain.models import Actor, ConversationMessage
from app.infrastructure.ai.factory import build_ai_gateway
from app.infrastructure.chat_events import CHAT_EVENTS_CHANNEL, ChatEvent, RedisChatEventPublisher
from app.infrastructure.config import Settings, get_settings
from app.infrastructure.db.database import Database
from app.infrastructure.db.repositories import (
    PostgresChatRepository,
    PostgresCopilotAuditRepository,
    PostgresSightingRepository,
)
from app.infrastructure.rate_limit import RedisRateLimiter
from app.presentation.api.dependencies import get_current_actor, get_database, get_rate_limiter
from app.presentation.api.errors import COMMON_ERROR_RESPONSES

router = APIRouter(prefix="/v1/chat", tags=["chat"])
ActorDependency = Annotated[Actor, Depends(get_current_actor)]
DatabaseDependency = Annotated[Database, Depends(get_database)]
RateLimiterDependency = Annotated[RedisRateLimiter, Depends(get_rate_limiter)]


class CreateChannelRequest(BaseModel):
    channel_type: str = Field(pattern="^(direct|group)$")
    name: str | None = Field(default=None, max_length=120)
    member_ids: list[UUID] = Field(min_length=1, max_length=100)


class SendMessageRequest(BaseModel):
    message_text: str = Field(min_length=1, max_length=4000)


class AddMembersRequest(BaseModel):
    member_ids: list[UUID] = Field(min_length=1, max_length=100)


class ChannelResponse(BaseModel):
    channel_id: UUID
    channel_type: str
    name: str | None
    created_at: datetime
    updated_at: datetime
    message_count: int
    unread_count: int
    last_message_at: datetime | None
    display_name: str


class ChannelMemberResponse(BaseModel):
    researcher_id: UUID
    full_name: str
    role_title: str
    accreditation_level: int
    avatar_key: str


class MessageResponse(BaseModel):
    message_id: UUID
    channel_id: UUID
    author_id: UUID | None = None
    author_name: str
    sender_role: str
    message_text: str
    is_edited: bool
    is_deleted: bool = False
    created_at: datetime
    read_count: int
    citations: list[dict[str, str]] = Field(default_factory=list)



class ChatCopilotRequest(BaseModel):
    question: str = Field(min_length=1, max_length=2000)


class ChatCopilotResponse(BaseModel):
    answer: str
    sources: list[dict[str, object]]
    model_name: str


def _channel(item: object) -> ChannelResponse:
    return ChannelResponse(**asdict(item))


def _message(item: object) -> MessageResponse:
    return MessageResponse(**asdict(item))


@router.get("/channels", response_model=list[ChannelResponse], responses=COMMON_ERROR_RESPONSES)
async def list_channels(actor: ActorDependency, database: DatabaseDependency) -> list[ChannelResponse]:
    async with database.actor_transaction(actor.researcher_id) as connection:
        items = await PostgresChatRepository(connection).list_channels()
    return [_channel(item) for item in items]


async def _is_channel_member(database: Database, actor: Actor, channel_id: UUID) -> bool:
    """Re-check RLS-backed membership immediately before emitting an event."""
    async with database.actor_transaction(actor.researcher_id) as connection:
        return bool(await connection.fetchval("SELECT bio_fn_is_chat_member($1)", channel_id))


@router.get("/events", responses=COMMON_ERROR_RESPONSES)
async def stream_events(
    actor: ActorDependency,
    database: DatabaseDependency,
    rate_limiter: RateLimiterDependency,
) -> StreamingResponse:
    """Authenticated SSE invalidations; clients reload data through the normal RLS API."""
    async def event_stream():
        pubsub = rate_limiter.client.pubsub()
        await pubsub.subscribe(CHAT_EVENTS_CHANNEL)
        try:
            yield ": connected\n\n"
            while True:
                message = await pubsub.get_message(ignore_subscribe_messages=True, timeout=15.0)
                if message is None:
                    yield ": heartbeat\n\n"
                    continue
                event = ChatEvent.from_json(message.get("data"))
                if event is None:
                    continue
                if await _is_channel_member(database, actor, event.channel_id):
                    data = json.dumps({"type": event.type, "channel_id": str(event.channel_id)})
                    yield f"event: chat\ndata: {data}\n\n"
        finally:
            await pubsub.unsubscribe(CHAT_EVENTS_CHANNEL)
            await pubsub.aclose()

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache, no-transform",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.post("/channels", response_model=ChannelResponse, status_code=status.HTTP_201_CREATED, responses=COMMON_ERROR_RESPONSES)
async def create_channel(
    payload: CreateChannelRequest,
    actor: ActorDependency,
    database: DatabaseDependency,
    rate_limiter: RateLimiterDependency,
) -> ChannelResponse:
    async with database.actor_transaction(actor.researcher_id) as connection:
        repository = PostgresChatRepository(connection)
        channel_id = await repository.create_channel(payload.channel_type, payload.name, payload.member_ids)
        items = await repository.list_channels()
    await RedisChatEventPublisher(rate_limiter.client).publish("channel.created", channel_id)
    return next(_channel(item) for item in items if item.channel_id == channel_id)


@router.get("/channels/{channel_id}/messages", response_model=list[MessageResponse], responses=COMMON_ERROR_RESPONSES)
async def history(channel_id: UUID, actor: ActorDependency, database: DatabaseDependency, rate_limiter: RateLimiterDependency, cursor_created_at: datetime | None = None, cursor_message_id: UUID | None = None, limit: int = Query(default=50, ge=1, le=100)) -> list[MessageResponse]:
    async with database.actor_transaction(actor.researcher_id) as connection:
        repository = PostgresChatRepository(connection)
        pending_count = await repository.mark_channel_read(channel_id)
        items = await repository.history(channel_id, cursor_created_at, cursor_message_id, limit)
    # Opening a channel marks this actor's pending receipts as read. The event
    # carries no content; other members refresh through their RLS-protected API.
    if pending_count:
        await RedisChatEventPublisher(rate_limiter.client).publish("message.read", channel_id)
    return [_message(item) for item in items]


@router.get("/channels/{channel_id}/members", response_model=list[ChannelMemberResponse], responses=COMMON_ERROR_RESPONSES)
async def channel_members(channel_id: UUID, actor: ActorDependency, database: DatabaseDependency) -> list[ChannelMemberResponse]:
    async with database.actor_transaction(actor.researcher_id) as connection:
        items = await PostgresChatRepository(connection).members(channel_id)
    return [ChannelMemberResponse(**asdict(item)) for item in items]


@router.post("/channels/{channel_id}/members", status_code=status.HTTP_204_NO_CONTENT, responses=COMMON_ERROR_RESPONSES)
async def add_channel_members(
    channel_id: UUID,
    payload: AddMembersRequest,
    actor: ActorDependency,
    database: DatabaseDependency,
    rate_limiter: RateLimiterDependency,
) -> Response:
    async with database.actor_transaction(actor.researcher_id) as connection:
        await PostgresChatRepository(connection).add_members(channel_id, payload.member_ids)
    await RedisChatEventPublisher(rate_limiter.client).publish("channel.updated", channel_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/channels/{channel_id}/leave", status_code=status.HTTP_204_NO_CONTENT, responses=COMMON_ERROR_RESPONSES)
async def leave_channel(
    channel_id: UUID,
    actor: ActorDependency,
    database: DatabaseDependency,
    rate_limiter: RateLimiterDependency,
) -> Response:
    async with database.actor_transaction(actor.researcher_id) as connection:
        await PostgresChatRepository(connection).leave(channel_id)
    await RedisChatEventPublisher(rate_limiter.client).publish("channel.updated", channel_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/channels/{channel_id}/messages", response_model=MessageResponse, status_code=status.HTTP_201_CREATED, responses=COMMON_ERROR_RESPONSES)
async def send_message(
    channel_id: UUID,
    payload: SendMessageRequest,
    actor: ActorDependency,
    database: DatabaseDependency,
    rate_limiter: RateLimiterDependency,
) -> MessageResponse:
    async with database.actor_transaction(actor.researcher_id) as connection:
        repository = PostgresChatRepository(connection)
        message_id = await repository.send(channel_id, payload.message_text)
        messages = await repository.history(channel_id, None, None, 1)
    await RedisChatEventPublisher(rate_limiter.client).publish("message.created", channel_id)
    return next(_message(item) for item in messages if item.message_id == message_id)


@router.post("/channels/{channel_id}/copilot", response_model=ChatCopilotResponse, responses=COMMON_ERROR_RESPONSES)
async def ask_channel_copilot(
    channel_id: UUID, payload: ChatCopilotRequest, actor: ActorDependency, database: DatabaseDependency,
    settings: Annotated[Settings, Depends(get_settings)],
    rate_limiter: RateLimiterDependency,
) -> ChatCopilotResponse:
    """Answer `@copilot` with shared visibility, never the sender's privileged view."""
    embeddings, copilot = build_ai_gateway(settings)

    async def retrieve(embedding: list[float]):
        async with database.actor_transaction(actor.researcher_id) as connection:
            repository = PostgresChatRepository(connection)
            messages = await repository.retrieve_message_context(channel_id, embedding)
            sightings = await repository.retrieve_shared_sighting_context(channel_id, embedding)
            return [*messages, *sightings]

    async def catalog():
        async with database.actor_transaction(actor.researcher_id) as connection:
            return await PostgresSightingRepository(connection).get_knowledge_catalog()

    async def audit(**kwargs: object):
        async with database.actor_transaction(actor.researcher_id) as connection:
            return await PostgresCopilotAuditRepository(connection).record(**kwargs)

    async with database.actor_transaction(actor.researcher_id) as connection:
        repository = PostgresChatRepository(connection)
        chat_prompt = await connection.fetchrow("SELECT * FROM bio_fn_get_active_system_prompt('chat')")
        greeting_prompt = await connection.fetchrow("SELECT * FROM bio_fn_get_active_system_prompt('greeting')")
        # El historial conversacional se recupera bajo RLS. Se excluye la invocación
        # actual porque se envía como pregunta explícita al proveedor.
        recent_messages = await repository.history(channel_id, None, None, 16)

    current_message = f"@copilot {payload.question}".strip().casefold()
    conversation_history = [
        ConversationMessage(
            role="assistant" if item.sender_role == "copilot" else "user",
            # Previous assistant citations are not evidence for this turn. They
            # are removed from the conversational transcript so the model cannot
            # copy an old reference that is absent from the current RLS result.
            content=(
                re.sub(r"\[obs-[A-Za-z0-9-]+\]", "", item.message_text, flags=re.IGNORECASE)
                if item.sender_role == "copilot" else item.message_text
            ),
        )
        for item in reversed(recent_messages)
        if item.message_text.strip().casefold() != current_message
    ]

    safe_chat_prompt = (
        f"{chat_prompt['prompt_text']}\n\n"
        "Regla adicional de conversación: usa los mensajes recientes para entender el contexto. "
        "No atribuyas un animal, especie o hecho a un avistamiento si la fuente no lo respalda "
        "de forma directa. Si una fuente RAG es irrelevante o contradice el mensaje conversacional, "
        "ignórala y no la cites. Una referencia solo puede aparecer junto al dato exacto que demuestra."
    )

    answer = await AnswerCopilotQuestion(
        embeddings=embeddings, copilot=copilot, context=retrieve, audit=audit, catalog=catalog
    ).execute(
        actor=actor, question=payload.question, system_prompt=safe_chat_prompt,
        system_prompt_version=chat_prompt["version_key"], greeting_prompt=greeting_prompt["prompt_text"],
        history=conversation_history,
    )

    sources = [{
        "type": source.source_type, "reference": source.observation_reference, "id": str(source.sighting_id)
    } for source in answer.sources]
    async with database.actor_transaction(actor.researcher_id) as connection:
        await PostgresChatRepository(connection).record_copilot_response(channel_id, answer.text, sources)
    await RedisChatEventPublisher(rate_limiter.client).publish("message.created", channel_id)
    return ChatCopilotResponse(answer=answer.text, model_name=answer.model_name, sources=sources)


@router.patch("/messages/{message_id}", status_code=status.HTTP_204_NO_CONTENT, responses=COMMON_ERROR_RESPONSES)
async def edit_message(
    message_id: UUID,
    payload: SendMessageRequest,
    actor: ActorDependency,
    database: DatabaseDependency,
    rate_limiter: RateLimiterDependency,
) -> None:
    async with database.actor_transaction(actor.researcher_id) as connection:
        repository = PostgresChatRepository(connection)
        channel_id = await repository.message_channel_id(message_id)
        await repository.edit(message_id, payload.message_text)
    if channel_id is not None:
        await RedisChatEventPublisher(rate_limiter.client).publish("message.updated", channel_id)


@router.delete("/messages/{message_id}", status_code=status.HTTP_204_NO_CONTENT, responses=COMMON_ERROR_RESPONSES)
async def delete_message(
    message_id: UUID,
    actor: ActorDependency,
    database: DatabaseDependency,
    rate_limiter: RateLimiterDependency,
) -> None:
    async with database.actor_transaction(actor.researcher_id) as connection:
        repository = PostgresChatRepository(connection)
        channel_id = await repository.message_channel_id(message_id)
        await repository.delete(message_id)
    if channel_id is not None:
        await RedisChatEventPublisher(rate_limiter.client).publish("message.deleted", channel_id)
