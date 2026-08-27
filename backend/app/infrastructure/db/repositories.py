from collections.abc import Sequence
from datetime import datetime
from uuid import UUID

import asyncpg

from app.domain.errors import InvalidRefreshToken, RefreshTokenReuseDetected
from app.domain.models import (
    ActivityItem,
    Actor,
    ClassificationCount,
    CopilotSource,
    DashboardSummary,
    LoginResearcher,
    ResearcherDirectoryItem,
    SightingHistoryItem,
    SightingDetail,
    SightingSearchItem,
    Site,
    Species,
)


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
            "SELECT * FROM bio_fn_sighting_history_with_images($1, $2, $3, $4, $5, false)",
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
                image_url=row["image_url"],
                image_alt_text_es=row["image_alt_text_es"],
            )
            for row in rows
        ]

    async def get_detail(self, *, sighting_id: UUID) -> SightingDetail | None:
        row = await self._connection.fetchrow(
            "SELECT * FROM bio_fn_get_sighting_detail($1)", sighting_id
        )
        if row is None:
            return None
        return SightingDetail(
            sighting_id=row["sighting_id"],
            observation_reference=row["observation_reference"],
            researcher_id=row["researcher_id"],
            researcher_name=row["researcher_name"],
            species_id=row["species_id"],
            species_common_name=row["species_common_name"],
            species_scientific_name=row["species_scientific_name"],
            species_iucn_category=row["species_iucn_category"],
            site_id=row["site_id"],
            site_name=row["site_name"],
            region=row["region"],
            observed_at=row["observed_at"],
            exact_latitude=float(row["exact_latitude"]),
            exact_longitude=float(row["exact_longitude"]),
            classification_level=row["classification_level"],
            field_notes=row["field_notes"],
            is_voided=row["is_voided"],
            voided_at=row["voided_at"],
            voided_by_researcher_id=row["voided_by_researcher_id"],
            void_reason=row["void_reason"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            image_url=row["image_url"],
            image_alt_text_es=row["image_alt_text_es"],
            image_attribution=row["image_attribution"],
            image_license_code=row["image_license_code"],
            image_license_url=row["image_license_url"],
        )

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

    async def store_embedding(
        self, sighting_id: UUID, embedding: Sequence[float], model_name: str
    ) -> None:
        await self._connection.execute(
            "SELECT bio_fn_store_sighting_embedding($1, $2::vector, $3)",
            sighting_id,
            str(list(embedding)),
            model_name,
        )

    async def claim_embedding_job(self) -> tuple[UUID, str, int] | None:
        row = await self._connection.fetchrow("SELECT * FROM bio_fn_claim_embedding_job()")
        if row is None:
            return None
        return row["sighting_id"], row["field_notes"], row["embedding_attempts"]

    async def mark_embedding_failed(self, sighting_id: UUID, error: str) -> None:
        await self._connection.execute(
            "SELECT bio_fn_mark_embedding_failed($1, $2)", sighting_id, error
        )

    async def search(
        self,
        *,
        search_term: str,
        cursor_observed_at: datetime | None,
        cursor_sighting_id: UUID | None,
        page_size: int,
    ) -> list[SightingSearchItem]:
        rows = await self._connection.fetch(
            "SELECT * FROM bio_fn_search_field_notes($1, $2, $3, $4)",
            search_term,
            cursor_observed_at,
            cursor_sighting_id,
            page_size,
        )
        return [
            SightingSearchItem(
                sighting_id=row["sighting_id"],
                observation_reference=row["observation_reference"],
                researcher_name=row["researcher_name"],
                species_common_name=row["species_common_name"],
                site_name=row["site_name"],
                field_notes_highlight=row["field_notes_highlight"],
                classification_level=row["classification_level"],
                observed_at=row["observed_at"],
            )
            for row in rows
        ]

    async def edit(
        self,
        *,
        sighting_id: UUID,
        field_notes: str | None,
        classification_level: int | None,
        latitude: float | None,
        longitude: float | None,
        change_reason: str,
    ) -> None:
        await self._connection.execute(
            "CALL bio_sp_edit_sighting($1, $2, $3, $4, $5, $6)",
            sighting_id,
            field_notes,
            classification_level,
            latitude,
            longitude,
            change_reason,
        )

    async def void(self, *, sighting_id: UUID, reason: str) -> None:
        await self._connection.execute("CALL bio_sp_void_sighting($1, $2)", sighting_id, reason)


class PostgresCatalogRepository:
    def __init__(self, connection: asyncpg.Connection) -> None:
        self._connection = connection

    async def list_species(self) -> list[Species]:
        rows = await self._connection.fetch(
            """
            SELECT sp.bio_species_id, sp.bio_common_name, sp.bio_scientific_name, sp.bio_iucn_category,
                   image.bio_display_url, image.bio_alt_text_es, image.bio_alt_text_en,
                   image.bio_attribution, image.bio_license_code, image.bio_license_url
            FROM bio_species AS sp
            LEFT JOIN bio_species_images AS image
              ON image.bio_species_id = sp.bio_species_id
             AND image.bio_is_featured = true AND image.bio_is_active = true
            ORDER BY sp.bio_common_name, sp.bio_species_id
            """
        )
        return [
            Species(
                species_id=row["bio_species_id"],
                common_name=row["bio_common_name"],
                scientific_name=row["bio_scientific_name"],
                iucn_category=row["bio_iucn_category"],
                image_url=row["bio_display_url"],
                image_alt_text_es=row["bio_alt_text_es"],
                image_alt_text_en=row["bio_alt_text_en"],
                image_attribution=row["bio_attribution"],
                image_license_code=row["bio_license_code"],
                image_license_url=row["bio_license_url"],
            )
            for row in rows
        ]

    async def list_sites(self) -> list[Site]:
        rows = await self._connection.fetch(
            """
            SELECT site.bio_site_id, site.bio_site_name, site.bio_region,
                   image.bio_display_url, image.bio_alt_text_es, image.bio_alt_text_en,
                   image.bio_attribution, image.bio_license_code, image.bio_license_url
            FROM bio_sites AS site
            LEFT JOIN bio_site_images AS image
              ON image.bio_site_id = site.bio_site_id
             AND image.bio_is_featured = true AND image.bio_is_active = true
            ORDER BY site.bio_site_name, site.bio_site_id
            """
        )
        return [
            Site(
                site_id=row["bio_site_id"],
                site_name=row["bio_site_name"],
                region=row["bio_region"],
                image_url=row["bio_display_url"],
                image_alt_text_es=row["bio_alt_text_es"],
                image_alt_text_en=row["bio_alt_text_en"],
                image_attribution=row["bio_attribution"],
                image_license_code=row["bio_license_code"],
                image_license_url=row["bio_license_url"],
            )
            for row in rows
        ]

    async def list_researchers(self) -> list[ResearcherDirectoryItem]:
        rows = await self._connection.fetch("SELECT * FROM bio_fn_researcher_directory()")
        return [
            ResearcherDirectoryItem(
                researcher_id=row["researcher_id"],
                full_name=row["full_name"],
                role_title=row["role_title"],
                accreditation_level=row["accreditation_level"],
            )
            for row in rows
        ]


class PostgresDashboardRepository:
    def __init__(self, connection: asyncpg.Connection) -> None:
        self._connection = connection

    async def summary(self) -> DashboardSummary:
        row = await self._connection.fetchrow("SELECT * FROM bio_fn_dashboard_summary()")
        if row is None:  # Defensive; the aggregate always returns a row.
            return DashboardSummary(0, 0, 0, 0)
        return DashboardSummary(
            visible_sightings=row["visible_sightings"],
            registered_species=row["registered_species"],
            monitored_sites=row["monitored_sites"],
            field_notes=row["field_notes"],
        )

    async def classification(self) -> list[ClassificationCount]:
        rows = await self._connection.fetch("SELECT * FROM bio_fn_dashboard_classification()")
        return [ClassificationCount(row["classification_level"], row["total"]) for row in rows]

    async def activity(self, limit: int) -> list[ActivityItem]:
        rows = await self._connection.fetch("SELECT * FROM bio_fn_dashboard_activity($1)", limit)
        return [
            ActivityItem(
                activity_type=row["activity_type"], researcher_name=row["researcher_name"],
                observation_reference=row["observation_reference"],
                species_common_name=row["species_common_name"], occurred_at=row["occurred_at"],
            )
            for row in rows
        ]


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


class PostgresAuthenticationRepository:
    def __init__(self, connection: asyncpg.Connection) -> None:
        self._connection = connection

    async def find_for_login(self, email: str) -> LoginResearcher | None:
        row = await self._connection.fetchrow(
            "SELECT * FROM bio_fn_get_researcher_for_login($1)", email
        )
        if row is None:
            return None
        return LoginResearcher(
            researcher_id=row["researcher_id"],
            full_name=row["full_name"],
            email=row["email"],
            password_hash=row["password_hash"],
            role_title=row["role_title"],
            accreditation_level=row["accreditation_level"],
            is_active=row["is_active"],
        )

    async def create_refresh_token(
        self, *, researcher_id: UUID, token_hash: str, family_id: UUID, expires_at: datetime
    ) -> None:
        await self._connection.fetchval(
            "SELECT bio_fn_create_refresh_token($1, $2, $3, $4)",
            researcher_id,
            token_hash,
            family_id,
            expires_at,
        )

    async def rotate_refresh_token(
        self, *, current_token_hash: str, next_token_hash: str, next_expires_at: datetime
    ) -> Actor:
        try:
            row = await self._connection.fetchrow(
                "SELECT * FROM bio_fn_rotate_refresh_token($1, $2, $3)",
                current_token_hash,
                next_token_hash,
                next_expires_at,
            )
        except asyncpg.PostgresError as error:
            if error.sqlstate == "P0008":
                raise InvalidRefreshToken from error
            if error.sqlstate == "P0009":
                # The SQL function raises after detecting reuse, which rolls back its own update.
                # Revoke in this new statement so every token in the family becomes unusable.
                await self.revoke_refresh_token_family(
                    token_hash=current_token_hash, reason="reuse_detected"
                )
                raise RefreshTokenReuseDetected from error
            raise
        if row is None:
            raise InvalidRefreshToken
        return Actor(
            researcher_id=row["researcher_id"],
            full_name=row["full_name"],
            role_title=row["role_title"],
            accreditation_level=row["accreditation_level"],
        )

    async def revoke_refresh_token_family(self, *, token_hash: str, reason: str) -> None:
        await self._connection.execute(
            "SELECT bio_fn_revoke_refresh_token_family($1, $2)", token_hash, reason
        )
