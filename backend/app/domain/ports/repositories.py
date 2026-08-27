from datetime import datetime
from typing import Protocol, Sequence
from uuid import UUID

from app.domain.models import (
    ActivityItem,
    ClassificationCount,
    CopilotSource,
    DashboardSummary,
    SightingHistoryItem,
    SightingSearchItem,
    Site,
    Species,
    ResearcherDirectoryItem,
)


class SightingRepository(Protocol):
    async def register(
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
    ) -> UUID: ...

    async def history(
        self,
        *,
        species_id: UUID | None,
        site_id: UUID | None,
        cursor_observed_at: datetime | None,
        cursor_sighting_id: UUID | None,
        page_size: int,
    ) -> list[SightingHistoryItem]: ...

    async def retrieve_context(
        self, embedding: Sequence[float], limit: int
    ) -> list[CopilotSource]: ...

    async def store_embedding(
        self, sighting_id: UUID, embedding: Sequence[float], model_name: str
    ) -> None: ...

    async def search(
        self,
        *,
        search_term: str,
        cursor_observed_at: datetime | None,
        cursor_sighting_id: UUID | None,
        page_size: int,
    ) -> list[SightingSearchItem]: ...

    async def edit(
        self,
        *,
        sighting_id: UUID,
        field_notes: str | None,
        classification_level: int | None,
        latitude: float | None,
        longitude: float | None,
        change_reason: str,
    ) -> None: ...

    async def void(self, *, sighting_id: UUID, reason: str) -> None: ...


class CatalogRepository(Protocol):
    async def list_species(self) -> list[Species]: ...

    async def list_sites(self) -> list[Site]: ...

    async def list_researchers(self) -> list[ResearcherDirectoryItem]: ...


class DashboardRepository(Protocol):
    async def summary(self) -> DashboardSummary: ...

    async def classification(self) -> list[ClassificationCount]: ...

    async def activity(self, limit: int) -> list[ActivityItem]: ...


class CopilotAuditRepository(Protocol):
    async def record(
        self,
        *,
        prompt: str,
        answer: str,
        system_prompt_version: str,
        model_name: str,
        input_tokens: int,
        output_tokens: int,
        sources: Sequence[CopilotSource],
    ) -> UUID: ...


class CopilotContextRepository(Protocol):
    async def retrieve_context(
        self, embedding: Sequence[float], limit: int
    ) -> list[CopilotSource]: ...
