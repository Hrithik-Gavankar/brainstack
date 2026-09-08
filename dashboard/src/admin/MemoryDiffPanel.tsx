import type { LiveMemory } from "../team-brain/types";

interface MemoryDiffPanelProps {
  proposedBody: string;
  proposedSourceRef: string | null;
  liveMemory: LiveMemory | null;
  loadingLive: boolean;
}

export const MemoryDiffPanel = ({
  proposedBody,
  proposedSourceRef,
  liveMemory,
  loadingLive,
}: MemoryDiffPanelProps) => {
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
      <section
        aria-label="Proposed memory body"
        className="rounded-lg border border-brain-600/30 bg-brain-600/5 p-3 space-y-2"
      >
        <h3 className="text-xs font-semibold uppercase tracking-wide text-brain-400">Proposed</h3>
        {proposedSourceRef && (
          <p className="text-xs text-text-muted font-mono">{proposedSourceRef}</p>
        )}
        <p className="text-sm text-text-primary whitespace-pre-wrap leading-relaxed">{proposedBody}</p>
      </section>

      <section
        aria-label="Current live memory body"
        className="rounded-lg border border-border-dim bg-surface p-3 space-y-2"
      >
        <h3 className="text-xs font-semibold uppercase tracking-wide text-text-secondary">Live memory</h3>
        {loadingLive && (
          <p className="text-sm text-text-muted">Loading live capture…</p>
        )}
        {!loadingLive && !liveMemory && (
          <p className="text-sm text-text-muted">No live capture linked (target may have been deleted).</p>
        )}
        {!loadingLive && liveMemory && (
          <>
            {liveMemory.source_ref && (
              <p className="text-xs text-text-muted font-mono">{liveMemory.source_ref}</p>
            )}
            <p className="text-xs text-text-muted">
              {liveMemory.author_name} · {liveMemory.kind}
            </p>
            <p className="text-sm text-text-primary whitespace-pre-wrap leading-relaxed">{liveMemory.body}</p>
          </>
        )}
      </section>
    </div>
  );
};
