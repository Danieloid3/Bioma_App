from dataclasses import dataclass
from datetime import datetime
from uuid import UUID


@dataclass(frozen=True, slots=True)
class Actor:
    researcher_id: UUID
    full_name: str
    role_title: str
    accreditation_level: int
    avatar_key: str = "spectacled_bear"


@dataclass(frozen=True, slots=True)
class LoginResearcher:
    researcher_id: UUID
    full_name: str
    email: str
    password_hash: str
    role_title: str
    accreditation_level: int
    is_active: bool
    avatar_key: str = "spectacled_bear"

    @property
    def actor(self) -> Actor:
        return Actor(
            researcher_id=self.researcher_id,
            full_name=self.full_name,
            role_title=self.role_title,
            accreditation_level=self.accreditation_level,
            avatar_key=self.avatar_key,
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
    site_name: str | None = None
    region: str | None = None
    source_type: str = "sighting"



@dataclass(frozen=True, slots=True)
class CatalogKnowledgeItem:
    catalog_type: str  # 'species' | 'site'
    common_name: str
    scientific_name: str | None = None
    iucn_category: str | None = None
    ecosystem: str | None = None
    region: str | None = None
    description: str | None = None
    habitat: str | None = None
    diet: str | None = None
    conservation_status: str | None = None


@dataclass(frozen=True, slots=True)
class ConversationMessage:
    role: str
    content: str



@dataclass(frozen=True, slots=True)
class CopilotAnswer:
    text: str
    sources: tuple[CopilotSource, ...]
    model_name: str
    input_tokens: int
    output_tokens: int
    audit_usage_id: UUID | None = None


@dataclass(frozen=True, slots=True)
class CopilotConversationItem:
    conversation_id: UUID
    title: str
    created_at: datetime
    updated_at: datetime
    message_count: int


@dataclass(frozen=True, slots=True)
class CopilotMessageItem:
    message_id: UUID
    conversation_id: UUID
    sender_role: str
    message_text: str
    model_name: str | None
    created_at: datetime
    citations: tuple[CopilotSource, ...]


@dataclass(frozen=True, slots=True)
class ChatChannelItem:
    channel_id: UUID
    channel_type: str
    name: str | None
    created_at: datetime
    updated_at: datetime
    message_count: int
    unread_count: int
    last_message_at: datetime | None
    display_name: str


@dataclass(frozen=True, slots=True)
class ChatMessageItem:
    message_id: UUID
    channel_id: UUID
    author_id: UUID | None
    author_name: str
    sender_role: str
    message_text: str
    is_edited: bool
    created_at: datetime
    is_deleted: bool = False
    read_count: int = 0
    citations: tuple[dict[str, str], ...] = ()





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
    description: str | None = None
    habitat: str | None = None
    diet: str | None = None
    conservation_status: str | None = None
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
    description: str | None = None
    ecosystem: str | None = None
    image_url: str | None = None
    image_alt_text_es: str | None = None
    image_alt_text_en: str | None = None
    image_attribution: str | None = None
    image_license_code: str | None = None
    image_license_url: str | None = None



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
    avatar_key: str
