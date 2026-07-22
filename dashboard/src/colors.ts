/** Presentation colors for commit-type charts (kept out of DashboardData). */
export const COMMIT_TYPE_COLORS: Record<string, string> = {
  feat: "#40c057",
  fix: "#ff6b6b",
  refactor: "#9775fa",
  chore: "#fcc419",
  docs: "#22b8cf",
  test: "#ff922b",
  ci: "#748ffc",
  style: "#f06595",
  perf: "#20c997",
  build: "#845ef7",
};

export function colorForCommitType(type: string): string {
  return COMMIT_TYPE_COLORS[type.toLowerCase()] ?? "#8b8d98";
}
