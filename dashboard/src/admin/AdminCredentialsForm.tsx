import { useCallback, useState } from "react";
import { KeyRound, ShieldCheck } from "lucide-react";
import type { TeamBrainSession } from "../team-brain/types";
import {
  hasSupabaseDefaults,
  readDefaultAnonKey,
  readDefaultSupabaseUrl,
} from "../team-brain/session";

interface AdminCredentialsFormProps {
  onConnect: (session: TeamBrainSession) => void;
}

export const AdminCredentialsForm = ({ onConnect }: AdminCredentialsFormProps) => {
  const defaultsAvailable = hasSupabaseDefaults();
  const [apiKey, setApiKey] = useState("");
  const [supabaseUrl, setSupabaseUrl] = useState(readDefaultSupabaseUrl());
  const [anonKey, setAnonKey] = useState(readDefaultAnonKey());
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = useCallback(
    (event: React.FormEvent<HTMLFormElement>) => {
      event.preventDefault();
      setError(null);

      const trimmedApiKey = apiKey.trim();
      const trimmedUrl = supabaseUrl.trim();
      const trimmedAnon = anonKey.trim();

      if (!trimmedApiKey.startsWith("tb_")) {
        setError("API key must start with tb_ (crew member key from register/join).");
        return;
      }
      if (!trimmedUrl || !trimmedAnon) {
        setError("Supabase URL and anon key are required.");
        return;
      }

      onConnect({
        apiKey: trimmedApiKey,
        supabaseUrl: trimmedUrl,
        anonKey: trimmedAnon,
      });
    },
    [anonKey, apiKey, onConnect, supabaseUrl],
  );

  return (
    <div className="min-h-screen bg-surface flex items-center justify-center px-6">
      <div className="w-full max-w-lg rounded-2xl border border-border-dim bg-surface-card p-6 space-y-5">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-brain-600/20 flex items-center justify-center">
            <ShieldCheck className="w-5 h-5 text-brain-400" aria-hidden="true" />
          </div>
          <div>
            <h1 className="text-lg font-semibold text-text-primary">Team Brain — Review queue</h1>
            <p className="text-sm text-text-secondary">Admin-only inbox for pending memory overrides</p>
          </div>
        </div>

        <p className="text-sm text-text-secondary leading-relaxed">
          Uses the same RPC trust model as the CLI: your crew <code className="text-brain-400">tb_…</code> key
          in session storage only. Never deploy real keys to GitHub Pages.
        </p>

        <form className="space-y-4" onSubmit={handleSubmit}>
          <label className="block space-y-1.5">
            <span className="text-sm font-medium text-text-primary">Admin API key</span>
            <div className="relative">
              <KeyRound
                className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-text-muted"
                aria-hidden="true"
              />
              <input
                type="password"
                value={apiKey}
                onChange={(event) => setApiKey(event.target.value)}
                autoComplete="off"
                spellCheck={false}
                aria-label="Team Brain admin API key"
                placeholder="tb_…"
                className="w-full rounded-lg border border-border-dim bg-surface pl-10 pr-3 py-2 text-sm text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-2 focus:ring-brain-600/40"
              />
            </div>
          </label>

          {!defaultsAvailable && (
            <>
              <label className="block space-y-1.5">
                <span className="text-sm font-medium text-text-primary">Supabase URL</span>
                <input
                  type="url"
                  value={supabaseUrl}
                  onChange={(event) => setSupabaseUrl(event.target.value)}
                  aria-label="Supabase project URL"
                  placeholder="https://xxxx.supabase.co"
                  className="w-full rounded-lg border border-border-dim bg-surface px-3 py-2 text-sm text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-2 focus:ring-brain-600/40"
                />
              </label>

              <label className="block space-y-1.5">
                <span className="text-sm font-medium text-text-primary">Supabase anon key</span>
                <input
                  type="password"
                  value={anonKey}
                  onChange={(event) => setAnonKey(event.target.value)}
                  autoComplete="off"
                  aria-label="Supabase anon key"
                  className="w-full rounded-lg border border-border-dim bg-surface px-3 py-2 text-sm text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-2 focus:ring-brain-600/40"
                />
              </label>
            </>
          )}

          {defaultsAvailable && (
            <p className="text-xs text-text-muted">
              Supabase URL/anon loaded from <code>VITE_TEAM_BRAIN_*</code> env vars.
            </p>
          )}

          {error && (
            <p role="alert" className="text-sm text-red-accent">
              {error}
            </p>
          )}

          <button
            type="submit"
            className="w-full rounded-lg bg-brain-600/20 text-brain-400 text-sm font-medium py-2.5 hover:bg-brain-600/30 transition-colors"
          >
            Connect
          </button>
        </form>
      </div>
    </div>
  );
};
