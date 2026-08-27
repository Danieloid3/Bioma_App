from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from app.domain.models import SightingHistoryItem, SightingSearchItem
from app.domain.ports.repositories import SightingRepository


@dataclass(slots=True)
class ListSightingHistory:
    sightings: SightingRepository

    async def execute(
        self,
        *,
        species_id: UUID | None,
        site_id: UUID | None,
        cursor_observed_at: datetime | None,
        cursor_sighting_id: UUID | None,
        page_size: int,
    ) -> list[SightingHistoryItem]:
        return await self.sightings.history(
            species_id=species_id,
            site_id=site_id,
            cursor_observed_at=cursor_observed_at,
            cursor_sighting_id=cursor_sighting_id,
            page_size=page_size,
        )


@dataclass(slots=True)
class RegisterSighting:
    sightings: SightingRepository

    async def execute(
        self,
        *,
        observation_reference: str,
        species_id: UUID,
        site_id: UUID,
        observed_at: datetime,
        latitude: float,
        longitude: float,
        classification_level: int,
        field_notes: str,
    ) -> UUID:
        return await self.sightings.register(
            observation_reference=observation_reference,
            species_id=species_id,
            site_id=site_id,
            observed_at=observed_at,
            latitude=latitude,
            longitude=longitude,
            classification_level=classification_level,
            field_notes=field_notes.strip(),
        )


@dataclass(slots=True)
class SearchSightings:
    sightings: SightingRepository

    async def execute(
        self,
        *,
        term: str,
        cursor_observed_at: datetime | None,
        cursor_sighting_id: UUID | None,
        page_size: int,
    ) -> list[SightingSearchItem]:
        return await self.sightings.search(
            search_term=term.strip(),
            cursor_observed_at=cursor_observed_at,
            cursor_sighting_id=cursor_sighting_id,
            page_size=page_size,
        )


@dataclass(slots=True)
class EditSighting:
    sightings: SightingRepository

    async def execute(
        self,
        *,
        sighting_id: UUID,
        field_notes: str | None,
        classification_level: int | None,
        latitude: float | None,
        longitude: float | None,
        change_reason: str,
    ) -> None:
        await self.sightings.edit(
            sighting_id=sighting_id,
            field_notes=field_notes.strip() if field_notes is not None else None,
            classification_level=classification_level,
            latitude=latitude,
            longitude=longitude,
            change_reason=change_reason.strip(),
        )


@dataclass(slots=True)
class VoidSighting:
    sightings: SightingRepository

    async def execute(self, *, sighting_id: UUID, reason: str) -> None:
        await self.sightings.void(sighting_id=sighting_id, reason=reason.strip())
