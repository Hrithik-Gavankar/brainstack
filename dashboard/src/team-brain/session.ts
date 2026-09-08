import type { TeamBrainSession } from "./types";

const STORAGE_KEYS = {
  apiKey: "teamBrain.apiKey",
  supabaseUrl: "teamBrain.supabaseUrl",
  anonKey: "teamBrain.anonKey",
} as const;

const readEnv = (key: string): string => import.meta.env[key]?.trim() ?? "";

export const readDefaultSupabaseUrl = (): string =>
  readEnv("VITE_TEAM_BRAIN_SUPABASE_URL");

export const readDefaultAnonKey = (): string =>
  readEnv("VITE_TEAM_BRAIN_SUPABASE_ANON_KEY");

export const loadTeamBrainSession = (): TeamBrainSession | null => {
  const apiKey = sessionStorage.getItem(STORAGE_KEYS.apiKey)?.trim() ?? "";
  const supabaseUrl =
    sessionStorage.getItem(STORAGE_KEYS.supabaseUrl)?.trim() ||
    readDefaultSupabaseUrl();
  const anonKey =
    sessionStorage.getItem(STORAGE_KEYS.anonKey)?.trim() || readDefaultAnonKey();

  if (!apiKey || !supabaseUrl || !anonKey) {
    return null;
  }

  return { apiKey, supabaseUrl, anonKey };
};

export const saveTeamBrainSession = (session: TeamBrainSession): void => {
  sessionStorage.setItem(STORAGE_KEYS.apiKey, session.apiKey.trim());
  sessionStorage.setItem(STORAGE_KEYS.supabaseUrl, session.supabaseUrl.trim());
  sessionStorage.setItem(STORAGE_KEYS.anonKey, session.anonKey.trim());
};

export const clearTeamBrainSession = (): void => {
  sessionStorage.removeItem(STORAGE_KEYS.apiKey);
  sessionStorage.removeItem(STORAGE_KEYS.supabaseUrl);
  sessionStorage.removeItem(STORAGE_KEYS.anonKey);
};

export const hasSupabaseDefaults = (): boolean =>
  Boolean(readDefaultSupabaseUrl() && readDefaultAnonKey());
