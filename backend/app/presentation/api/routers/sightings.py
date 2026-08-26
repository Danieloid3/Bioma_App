from datetime import datetime
from typing import Annotated
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Query, status
from pydantic import BaseModel, Field

from app.domain.models import Actor
from app.infrastructure.db.repositories import PostgresSightingRepository
from app.presentation.api.dependencies import get_actor_connection

router = APIRouter(prefix="/v1/sightings", tags=["sightings"])
ActorConnection = Annotated[tuple[Actor, asyncpg.Connection], Depends(get_actor_connection)]


class RegisterSightingRequest(BaseModel):
    observation_reference: str = Field(pattern=r"^obs-[A-Za-z0-9-]+$", max_length=30)
    species_id: UUID
    site_id: UUID
    observed_at: datetime
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    classification_level: int = Field(ge=1, le=3)
    field_notes: str = Field(min_length=1)


@router.get("")
async def list_sightings(
    actor_connection: ActorConnection,
    species_id: UUID | None = None,
    site_id: UUID | None = None,
    cursor_observed_at: datetime | None = None,
    cursor_sighting_id: UUID | None = None,
    page_size: int = Query(default=20, ge=1, le=100),
) -> dict[str, object]:
    _, connection = actor_connection
    items = await PostgresSightingRepository(connection).history(
        species_id=species_id,
        site_id=site_id,
        cursor_observed_at=cursor_observed_at,
        cursor_sighting_id=cursor_sighting_id,
        page_size=page_size,
    )
    return {"items": items}


@router.post("", status_code=status.HTTP_201_CREATED)
async def register_sighting(
    payload: RegisterSightingRequest, actor_connection: ActorConnection
) -> dict[str, UUID]:
    _, connection = actor_connection
    sighting_id = await PostgresSightingRepository(connection).register(**payload.model_dump())
    return {"sighting_id": sighting_id}
