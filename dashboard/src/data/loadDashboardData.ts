import type { DashboardData, LoadDashboardOptions } from "../types";
import { loadFromBrain } from "./brainAdapter";
import { sampleData } from "./sampleData";

/**
 * Stable data port for the dashboard.
 *
 * Swap adapters here without touching App.tsx or chart components.
 * - `sample` — fixture data (default; safe for Vercel/Pages demos)
 * - `brain`  — local BRAIN.md / scan parser (stub until implemented)
 */
export async function loadDashboardData(
  options: LoadDashboardOptions = {},
): Promise<DashboardData> {
  const source = options.source ?? "sample";

  switch (source) {
    case "sample":
      // Clone so callers can treat the payload as immutable-ish after refresh.
      return structuredClone(sampleData);
    case "brain":
      return loadFromBrain();
    default: {
      const _exhaustive: never = source;
      throw new Error(`Unknown dashboard data source: ${_exhaustive}`);
    }
  }
}

export function sourceLabel(source: DashboardData["source"]): string {
  switch (source) {
    case "sample":
      return "Demo data (sample fixture)";
    case "brain":
      return "Local BRAIN.md + git scan";
    default: {
      const _exhaustive: never = source;
      return _exhaustive;
    }
  }
}
