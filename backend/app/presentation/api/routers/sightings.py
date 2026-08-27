from datetime import datetime
from typing import Annotated
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from pydantic import BaseModel, Field, model_validator

from app.application.use_cases.sightings import (
    EditSighting,
    GetSightingDetail,
    ListSightingHistory,
    RegisterSighting,
    SearchSightings,
    VoidSighting,
)
from app.domain.models import Actor
from app.infrastructure.db.repositories import PostgresSightingRepository
from app.presentation.api.dependencies import get_actor_connection
from app.presentation.api.errors import COMMON_ERROR_RESPONSES

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


class EditSightingRequest(BaseModel):
    field_notes: str | None = Field(default=None, min_length=1)
    classification_level: int | None = Field(default=None, ge=1, le=3)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    change_reason: str = Field(min_length=1, max_length=500)

    @model_validator(mode="after")
    def requires_a_change(self) -> "EditSightingRequest":
        if all(
            value is None
            for value in (
                self.field_notes,
                self.classification_level,
                self.latitude,
                self.longitude,
            )
        ):
            raise ValueError("at least one editable field is required")
        return self


class VoidSightingRequest(BaseModel):
    reason: str = Field(min_length=1, max_length=500)


@router.get("/{sighting_id}", responses=COMMON_ERROR_RESPONSES)
async def get_sighting_detail(
    sighting_id: UUID, actor_connection: ActorConnection
) -> object:
    _, connection = actor_connection
    detail = await GetSightingDetail(PostgresSightingRepository(connection)).execute(
        sighting_id=sighting_id
    )
    if detail is None:
        # A forbidden row is indistinguishable from an unknown UUID by design.
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
    return detail


@router.get("", responses=COMMON_ERROR_RESPONSES)
async def list_sightings(
    actor_connection: ActorConnection,
    species_id: UUID | None = None,
    site_id: UUID | None = None,
    cursor_observed_at: datetime | None = None,
    cursor_sighting_id: UUID | None = None,
    page_size: int = Query(default=20, ge=1, le=100),
) -> dict[str, object]:
    _, connection = actor_connection
    items = await ListSightingHistory(PostgresSightingRepository(connection)).execute(
        species_id=species_id,
        site_id=site_id,
        cursor_observed_at=cursor_observed_at,
        cursor_sighting_id=cursor_sighting_id,
        page_size=page_size,
    )
    return {"items": items}


@router.post("", status_code=status.HTTP_201_CREATED, responses=COMMON_ERROR_RESPONSES)
async def register_sighting(
    payload: RegisterSightingRequest, actor_connection: ActorConnection
) -> dict[str, UUID]:
    _, connection = actor_connection
    sighting_id = await RegisterSighting(PostgresSightingRepository(connection)).execute(
        **payload.model_dump()
    )
    return {"sighting_id": sighting_id}


@router.get("/search", responses=COMMON_ERROR_RESPONSES)
async def search_sightings(
    actor_connection: ActorConnection,
    term: str = Query(min_length=1, max_length=200),
    cursor_observed_at: datetime | None = None,
    cursor_sighting_id: UUID | None = None,
    page_size: int = Query(default=20, ge=1, le=100),
) -> dict[str, object]:
    _, connection = actor_connection
    items = await SearchSightings(PostgresSightingRepository(connection)).execute(
        term=term,
        cursor_observed_at=cursor_observed_at,
        cursor_sighting_id=cursor_sighting_id,
        page_size=page_size,
    )
    return {"items": items}


@router.patch(
    "/{sighting_id}", status_code=status.HTTP_204_NO_CONTENT, responses=COMMON_ERROR_RESPONSES
)
async def edit_sighting(
    sighting_id: UUID, payload: EditSightingRequest, actor_connection: ActorConnection
) -> Response:
    _, connection = actor_connection
    await EditSighting(PostgresSightingRepository(connection)).execute(
        sighting_id=sighting_id, **payload.model_dump()
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/{sighting_id}/void", status_code=status.HTTP_204_NO_CONTENT, responses=COMMON_ERROR_RESPONSES
)
async def void_sighting(
    sighting_id: UUID, payload: VoidSightingRequest, actor_connection: ActorConnection
) -> Response:
    _, connection = actor_connection
    await VoidSighting(PostgresSightingRepository(connection)).execute(
        sighting_id=sighting_id, reason=payload.reason
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)
