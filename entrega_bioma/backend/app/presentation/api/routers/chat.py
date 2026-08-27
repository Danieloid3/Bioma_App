from dataclasses import asdict
from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
from pydantic import BaseModel, Field

from app.application.use_cases.answer_copilot_question import AnswerCopilotQuestion
from app.domain.models import Actor
from app.infrastructure.ai.factory import build_ai_gateway
from app.infrastructure.config import Settings, get_settings
from app.infrastructure.db.database import Database
from app.infrastructure.db.repositories import (
    PostgresChatRepository,
    PostgresCopilotAuditRepository,
    PostgresSightingRepository,
)
from app.presentation.api.dependencies import get_current_actor, get_database
from app.presentation.api.errors import COMMON_ERROR_RESPONSES

router = APIRouter(prefix="/v1/chat", tags=["chat"])
ActorDependency = Annotated[Actor, Depends(get_current_actor)]
DatabaseDependency = Annotated[Database, Depends(get_database)]


class CreateChannelRequest(BaseModel):
    channel_type: str = Field(pattern="^(direct|group)$")
    name: str | None = Field(default=None, max_length=120)
    member_ids: list[UUID] = Field(min_length=1, max_length=100)


class SendMessageRequest(BaseModel):
    message_text: str = Field(min_length=1, max_length=4000)


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


@router.post("/channels", response_model=ChannelResponse, status_code=status.HTTP_201_CREATED, responses=COMMON_ERROR_RESPONSES)
async def create_channel(payload: CreateChannelRequest, actor: ActorDependency, database: DatabaseDependency) -> ChannelResponse:
    async with database.actor_transaction(actor.researcher_id) as connection:
        repository = PostgresChatRepository(connection)
        channel_id = await repository.create_channel(payload.channel_type, payload.name, payload.member_ids)
        items = await repository.list_channels()
    return next(_channel(item) for item in items if item.channel_id == channel_id)


@router.get("/channels/{channel_id}/messages", response_model=list[MessageResponse], responses=COMMON_ERROR_RESPONSES)
async def history(channel_id: UUID, actor: ActorDependency, database: DatabaseDependency, cursor_created_at: datetime | None = None, cursor_message_id: UUID | None = None, limit: int = Query(default=50, ge=1, le=100)) -> list[MessageResponse]:
    async with database.actor_transaction(actor.researcher_id) as connection:
        items = await PostgresChatRepository(connection).history(channel_id, cursor_created_at, cursor_message_id, limit)
    return [_message(item) for item in items]


@router.get("/channels/{channel_id}/members", response_model=list[ChannelMemberResponse], responses=COMMON_ERROR_RESPONSES)
async def channel_members(channel_id: UUID, actor: ActorDependency, database: DatabaseDependency) -> list[ChannelMemberResponse]:
    async with database.actor_transaction(actor.researcher_id) as connection:
        items = await PostgresChatRepository(connection).members(channel_id)
    return [ChannelMemberResponse(**asdict(item)) for item in items]


@router.post("/channels/{channel_id}/messages", response_model=MessageResponse, status_code=status.HTTP_201_CREATED, responses=COMMON_ERROR_RESPONSES)
async def send_message(channel_id: UUID, payload: SendMessageRequest, actor: ActorDependency, database: DatabaseDependency) -> MessageResponse:
    async with database.actor_transaction(actor.researcher_id) as connection:
        repository = PostgresChatRepository(connection)
        message_id = await repository.send(channel_id, payload.message_text)
        messages = await repository.history(channel_id, None, None, 1)
    return next(_message(item) for item in messages if item.message_id == message_id)


@router.post("/channels/{channel_id}/copilot", response_model=ChatCopilotResponse, responses=COMMON_ERROR_RESPONSES)
async def ask_channel_copilot(
    channel_id: UUID, payload: ChatCopilotRequest, actor: ActorDependency, database: DatabaseDependency,
    settings: Annotated[Settings, Depends(get_settings)],
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
        chat_prompt = await connection.fetchrow("SELECT * FROM bio_fn_get_active_system_prompt('chat')")
        greeting_prompt = await connection.fetchrow("SELECT * FROM bio_fn_get_active_system_prompt('greeting')")

    answer = await AnswerCopilotQuestion(
        embeddings=embeddings, copilot=copilot, context=retrieve, audit=audit, catalog=catalog
    ).execute(
        actor=actor, question=payload.question, system_prompt=chat_prompt["prompt_text"],
        system_prompt_version=chat_prompt["version_key"], greeting_prompt=greeting_prompt["prompt_text"],
    )

    sources = [{
        "type": source.source_type, "reference": source.observation_reference, "id": str(source.sighting_id)
    } for source in answer.sources]
    async with database.actor_transaction(actor.researcher_id) as connection:
        await PostgresChatRepository(connection).record_copilot_response(channel_id, answer.text, sources)
    return ChatCopilotResponse(answer=answer.text, model_name=answer.model_name, sources=sources)


@router.patch("/messages/{message_id}", status_code=status.HTTP_204_NO_CONTENT, responses=COMMON_ERROR_RESPONSES)
async def edit_message(message_id: UUID, payload: SendMessageRequest, actor: ActorDependency, database: DatabaseDependency) -> None:
    async with database.actor_transaction(actor.researcher_id) as connection:
        await PostgresChatRepository(connection).edit(message_id, payload.message_text)


@router.delete("/messages/{message_id}", status_code=status.HTTP_204_NO_CONTENT, responses=COMMON_ERROR_RESPONSES)
async def delete_message(message_id: UUID, actor: ActorDependency, database: DatabaseDependency) -> None:
    async with database.actor_transaction(actor.researcher_id) as connection:
        await PostgresChatRepository(connection).delete(message_id)
