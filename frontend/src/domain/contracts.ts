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
export type CatalogItem = { species_id?: string; site_id?: string; common_name?: string; site_name?: string; scientific_name?: string; region?: string };
export type CatalogResponse = { items: CatalogItem[] };

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
