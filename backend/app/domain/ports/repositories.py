from datetime import datetime
from typing import Protocol, Sequence
from uuid import UUID

from app.domain.models import CopilotSource, SightingHistoryItem


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

    async def retrieve_context(self, embedding: Sequence[float], limit: int) -> list[CopilotSource]: ...

    async def store_embedding(self, sighting_id: UUID, embedding: Sequence[float], model_name: str) -> None: ...


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

