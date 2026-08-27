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


@dataclass(frozen=True, slots=True)
class Site:
    site_id: UUID
    site_name: str
    region: str
