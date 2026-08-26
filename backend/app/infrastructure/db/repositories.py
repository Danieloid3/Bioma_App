from collections.abc import Sequence
from datetime import datetime
from uuid import UUID

import asyncpg

from app.domain.models import CopilotSource, SightingHistoryItem


class PostgresSightingRepository:
    def __init__(self, connection: asyncpg.Connection) -> None:
        self._connection = connection

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
    ) -> UUID:
        return await self._connection.fetchval(
            "SELECT bio_fn_register_sighting($1, $2, $3, $4, $5, $6, $7, $8)",
            observation_reference,
            species_id,
            site_id,
            observed_at,
            latitude,
            longitude,
            classification_level,
            field_notes,
        )

    async def history(
        self,
        *,
        species_id: UUID | None,
        site_id: UUID | None,
        cursor_observed_at: datetime | None,
        cursor_sighting_id: UUID | None,
        page_size: int,
    ) -> list[SightingHistoryItem]:
        rows = await self._connection.fetch(
            "SELECT * FROM bio_fn_sighting_history($1, $2, $3, $4, $5, false)",
            species_id,
            site_id,
            cursor_observed_at,
            cursor_sighting_id,
            page_size,
        )
        return [
            SightingHistoryItem(
                sighting_id=row["sighting_id"],
                observation_reference=row["observation_reference"],
                researcher_name=row["researcher_name"],
                species_common_name=row["species_common_name"],
                site_name=row["site_name"],
                classification_level=row["classification_level"],
                field_notes=row["field_notes"],
                observed_at=row["observed_at"],
                is_voided=row["is_voided"],
            )
            for row in rows
        ]

    async def retrieve_context(self, embedding: Sequence[float], limit: int) -> list[CopilotSource]:
        rows = await self._connection.fetch(
            "SELECT * FROM bio_fn_retrieve_copilot_context($1::vector, $2)",
            str(list(embedding)),
            limit,
        )
        return [
            CopilotSource(
                sighting_id=row["sighting_id"],
                observation_reference=row["observation_reference"],
                species_common_name=row["species_common_name"],
                field_notes=row["field_notes"],
                similarity=row["similarity"],
            )
            for row in rows
        ]

    async def store_embedding(self, sighting_id: UUID, embedding: Sequence[float], model_name: str) -> None:
        await self._connection.execute(
            "SELECT bio_fn_store_sighting_embedding($1, $2::vector, $3)",
            sighting_id,
            str(list(embedding)),
            model_name,
        )


class PostgresCopilotAuditRepository:
    def __init__(self, connection: asyncpg.Connection) -> None:
        self._connection = connection

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
    ) -> UUID:
        return await self._connection.fetchval(
            "SELECT bio_fn_log_copilot_usage($1, $2, $3, $4, $5, $6, $7::uuid[], $8::numeric[])",
            prompt,
            answer,
            system_prompt_version,
            model_name,
            input_tokens,
            output_tokens,
            [source.sighting_id for source in sources],
            [source.similarity for source in sources],
        )

