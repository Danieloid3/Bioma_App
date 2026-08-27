export type Researcher = {
  researcher_id: string;
  full_name: string;
  role_title: string;
  accreditation_level: number;
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
};

export type SightingPage = { items: Sighting[] };
export type SpeciesImage = { image_url?: string; image_alt_text_es?: string; image_alt_text_en?: string; image_attribution?: string; image_license_code?: string; image_license_url?: string };
export type CatalogItem = { species_id?: string; site_id?: string; common_name?: string; site_name?: string; scientific_name?: string; region?: string; iucn_category?: string } & SpeciesImage;
export type CatalogResponse = { items: CatalogItem[] };
export type ResearcherDirectoryItem = { researcher_id: string; full_name: string; role_title: string; accreditation_level: number };
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
};
