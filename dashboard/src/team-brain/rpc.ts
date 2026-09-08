import type {
  ApprovePendingResponse,
  InitiativeRow,
  ListPendingResponse,
  LiveMemory,
  PendingStatus,
  RejectPendingResponse,
  TeamBrainSession,
  WhoAmIResponse,
} from "./types";

const parseRpcError = (raw: string): string => {
  try {
    const parsed = JSON.parse(raw) as { message?: string; error?: string };
    return parsed.message ?? parsed.error ?? raw;
  } catch {
    return raw || "RPC request failed";
  }
};

export const callTeamBrainRpc = async <T>(
  fn: string,
  body: Record<string, unknown>,
  session: TeamBrainSession,
): Promise<T> => {
  const url = `${session.supabaseUrl.replace(/\/$/, "")}/rest/v1/rpc/${fn}`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: session.anonKey,
      Authorization: `Bearer ${session.anonKey}`,
    },
    body: JSON.stringify(body),
  });

  const text = await response.text();
  if (!response.ok) {
    throw new Error(parseRpcError(text));
  }

  if (!text) {
    return {} as T;
  }

  return JSON.parse(text) as T;
};

export const whoAmI = (session: TeamBrainSession): Promise<WhoAmIResponse> =>
  callTeamBrainRpc("tb_whoami", { p_api_key: session.apiKey }, session);

export const listInitiatives = (session: TeamBrainSession): Promise<InitiativeRow[]> =>
  callTeamBrainRpc("list_initiatives", { p_api_key: session.apiKey }, session);

export const listPendingMemories = (
  session: TeamBrainSession,
  jiraKey: string | null,
  status: PendingStatus,
): Promise<ListPendingResponse> =>
  callTeamBrainRpc("list_pending_memories", {
    p_api_key: session.apiKey,
    p_jira_key: jiraKey,
    p_status: status,
  }, session);

export const approvePendingMemory = (
  session: TeamBrainSession,
  pendingId: string,
  note: string | null,
): Promise<ApprovePendingResponse> =>
  callTeamBrainRpc("approve_pending_memory", {
    p_api_key: session.apiKey,
    p_pending_id: pendingId,
    p_note: note,
  }, session);

export const rejectPendingMemory = (
  session: TeamBrainSession,
  pendingId: string,
  note: string | null,
): Promise<RejectPendingResponse> =>
  callTeamBrainRpc("reject_pending_memory", {
    p_api_key: session.apiKey,
    p_pending_id: pendingId,
    p_note: note,
  }, session);

export const fetchLiveMemoryById = async (
  session: TeamBrainSession,
  jiraKey: string,
  captureId: string,
): Promise<LiveMemory | null> => {
  const payload = await callTeamBrainRpc<{
    memories?: LiveMemory[];
    captures?: LiveMemory[];
  }>("list_recent", {
    p_api_key: session.apiKey,
    p_jira_key: jiraKey,
    p_limit: 200,
  }, session);

  const rows = payload.memories ?? payload.captures ?? [];
  return rows.find((row) => row.id === captureId) ?? null;
};
