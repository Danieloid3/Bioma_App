from dataclasses import dataclass
from datetime import datetime
from uuid import UUID


@dataclass(frozen=True, slots=True)
class Actor:
    researcher_id: UUID
    full_name: str
    role_title: str
    accreditation_level: int


@dataclass(frozen=True, slots=True)
class LoginResearcher:
    researcher_id: UUID
    full_name: str
    email: str
    password_hash: str
    role_title: str
    accreditation_level: int
    is_active: bool

    @property
    def actor(self) -> Actor:
        return Actor(
            researcher_id=self.researcher_id,
            full_name=self.full_name,
            role_title=self.role_title,
            accreditation_level=self.accreditation_level,
        )


@dataclass(frozen=True, slots=True)
class AuthenticationResult:
    actor: Actor
    access_token: str
    refresh_token: str
    expires_in: int


@dataclass(frozen=True, slots=True)
class CopilotSource:
    sighting_id: UUID
    observation_reference: str
    species_common_name: str
    field_notes: str
    similarity: float


@dataclass(frozen=True, slots=True)
class CopilotAnswer:
    text: str
    sources: tuple[CopilotSource, ...]
    model_name: str
    input_tokens: int
    output_tokens: int


@dataclass(frozen=True, slots=True)
class SightingHistoryItem:
    sighting_id: UUID
    observation_reference: str
    researcher_name: str
    species_common_name: str
    site_name: str
    classification_level: int
    field_notes: str
    observed_at: datetime
    is_voided: bool
    image_url: str | None = None
    image_alt_text_es: str | None = None


@dataclass(frozen=True, slots=True)
class SightingDetail:
    sighting_id: UUID
    observation_reference: str
    researcher_id: UUID
    researcher_name: str
    species_id: UUID
    species_common_name: str
    species_scientific_name: str
    species_iucn_category: str
    site_id: UUID
    site_name: str
    region: str
    observed_at: datetime
    exact_latitude: float
    exact_longitude: float
    classification_level: int
    field_notes: str
    is_voided: bool
    voided_at: datetime | None
    voided_by_researcher_id: UUID | None
    void_reason: str | None
    created_at: datetime
    updated_at: datetime
    image_url: str | None
    image_alt_text_es: str | None
    image_attribution: str | None
    image_license_code: str | None
    image_license_url: str | None


@dataclass(frozen=True, slots=True)
class SightingSearchItem:
    sighting_id: UUID
    observation_reference: str
    researcher_name: str
    species_common_name: str
    site_name: str
    field_notes_highlight: str
    classification_level: int
    observed_at: datetime


@dataclass(frozen=True, slots=True)
class Species:
    species_id: UUID
    common_name: str
    scientific_name: str
    iucn_category: str
    image_url: str | None = None
    image_alt_text_es: str | None = None
    image_alt_text_en: str | None = None
    image_attribution: str | None = None
    image_license_code: str | None = None
    image_license_url: str | None = None


@dataclass(frozen=True, slots=True)
class Site:
    site_id: UUID
    site_name: str
    region: str


@dataclass(frozen=True, slots=True)
class DashboardSummary:
    visible_sightings: int
    registered_species: int
    monitored_sites: int
    field_notes: int


@dataclass(frozen=True, slots=True)
class ClassificationCount:
    classification_level: int
    total: int


@dataclass(frozen=True, slots=True)
class ActivityItem:
    activity_type: str
    researcher_name: str
    observation_reference: str
    species_common_name: str
    occurred_at: datetime


@dataclass(frozen=True, slots=True)
class ResearcherDirectoryItem:
    researcher_id: UUID
    full_name: str
    role_title: str
    accreditation_level: int
