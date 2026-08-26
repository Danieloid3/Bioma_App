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

