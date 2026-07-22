/** Expertise levels from docs/brain-spec.md (Active Repos / Skills Inventory). */
export type ExpertiseCategory = "strong" | "growing" | "exposure";

/** Which adapter produced the dashboard payload. */
export type DataSource = "sample" | "brain";

export interface EngineerProfile {
  name: string;
  role: string;
  company: string;
  experience: string;
  careerGoal: string;
  tools: string[];
}

export interface RepoActivity {
  name: string;
  role: string;
  contributionLevel: "Heavy" | "Medium" | "Light" | "Exploring";
  lastActive: string;
  focusArea: string;
  commitCount: number;
}

/** Counts only — chart colors live in the UI layer (`colors.ts`). */
export interface CommitTypeBreakdown {
  type: string;
  count: number;
}

export interface VelocityPoint {
  period: string;
  commits: number;
}

export interface ExpertiseArea {
  area: string;
  /** 0–100 display scale for the radar chart. */
  level: number;
  category: ExpertiseCategory;
}

export interface GrowthItem {
  id: string;
  category: string;
  goal: string;
  completed: boolean;
}

export interface DashboardData {
  profile: EngineerProfile;
  totalCommits: number;
  activeRepos: number;
  totalRepos: number;
  velocityTrend: "up" | "down" | "stable";
  velocityChange: number;
  repos: RepoActivity[];
  commitTypes: CommitTypeBreakdown[];
  velocity: VelocityPoint[];
  expertise: ExpertiseArea[];
  growthItems: GrowthItem[];
  lastUpdated: string;
  /** Adapter that produced this payload. */
  source: DataSource;
}

export interface LoadDashboardOptions {
  /**
   * Prefer `brain` when a BRAIN.md parser adapter is available.
   * Defaults to `sample` (demo / Vercel-safe).
   */
  source?: DataSource;
}
