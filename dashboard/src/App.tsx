import { Header } from "./components/Header";
import { SummaryCards } from "./components/SummaryCards";
import { CommitTypeChart } from "./components/CommitTypeChart";
import { VelocityChart } from "./components/VelocityChart";
import { RepoList } from "./components/RepoList";
import { ExpertiseMap } from "./components/ExpertiseMap";
import { GrowthTracker } from "./components/GrowthTracker";
import { sampleData } from "./data/sampleData";
import "./index.css";

function App() {
  const data = sampleData;

  return (
    <div className="min-h-screen bg-surface">
      <Header profile={data.profile} lastUpdated={data.lastUpdated} />

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
          Engineer Brain Dashboard &middot; Data from BRAIN.md + git scan
        </p>
      </footer>
    </div>
  );
}

export default App;
