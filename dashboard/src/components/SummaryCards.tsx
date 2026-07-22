import { GitCommit, FolderGit2, TrendingUp, TrendingDown, Minus, Target } from "lucide-react";
import type { DashboardData } from "../types";

interface SummaryCardsProps {
  data: DashboardData;
}

export function SummaryCards({ data }: SummaryCardsProps) {
  const trendIcon = {
    up: <TrendingUp className="w-4 h-4" />,
    down: <TrendingDown className="w-4 h-4" />,
    stable: <Minus className="w-4 h-4" />,
  };

  const trendColor = {
    up: "text-green-accent",
    down: "text-red-accent",
    stable: "text-yellow-accent",
  };

  const growthDone = data.growthItems.filter((g) => g.completed).length;
  const growthTotal = data.growthItems.length;
  const growthPct = Math.round((growthDone / growthTotal) * 100);

  const cards = [
    {
      label: "Total Commits",
      value: data.totalCommits,
      subtitle: "This quarter",
      icon: <GitCommit className="w-5 h-5 text-brain-400" />,
      accent: "bg-brain-600/15",
    },
    {
      label: "Active Repos",
      value: `${data.activeRepos} / ${data.totalRepos}`,
      subtitle: "With recent commits",
      icon: <FolderGit2 className="w-5 h-5 text-green-accent" />,
      accent: "bg-green-accent/15",
    },
    {
      label: "Velocity Trend",
      value: `${data.velocityChange > 0 ? "+" : ""}${data.velocityChange}%`,
      subtitle: data.velocityTrend === "up" ? "Trending up" : data.velocityTrend === "down" ? "Trending down" : "Stable",
      icon: <span className={trendColor[data.velocityTrend]}>{trendIcon[data.velocityTrend]}</span>,
      accent: `${data.velocityTrend === "up" ? "bg-green-accent/15" : data.velocityTrend === "down" ? "bg-red-accent/15" : "bg-yellow-accent/15"}`,
    },
    {
      label: "Growth Progress",
      value: `${growthDone}/${growthTotal}`,
      subtitle: `${growthPct}% complete`,
      icon: <Target className="w-5 h-5 text-purple-accent" />,
      accent: "bg-purple-accent/15",
    },
  ];

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
      {cards.map((card) => (
        <div
          key={card.label}
          className="rounded-xl border border-border-dim bg-surface-card p-5 hover:border-brain-700/40 transition-colors"
        >
          <div className="flex items-center justify-between mb-3">
            <span className="text-sm text-text-secondary">{card.label}</span>
            <div className={`w-8 h-8 rounded-lg ${card.accent} flex items-center justify-center`}>
              {card.icon}
            </div>
          </div>
          <div className="text-2xl font-bold text-text-primary">{card.value}</div>
          <div className="text-xs text-text-muted mt-1">{card.subtitle}</div>
        </div>
      ))}
    </div>
  );
}
