import { useCallback, useEffect, useState } from "react";
import { Header } from "./components/Header";
import { SummaryCards } from "./components/SummaryCards";
import { CommitTypeChart } from "./components/CommitTypeChart";
import { VelocityChart } from "./components/VelocityChart";
import { RepoList } from "./components/RepoList";
import { ExpertiseMap } from "./components/ExpertiseMap";
import { GrowthTracker } from "./components/GrowthTracker";
import { loadDashboardData, sourceLabel } from "./data/loadDashboardData";
import type { DashboardData } from "./types";
import "./index.css";

function App() {
  const [data, setData] = useState<DashboardData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const next = await loadDashboardData({ source: "sample" });
      setData(next);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load dashboard data");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  if (error && !data) {
    return (
      <div className="min-h-screen bg-surface flex items-center justify-center px-6">
        <div className="max-w-md text-center space-y-3">
          <p className="text-text-primary font-medium">Could not load dashboard</p>
          <p className="text-sm text-text-secondary">{error}</p>
          <button
            type="button"
            onClick={() => void refresh()}
            className="px-3 py-1.5 rounded-lg bg-brain-600/15 text-brain-400 text-sm font-medium hover:bg-brain-600/25"
          >
            Retry
          </button>
        </div>
      </div>
    );
  }

  if (!data) {
    return (
      <div className="min-h-screen bg-surface flex items-center justify-center">
        <p className="text-sm text-text-muted">Loading dashboard…</p>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-surface">
      <Header
        profile={data.profile}
        lastUpdated={data.lastUpdated}
        loading={loading}
        onRefresh={() => void refresh()}
      />

      <main className="max-w-7xl mx-auto px-6 py-6 space-y-6">
        <SummaryCards data={data} />

        <div className="grid grid-cols-1 lg:grid-cols-5 gap-6">
          <div className="lg:col-span-3">
            <VelocityChart data={data.velocity} />
          </div>
          <div className="lg:col-span-2">
            <CommitTypeChart data={data.commitTypes} />
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <RepoList repos={data.repos} />
          <ExpertiseMap data={data.expertise} />
        </div>

        <GrowthTracker items={data.growthItems} />
      </main>

      <footer className="border-t border-border-dim px-6 py-4 text-center">
        <p className="text-xs text-text-muted">
          Brainstack Dashboard &middot; {sourceLabel(data.source)}
        </p>
      </footer>
    </div>
  );
}

export default App;
