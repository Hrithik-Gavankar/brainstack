import type { DashboardData } from "../types";

/**
 * Future BRAIN.md / scan.sh adapter.
 *
 * Contract: parse local brain data into DashboardData with `source: "brain"`.
 * Must never run against uploaded personal profiles on public hosts.
 *
 * Implementation tracked separately from the data-port seam (#26).
 */
export async function loadFromBrain(): Promise<DashboardData> {
  throw new Error(
    "BRAIN.md adapter is not implemented yet. Use source: \"sample\" for the demo dashboard, or contribute a local parser that maps docs/brain-spec.md → DashboardData.",
  );
}
