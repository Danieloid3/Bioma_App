from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, Field

from app.domain.models import Actor
from app.infrastructure.db.database import Database
from app.presentation.api.dependencies import get_current_actor, get_database
from app.presentation.api.errors import COMMON_ERROR_RESPONSES

router = APIRouter(prefix="/v1/admin", tags=["administration"])
ActorDependency = Annotated[Actor, Depends(get_current_actor)]
DatabaseDependency = Annotated[Database, Depends(get_database)]


class PromptVersionResponse(BaseModel):
    prompt_id: UUID
    scope: str
    version_key: str
    prompt_text: str
    content_sha256: str
    is_active: bool
    created_at: str
    created_by: str


class CreatePromptVersionRequest(BaseModel):
    scope: str = Field(pattern="^(field|chat|greeting)$")
    prompt_text: str = Field(min_length=40, max_length=20000)


@router.get("/system-prompts", response_model=list[PromptVersionResponse], responses=COMMON_ERROR_RESPONSES)
async def list_system_prompts(actor: ActorDependency, database: DatabaseDependency) -> list[PromptVersionResponse]:
    async with database.actor_transaction(actor.researcher_id) as connection:
        rows = await connection.fetch("SELECT * FROM bio_fn_list_system_prompt_versions()")
    items: list[PromptVersionResponse] = []
    for row in rows:
        item = dict(row)
        item["created_at"] = row["created_at"].isoformat()
        items.append(PromptVersionResponse(**item))
    return items


@router.post(
    "/system-prompts",
    response_model=UUID,
    status_code=status.HTTP_201_CREATED,
    responses=COMMON_ERROR_RESPONSES,
)
async def create_system_prompt(payload: CreatePromptVersionRequest, actor: ActorDependency, database: DatabaseDependency) -> UUID:
    async with database.actor_transaction(actor.researcher_id) as connection:
        return await connection.fetchval("SELECT bio_fn_create_system_prompt_version($1, $2)", payload.scope, payload.prompt_text)


@router.post(
    "/system-prompts/{prompt_id}/activate",
    status_code=status.HTTP_204_NO_CONTENT,
    responses=COMMON_ERROR_RESPONSES,
)
async def activate_system_prompt(prompt_id: UUID, actor: ActorDependency, database: DatabaseDependency) -> None:
    async with database.actor_transaction(actor.researcher_id) as connection:
        await connection.execute("SELECT bio_fn_activate_system_prompt_version($1)", prompt_id)
