import { useCallback, useEffect, useMemo, useState } from "react";
import { Inbox, LogOut, RefreshCw, ShieldAlert } from "lucide-react";
import { AdminCredentialsForm } from "./AdminCredentialsForm";
import { PendingSubmissionCard } from "./PendingSubmissionCard";
import {
  approvePendingMemory,
  listInitiatives,
  listPendingMemories,
  rejectPendingMemory,
  whoAmI,
} from "../team-brain/rpc";
import {
  clearTeamBrainSession,
  loadTeamBrainSession,
  saveTeamBrainSession,
} from "../team-brain/session";
import type {
  InitiativeRow,
  PendingStatus,
  PendingSubmission,
  TeamBrainSession,
  WhoAmIResponse,
} from "../team-brain/types";

export const AdminReviewApp = () => {
  const [session, setSession] = useState<TeamBrainSession | null>(() => loadTeamBrainSession());
  const [viewer, setViewer] = useState<WhoAmIResponse | null>(null);
  const [initiatives, setInitiatives] = useState<InitiativeRow[]>([]);
  const [submissions, setSubmissions] = useState<PendingSubmission[]>([]);
  const [jiraKey, setJiraKey] = useState("");
  const [statusFilter, setStatusFilter] = useState<PendingStatus>("pending");
  const [loading, setLoading] = useState(false);
  const [actingId, setActingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [actionMessage, setActionMessage] = useState<string | null>(null);

  const isAdmin = viewer?.role === "admin";

  const refreshQueue = useCallback(async (activeSession: TeamBrainSession) => {
    setLoading(true);
    setError(null);
    try {
      const [who, initiativeRows, pendingPayload] = await Promise.all([
        whoAmI(activeSession),
        listInitiatives(activeSession),
        listPendingMemories(
          activeSession,
          jiraKey.trim() ? jiraKey.trim().toUpperCase() : null,
          statusFilter,
        ),
      ]);
      setViewer(who);
      setInitiatives(initiativeRows);
      setSubmissions(pendingPayload.pending ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load review queue");
    } finally {
      setLoading(false);
    }
  }, [jiraKey, statusFilter]);

  useEffect(() => {
    if (!session) {
      return;
    }
    void refreshQueue(session);
  }, [session, refreshQueue]);

  const handleConnect = useCallback((nextSession: TeamBrainSession) => {
    saveTeamBrainSession(nextSession);
    setSession(nextSession);
    setViewer(null);
    setError(null);
    setActionMessage(null);
  }, []);

  const handleDisconnect = useCallback(() => {
    clearTeamBrainSession();
    setSession(null);
    setViewer(null);
    setSubmissions([]);
    setError(null);
    setActionMessage(null);
  }, []);

  const handleRefresh = useCallback(() => {
    if (!session) {
      return;
    }
    void refreshQueue(session);
  }, [refreshQueue, session]);

  const handleApprove = useCallback(
    async (pendingId: string, note: string) => {
      if (!session) {
        return;
      }
      setActingId(pendingId);
      setError(null);
      setActionMessage(null);
      try {
        const result = await approvePendingMemory(session, pendingId, note || null);
        setActionMessage(`Approved — live memory updated (${result.jira_key}).`);
        await refreshQueue(session);
      } catch (err) {
        setError(err instanceof Error ? err.message : "Approve failed");
      } finally {
        setActingId(null);
      }
    },
    [refreshQueue, session],
  );

  const handleReject = useCallback(
    async (pendingId: string, note: string) => {
      if (!session) {
        return;
      }
      setActingId(pendingId);
      setError(null);
      setActionMessage(null);
      try {
        await rejectPendingMemory(session, pendingId, note || null);
        setActionMessage("Rejected — existing live memory unchanged.");
        await refreshQueue(session);
      } catch (err) {
        setError(err instanceof Error ? err.message : "Reject failed");
      } finally {
        setActingId(null);
      }
    },
    [refreshQueue, session],
  );

  const pendingCount = useMemo(
    () => submissions.filter((row) => row.status === "pending").length,
    [submissions],
  );

  if (!session) {
    return <AdminCredentialsForm onConnect={handleConnect} />;
  }

  return (
    <div className="min-h-screen bg-surface">
      <header className="border-b border-border-dim px-6 py-4 flex flex-wrap items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-brain-600/20 flex items-center justify-center">
            <Inbox className="w-5 h-5 text-brain-400" aria-hidden="true" />
          </div>
          <div>
            <h1 className="text-lg font-semibold text-text-primary">Team Brain — Review queue</h1>
            <p className="text-sm text-text-secondary">
              {viewer?.team_name ?? "Connecting…"}
              {viewer ? ` · ${viewer.display_name} (${viewer.role})` : ""}
            </p>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={handleRefresh}
            disabled={loading}
            aria-busy={loading}
            className="inline-flex items-center gap-2 rounded-lg bg-brain-600/15 px-3 py-1.5 text-sm font-medium text-brain-400 hover:bg-brain-600/25 disabled:opacity-50"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${loading ? "animate-spin" : ""}`} aria-hidden="true" />
            Refresh
          </button>
          <button
            type="button"
            onClick={handleDisconnect}
            aria-label="Disconnect and clear session credentials"
            className="inline-flex items-center gap-2 rounded-lg border border-border-dim px-3 py-1.5 text-sm text-text-secondary hover:bg-surface-hover"
          >
            <LogOut className="w-3.5 h-3.5" aria-hidden="true" />
            Disconnect
          </button>
        </div>
      </header>

      <main className="max-w-5xl mx-auto px-6 py-6 space-y-5">
        {!isAdmin && viewer && (
          <div
            role="alert"
            className="rounded-lg border border-yellow-accent/30 bg-yellow-accent/10 px-4 py-3 flex items-start gap-2"
          >
            <ShieldAlert className="w-4 h-4 text-yellow-accent mt-0.5 shrink-0" aria-hidden="true" />
            <p className="text-sm text-text-primary">
              Admin role required to approve or reject. You can still view your own queued submissions.
            </p>
          </div>
        )}

        <section className="flex flex-wrap items-end gap-3">
          <label className="space-y-1">
            <span className="text-xs text-text-muted">Initiative</span>
            <select
              value={jiraKey}
              onChange={(event) => setJiraKey(event.target.value)}
              aria-label="Filter by initiative Jira key"
              className="rounded-lg border border-border-dim bg-surface-card px-3 py-2 text-sm text-text-primary min-w-[10rem] focus:outline-none focus:ring-2 focus:ring-brain-600/40"
            >
              <option value="">All initiatives</option>
              {initiatives.map((initiative) => (
                <option key={initiative.id} value={initiative.jira_key}>
                  {initiative.jira_key}
                  {initiative.title ? ` — ${initiative.title}` : ""}
                </option>
              ))}
            </select>
          </label>

          <label className="space-y-1">
            <span className="text-xs text-text-muted">Status</span>
            <select
              value={statusFilter}
              onChange={(event) => setStatusFilter(event.target.value as PendingStatus)}
              aria-label="Filter by submission status"
              className="rounded-lg border border-border-dim bg-surface-card px-3 py-2 text-sm text-text-primary min-w-[8rem] focus:outline-none focus:ring-2 focus:ring-brain-600/40"
            >
              <option value="pending">Pending</option>
              <option value="approved">Approved</option>
              <option value="rejected">Rejected</option>
              <option value="all">All</option>
            </select>
          </label>

          <p className="text-sm text-text-secondary pb-2">
            {statusFilter === "pending" ? `Pending (${pendingCount})` : `${submissions.length} row(s)`}
          </p>
        </section>

        {actionMessage && (
          <p role="status" className="text-sm text-green-accent">
            {actionMessage}
          </p>
        )}

        {error && (
          <p role="alert" className="text-sm text-red-accent">
            {error}
          </p>
        )}

        {loading && submissions.length === 0 && (
          <p className="text-sm text-text-muted">Loading review queue…</p>
        )}

        {!loading && submissions.length === 0 && (
          <div className="rounded-xl border border-border-dim bg-surface-card p-8 text-center">
            <p className="text-text-primary font-medium">No submissions in this view</p>
            <p className="text-sm text-text-secondary mt-1">
              Members queue overrides with <code className="text-brain-400">remember … --queue</code>.
            </p>
          </div>
        )}

        <div className="space-y-4">
          {submissions.map((submission) => (
            <PendingSubmissionCard
              key={submission.id}
              submission={submission}
              session={session}
              isAdmin={Boolean(isAdmin)}
              acting={actingId === submission.id}
              onApprove={handleApprove}
              onReject={handleReject}
            />
          ))}
        </div>
      </main>

      <footer className="border-t border-border-dim px-6 py-4 text-center">
        <p className="text-xs text-text-muted">
          Team Brain admin review · RPC-only (no direct table access) · local session credentials
        </p>
      </footer>
    </div>
  );
};
