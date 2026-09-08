export type TeamBrainRole = "admin" | "member" | "viewer";

export type PendingStatus = "pending" | "approved" | "rejected" | "all";

export type ConflictReason = "semantic_duplicate" | "source_ref_override";

export type MemoryKind = "research" | "decision" | "note" | "learning";

export interface TeamBrainSession {
  supabaseUrl: string;
  anonKey: string;
  apiKey: string;
}

export interface WhoAmIResponse {
  member_id: string;
  display_name: string;
  role: TeamBrainRole;
  team_id: string;
  team_name: string;
  invite_code?: string;
}

export interface InitiativeRow {
  id: string;
  jira_key: string;
  title: string;
  status: string;
  jira_url?: string | null;
  updated_at?: string;
}

export interface MatchMetadataEntry {
  capture_id?: string;
  source_ref?: string | null;
  kind?: MemoryKind;
  body_preview?: string;
  author_name?: string;
  match_type?: string;
  similarity?: number;
  distance?: number | null;
  rank?: number | null;
}

export interface PendingMatchMetadata {
  matches?: MatchMetadataEntry[];
}

export interface PendingSubmission {
  id: string;
  status: "pending" | "approved" | "rejected";
  conflict_reason: ConflictReason;
  kind: MemoryKind;
  body_preview: string;
  source_ref: string | null;
  target_capture_id: string | null;
  match_metadata: PendingMatchMetadata;
  review_note: string | null;
  created_at: string;
  reviewed_at: string | null;
  jira_key: string;
  author_name: string;
  reviewed_by: string | null;
}

export interface ListPendingResponse {
  team_id: string;
  viewer_role: TeamBrainRole;
  status_filter: PendingStatus;
  pending: PendingSubmission[];
}

export interface LiveMemory {
  id: string;
  kind: MemoryKind;
  body: string;
  source_ref: string | null;
  author_name: string;
  updated_at?: string;
  created_at?: string;
}

export interface ApprovePendingResponse {
  ok: boolean;
  approved: boolean;
  pending_id: string;
  jira_key: string;
  capture_id: string;
  source_ref: string | null;
  archived_revision: number | null;
  reviewed_by: string;
}

export interface RejectPendingResponse {
  ok: boolean;
  rejected: boolean;
  pending_id: string;
  reviewed_by: string;
  review_note: string | null;
}
