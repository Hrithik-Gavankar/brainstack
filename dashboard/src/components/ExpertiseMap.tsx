import {
  RadarChart,
  Radar,
  PolarGrid,
  PolarAngleAxis,
  PolarRadiusAxis,
  ResponsiveContainer,
  Tooltip,
} from "recharts";
import type { ExpertiseArea, ExpertiseCategory } from "../types";

interface ExpertiseMapProps {
  data: ExpertiseArea[];
}

const CATEGORIES: ExpertiseCategory[] = ["strong", "growing", "exposure"];

const categoryColors: Record<ExpertiseCategory, string> = {
  strong: "text-green-accent",
  growing: "text-brain-400",
  exposure: "text-text-muted",
};

const categoryLabels: Record<ExpertiseCategory, string> = {
  strong: "Strong",
  growing: "Growing",
  exposure: "Exposure",
};

function CustomTooltip({ active, payload }: { active?: boolean; payload?: Array<{ payload: ExpertiseArea }> }) {
  if (!active || !payload?.length) return null;
  const d = payload[0].payload;
  return (
    <div className="bg-surface-hover border border-border-dim rounded-lg px-3 py-2 shadow-lg">
      <p className="text-sm font-medium text-text-primary">{d.area}</p>
      <p className="text-xs text-text-secondary">
        {categoryLabels[d.category]} &middot; {d.level}%
      </p>
    </div>
  );
}

export function ExpertiseMap({ data }: ExpertiseMapProps) {
  return (
    <div className="rounded-xl border border-border-dim bg-surface-card p-5">
      <h3 className="text-sm font-medium text-text-secondary mb-4">
        Expertise Map
      </h3>
      <div className="h-64">
        <ResponsiveContainer width="100%" height="100%">
          <RadarChart data={data} cx="50%" cy="50%" outerRadius="70%">
            <PolarGrid stroke="#2a2d3a" />
            <PolarAngleAxis
              dataKey="area"
              tick={{ fill: "#8b8d98", fontSize: 11 }}
            />
            <PolarRadiusAxis
              angle={90}
              domain={[0, 100]}
              tick={false}
              axisLine={false}
            />
            <Radar
              dataKey="level"
              stroke="#5c7cfa"
              strokeWidth={2}
              fill="#5c7cfa"
              fillOpacity={0.15}
              dot={{ fill: "#5c7cfa", r: 3 }}
            />
            <Tooltip content={<CustomTooltip />} />
          </RadarChart>
        </ResponsiveContainer>
      </div>
      <div className="flex items-center justify-center gap-5 mt-2">
        {CATEGORIES.map((cat) => (
          <div key={cat} className="flex items-center gap-1.5">
            <div
              className={`w-2 h-2 rounded-full ${
                cat === "strong"
                  ? "bg-green-accent"
                  : cat === "growing"
                    ? "bg-brain-400"
                    : "bg-text-muted"
              }`}
            />
            <span className={`text-xs ${categoryColors[cat]}`}>
              {categoryLabels[cat]} ({data.filter((d) => d.category === cat).length})
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
