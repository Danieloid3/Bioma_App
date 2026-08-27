export type Researcher = {
  researcher_id: string;
  full_name: string;
  role_title: string;
  accreditation_level: number;
  /** Optional presentation preference supplied by the API; never persisted by the client. */
  animal_avatar_key?: string | null;
};

export type AuthenticationResponse = {
  access_token: string;
  token_type: "bearer";
  expires_in: number;
  researcher: Researcher;
};

export type Sighting = {
  sighting_id: string;
  observation_reference: string;
  researcher_name: string;
  species_common_name: string;
  site_name: string;
  classification_level: number;
  field_notes: string;
  observed_at: string;
  is_voided: boolean;
  image_url?: string | null;
  image_alt_text_es?: string | null;
};

export type SightingDetail = Sighting & {
  researcher_id: string;
  species_id: string;
  species_scientific_name: string;
  species_iucn_category: string;
  site_id: string;
  region: string;
  exact_latitude: number;
  exact_longitude: number;
  voided_at: string | null;
  void_reason: string | null;
  created_at: string;
  updated_at: string;
  image_attribution: string | null;
  image_license_code: string | null;
  image_license_url: string | null;
};

export type SightingPage = { items: Sighting[] };
export type CuratedImage = {
  image_url: string | null;
  image_alt_text_es: string | null;
  image_alt_text_en: string | null;
  image_attribution: string | null;
  image_license_code: string | null;
  image_license_url: string | null;
};

export type SpeciesCatalogItem = {
  species_id: string;
  common_name: string;
  scientific_name: string;
  iucn_category: string;
  description?: string | null;
  habitat?: string | null;
  diet?: string | null;
  conservation_status?: string | null;
} & CuratedImage;

export type SiteCatalogItem = {
  site_id: string;
  site_name: string;
  region: string;
  description?: string | null;
  ecosystem?: string | null;
} & CuratedImage;


/** Flexible catalogue shape used only by sighting filter controls. */
export type CatalogItem = {
  species_id?: string;
  site_id?: string;
  common_name?: string;
  site_name?: string;
  scientific_name?: string;
  region?: string;
  iucn_category?: string;
} & CuratedImage;

export type CatalogResponse = { items: SpeciesCatalogItem[] };
export type SiteCatalogResponse = { items: SiteCatalogItem[] };
export type ResearcherDirectoryItem = { researcher_id: string; full_name: string; role_title: string; accreditation_level: number; animal_avatar_key?: string | null };
export type ResearcherDirectoryResponse = { items: ResearcherDirectoryItem[] };

export type DashboardSummary = { visible_sightings: number; registered_species: number; monitored_sites: number; field_notes: number };
export type ClassificationCount = { classification_level: number; total: number };
export type ActivityItem = { activity_type: "created" | "edited" | "voided"; researcher_name: string; observation_reference: string; species_common_name: string; occurred_at: string };
export type DashboardResponse = { summary: DashboardSummary; classification: ClassificationCount[]; activity: ActivityItem[] };

export type CopilotSource = {
  sighting_id: string;
  observation_reference: string;
  species_common_name: string;
  field_notes: string;
  similarity: number;
};

export type CopilotAnswer = {
  answer: string;
  model_name: string;
  input_tokens: number;
  output_tokens: number;
  sources: CopilotSource[];
  conversation_id: string;
};

export type CopilotConversation = {
  conversation_id: string;
  title: string;
  created_at: string;
  updated_at: string;
  message_count: number;
};

export type CopilotConversationItem = CopilotConversation;

export type CopilotConversationListResponse = {
  items: CopilotConversation[];
};

export type CopilotMessage = {
  message_id: string;
  conversation_id: string;
  sender_role: "user" | "assistant" | "error";
  message_text: string;
  model_name?: string | null;
  created_at: string;
  citations: CopilotSource[];
};

export type CopilotMessageListResponse = {
  items: CopilotMessage[];
};

export type CopilotUsageItem = {
  researcher_id: string;
  total_queries: number;
  total_tokens: number;
  last_query_at: string;
};

export type CopilotUsageResponse = { item: CopilotUsageItem | null };

