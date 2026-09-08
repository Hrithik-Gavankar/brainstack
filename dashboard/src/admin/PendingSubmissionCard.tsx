import { useEffect, useMemo, useState } from "react";
import { Check, Clock, X } from "lucide-react";
import type { LiveMemory, PendingSubmission, TeamBrainSession } from "../team-brain/types";
import { fetchLiveMemoryById } from "../team-brain/rpc";
import { MemoryDiffPanel } from "./MemoryDiffPanel";

interface PendingSubmissionCardProps {
  submission: PendingSubmission;
  session: TeamBrainSession;
  isAdmin: boolean;
  acting: boolean;
  onApprove: (id: string, note: string) => void;
  onReject: (id: string, note: string) => void;
}

const formatRelativeTime = (iso: string): string => {
  const deltaMs = Date.now() - new Date(iso).getTime();
  const minutes = Math.floor(deltaMs / 60_000);
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 48) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
};

export const PendingSubmissionCard = ({
  submission,
  session,
  isAdmin,
  acting,
  onApprove,
  onReject,
}: PendingSubmissionCardProps) => {
  const [note, setNote] = useState("");
  const [liveMemory, setLiveMemory] = useState<LiveMemory | null>(null);
  const [loadingLive, setLoadingLive] = useState(false);

  const matches = useMemo(
    () => submission.match_metadata?.matches ?? [],
    [submission.match_metadata],
  );

  useEffect(() => {
    if (!submission.target_capture_id) {
      setLiveMemory(null);
      return;
    }

    let cancelled = false;
    const loadLive = async () => {
      setLoadingLive(true);
      try {
        const live = await fetchLiveMemoryById(
          session,
          submission.jira_key,
          submission.target_capture_id!,
        );
        if (!cancelled) {
          setLiveMemory(live);
        }
      } catch {
        if (!cancelled) {
          setLiveMemory(null);
        }
      } finally {
        if (!cancelled) {
          setLoadingLive(false);
        }
      }
    };

    void loadLive();
    return () => {
      cancelled = true;
    };
  }, [session, submission.jira_key, submission.target_capture_id]);

  const isPending = submission.status === "pending";

  return (
    <article className="rounded-xl border border-border-dim bg-surface-card p-4 space-y-4">
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div className="space-y-1">
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <span className="rounded-md bg-purple-accent/15 px-2 py-0.5 text-purple-accent font-medium">
              {submission.conflict_reason}
            </span>
            <span className="text-text-secondary">{submission.author_name}</span>
            <span className="text-text-muted flex items-center gap-1">
              <Clock className="w-3.5 h-3.5" aria-hidden="true" />
              {formatRelativeTime(submission.created_at)}
            </span>
          </div>
          <p className="text-xs text-text-muted">
            {submission.jira_key} · {submission.kind}
            {submission.source_ref ? ` · ${submission.source_ref}` : ""}
          </p>
        </div>
        {!isPending && (
          <span
            className={`text-xs font-medium px-2 py-1 rounded-md ${
              submission.status === "approved"
                ? "bg-green-accent/15 text-green-accent"
                : "bg-red-accent/15 text-red-accent"
            }`}
          >
            {submission.status}
            {submission.reviewed_by ? ` by ${submission.reviewed_by}` : ""}
          </span>
        )}
      </header>

      {matches.length > 0 && (
        <div className="rounded-lg border border-border-dim bg-surface px-3 py-2 space-y-2">
          <p className="text-xs font-semibold uppercase tracking-wide text-text-secondary">Matches</p>
          <ul className="space-y-2">
            {matches.map((match) => (
              <li key={match.capture_id ?? match.source_ref ?? match.body_preview} className="text-sm">
                <span className="font-mono text-text-muted">
                  {match.source_ref ?? match.capture_id ?? "match"}
                </span>
                {match.author_name && (
                  <span className="text-text-secondary"> — {match.author_name}</span>
                )}
                {match.body_preview && (
                  <p className="text-text-primary mt-0.5">{match.body_preview}</p>
                )}
              </li>
            ))}
          </ul>
        </div>
      )}

      {submission.target_capture_id ? (
        <MemoryDiffPanel
          proposedBody={submission.body_preview}
          proposedSourceRef={submission.source_ref}
          liveMemory={liveMemory}
          loadingLive={loadingLive}
        />
      ) : (
        <div className="rounded-lg border border-brain-600/30 bg-brain-600/5 p-3">
          <p className="text-xs font-semibold uppercase tracking-wide text-brain-400 mb-2">Proposed</p>
          <p className="text-sm text-text-primary whitespace-pre-wrap leading-relaxed">
            {submission.body_preview}
          </p>
        </div>
      )}

      {submission.review_note && (
        <p className="text-sm text-text-secondary">
          Review note: {submission.review_note}
        </p>
      )}

      {isPending && isAdmin && (
        <div className="flex flex-col sm:flex-row sm:items-end gap-3 pt-1">
          <label className="flex-1 space-y-1">
            <span className="text-xs text-text-muted">Review note (optional)</span>
            <input
              type="text"
              value={note}
              onChange={(event) => setNote(event.target.value)}
              aria-label={`Review note for submission ${submission.id}`}
              placeholder="Why approve or reject…"
              className="w-full rounded-lg border border-border-dim bg-surface px-3 py-2 text-sm text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-2 focus:ring-brain-600/40"
            />
          </label>
          <div className="flex gap-2">
            <button
              type="button"
              disabled={acting}
              aria-label={`Approve submission from ${submission.author_name}`}
              onClick={() => onApprove(submission.id, note.trim())}
              className="inline-flex items-center gap-1.5 rounded-lg bg-green-accent/15 px-3 py-2 text-sm font-medium text-green-accent hover:bg-green-accent/25 disabled:opacity-50"
            >
              <Check className="w-4 h-4" aria-hidden="true" />
              Approve
            </button>
            <button
              type="button"
              disabled={acting}
              aria-label={`Reject submission from ${submission.author_name}`}
              onClick={() => onReject(submission.id, note.trim())}
              className="inline-flex items-center gap-1.5 rounded-lg bg-red-accent/15 px-3 py-2 text-sm font-medium text-red-accent hover:bg-red-accent/25 disabled:opacity-50"
            >
              <X className="w-4 h-4" aria-hidden="true" />
              Reject
            </button>
          </div>
        </div>
      )}

      {isPending && !isAdmin && (
        <p className="text-sm text-text-muted">Awaiting admin approval.</p>
      )}
    </article>
  );
};
