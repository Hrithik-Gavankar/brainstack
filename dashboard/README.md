# Engineer Brain Dashboard

A web-based UI dashboard that visualizes engineer-brain data — work patterns, expertise maps, velocity trends, and growth tracking — in an interactive, beautiful interface.

## Features (MVP)

- **Summary Cards** — Total commits, active repos, velocity trend, growth progress
- **Velocity Timeline** — Area chart showing commits per week/month
- **Commit Type Distribution** — Donut chart breaking down feat/fix/refactor/test/chore/docs
- **Active Repos List** — Repos with contribution level badges and last-active indicators
- **Expertise Radar Chart** — Visual skill map with strong/growing/dormant classifications
- **Growth Roadmap Tracker** — Checklist with progress bar and category grouping

## Stack

- **React 19** + **TypeScript**
- **Tailwind CSS v4** (via `@tailwindcss/vite`)
- **Recharts** for charts (area, pie, radar)
- **Lucide React** for icons
- **Vite** for build tooling

## Getting Started

```bash
cd dashboard
npm install
npm run dev
```

Open [http://localhost:5173](http://localhost:5173) to view the dashboard.

## Data Source

Currently uses sample data in `src/data/sampleData.ts`. Future versions will parse `BRAIN.md` and `scan.sh` output directly.

## Architecture

```
dashboard/
├── src/
│   ├── components/       # React components
│   │   ├── Header.tsx
│   │   ├── SummaryCards.tsx
│   │   ├── VelocityChart.tsx
│   │   ├── CommitTypeChart.tsx
│   │   ├── RepoList.tsx
│   │   ├── ExpertiseMap.tsx
│   │   └── GrowthTracker.tsx
│   ├── data/
│   │   └── sampleData.ts # Sample data (replace with parser)
│   ├── types.ts          # TypeScript interfaces
│   ├── App.tsx           # Main layout
│   ├── main.tsx          # Entry point
│   └── index.css         # Tailwind + theme
├── package.json
└── vite.config.ts
```
