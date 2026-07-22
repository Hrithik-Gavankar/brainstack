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

export interface CommitTypeBreakdown {
  type: string;
  count: number;
  color: string;
}

export interface VelocityPoint {
  period: string;
  commits: number;
}

export interface ExpertiseArea {
  area: string;
  level: number; // 0-100
  category: "strong" | "growing" | "dormant";
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
}
