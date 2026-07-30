import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from "recharts";
import { colorForCommitType } from "../colors";
import type { CommitTypeBreakdown } from "../types";

interface CommitTypeChartProps {
  data: CommitTypeBreakdown[];
}

type ChartRow = CommitTypeBreakdown & { color: string };

function CustomTooltip({ active, payload }: { active?: boolean; payload?: Array<{ payload: ChartRow }> }) {
  if (!active || !payload?.length) return null;
  const d = payload[0].payload;
  return (
    <div className="bg-surface-hover border border-border-dim rounded-lg px-3 py-2 shadow-lg">
      <p className="text-sm font-medium text-text-primary capitalize">{d.type}</p>
      <p className="text-xs text-text-secondary">{d.count} commits</p>
    </div>
  );
}

export function CommitTypeChart({ data }: CommitTypeChartProps) {
  const total = data.reduce((sum, d) => sum + d.count, 0);
  const chartData: ChartRow[] = data.map((item) => ({
    ...item,
    color: colorForCommitType(item.type),
  }));

  return (
    <div className="rounded-xl border border-border-dim bg-surface-card p-5">
      <h3 className="text-sm font-medium text-text-secondary mb-4">Commit Types</h3>
      <div className="flex items-center gap-6">
        <div className="w-40 h-40 flex-shrink-0">
          <ResponsiveContainer width="100%" height="100%">
            <PieChart>
              <Pie
                data={chartData}
                cx="50%"
                cy="50%"
                innerRadius={45}
                outerRadius={70}
                dataKey="count"
                stroke="none"
                paddingAngle={3}
              >
                {chartData.map((entry) => (
                  <Cell key={entry.type} fill={entry.color} />
                ))}
              </Pie>
              <Tooltip content={<CustomTooltip />} />
            </PieChart>
          </ResponsiveContainer>
        </div>
        <div className="flex-1 space-y-2.5">
          {chartData.map((item) => {
            const pct = total === 0 ? 0 : Math.round((item.count / total) * 100);
            return (
              <div key={item.type} className="flex items-center gap-3">
                <div
                  className="w-2.5 h-2.5 rounded-full flex-shrink-0"
                  style={{ backgroundColor: item.color }}
                />
                <span className="text-sm text-text-secondary capitalize flex-1">{item.type}</span>
                <span className="text-sm font-medium text-text-primary">{item.count}</span>
                <span className="text-xs text-text-muted w-10 text-right">{pct}%</span>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
