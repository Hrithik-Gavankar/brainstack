import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  CartesianGrid,
} from "recharts";
import type { VelocityPoint } from "../types";

interface VelocityChartProps {
  data: VelocityPoint[];
}

function CustomTooltip({ active, payload, label }: { active?: boolean; payload?: Array<{ value: number }>; label?: string }) {
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-surface-hover border border-border-dim rounded-lg px-3 py-2 shadow-lg">
      <p className="text-xs text-text-muted">{label}</p>
      <p className="text-sm font-medium text-text-primary">
        {payload[0].value} commits
      </p>
    </div>
  );
}

export function VelocityChart({ data }: VelocityChartProps) {
  return (
    <div className="rounded-xl border border-border-dim bg-surface-card p-5">
      <h3 className="text-sm font-medium text-text-secondary mb-4">
        Velocity Timeline
      </h3>
      <div className="h-56">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={data} margin={{ top: 5, right: 5, bottom: 0, left: -20 }}>
            <defs>
              <linearGradient id="velocityGradient" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="#5c7cfa" stopOpacity={0.3} />
                <stop offset="100%" stopColor="#5c7cfa" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" stroke="#2a2d3a" vertical={false} />
            <XAxis
              dataKey="period"
              tick={{ fill: "#5c5e6a", fontSize: 11 }}
              axisLine={{ stroke: "#2a2d3a" }}
              tickLine={false}
              interval="preserveStartEnd"
            />
            <YAxis
              tick={{ fill: "#5c5e6a", fontSize: 11 }}
              axisLine={false}
              tickLine={false}
            />
            <Tooltip content={<CustomTooltip />} />
            <Area
              type="monotone"
              dataKey="commits"
              stroke="#5c7cfa"
              strokeWidth={2}
              fill="url(#velocityGradient)"
              dot={{ fill: "#5c7cfa", r: 3, strokeWidth: 0 }}
              activeDot={{ fill: "#5c7cfa", r: 5, strokeWidth: 2, stroke: "#181a24" }}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
