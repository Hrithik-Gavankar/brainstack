import { FolderGit2 } from "lucide-react";
import type { RepoActivity } from "../types";

interface RepoListProps {
  repos: RepoActivity[];
}

const levelColors: Record<string, string> = {
  Heavy: "bg-green-accent/20 text-green-accent",
  Medium: "bg-brain-500/20 text-brain-400",
  Light: "bg-yellow-accent/20 text-yellow-accent",
  Exploring: "bg-purple-accent/20 text-purple-accent",
};

function daysAgo(dateStr: string): string {
  const diff = Math.floor(
    (Date.now() - new Date(dateStr).getTime()) / 86400000
  );
  if (diff === 0) return "Today";
  if (diff === 1) return "Yesterday";
  if (diff < 7) return `${diff}d ago`;
  if (diff < 30) return `${Math.floor(diff / 7)}w ago`;
  return `${Math.floor(diff / 30)}mo ago`;
}

export function RepoList({ repos }: RepoListProps) {
  return (
    <div className="rounded-xl border border-border-dim bg-surface-card p-5">
      <h3 className="text-sm font-medium text-text-secondary mb-4">
        Active Repositories
      </h3>
      <div className="space-y-3">
        {repos.map((repo) => (
          <div
            key={repo.name}
            className="flex items-center gap-4 rounded-lg bg-surface/50 p-3 hover:bg-surface-hover transition-colors"
          >
            <FolderGit2 className="w-4 h-4 text-text-muted flex-shrink-0" />
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <span className="text-sm font-medium text-text-primary truncate">
                  {repo.name}
                </span>
                <span
                  className={`text-[10px] font-medium px-1.5 py-0.5 rounded-full ${levelColors[repo.contributionLevel]}`}
                >
                  {repo.contributionLevel}
                </span>
              </div>
              <p className="text-xs text-text-muted truncate">{repo.focusArea}</p>
            </div>
            <div className="text-right flex-shrink-0">
              <div className="text-sm font-medium text-text-primary">
                {repo.commitCount}
              </div>
              <div className="text-[10px] text-text-muted">
                {daysAgo(repo.lastActive)}
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
