import { Brain, RefreshCw } from "lucide-react";
import type { EngineerProfile } from "../types";

interface HeaderProps {
  profile: EngineerProfile;
  lastUpdated: string;
}

export function Header({ profile, lastUpdated }: HeaderProps) {
  return (
    <header className="border-b border-border-dim px-6 py-4 flex items-center justify-between">
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-xl bg-brain-600/20 flex items-center justify-center">
          <Brain className="w-5 h-5 text-brain-400" />
        </div>
        <div>
          <h1 className="text-lg font-semibold text-text-primary leading-tight">
            {profile.name}
          </h1>
          <p className="text-sm text-text-secondary">
            {profile.role} at {profile.company} &middot; {profile.experience}
          </p>
        </div>
      </div>
      <div className="flex items-center gap-4">
        <span className="text-xs text-text-muted">
          Updated {lastUpdated}
        </span>
        <button className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-brain-600/15 text-brain-400 text-sm font-medium hover:bg-brain-600/25 transition-colors">
          <RefreshCw className="w-3.5 h-3.5" />
          Refresh
        </button>
      </div>
    </header>
  );
}
