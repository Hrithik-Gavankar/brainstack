# Brainstack Dashboard

Local / demo web UI that visualizes engineer-brain data — work patterns, expertise maps, velocity trends, and growth tracking.

This is a **Delivery-layer consumer** of `BRAIN.md` (see [docs/architecture.md](../docs/architecture.md)). It is separate from `website/`, which is the Docusaurus **product docs** site.

## Features (MVP)

- **Summary Cards** — Total commits, active repos, velocity trend, growth progress
- **Velocity Timeline** — Area chart showing commits per week/month
- **Commit Type Distribution** — Donut chart breaking down feat/fix/refactor/test/chore/docs
- **Active Repos List** — Repos with contribution level badges and last-active indicators
- **Expertise Radar Chart** — Skill map using brain-spec levels: Strong / Growing / Exposure
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

```bash
npm run build   # production build → dist/
npm run preview # serve dist locally
```

## Data Source

Data is loaded through a stable port:

```ts
import { loadDashboardData } from "./src/data/loadDashboardData";

const data = await loadDashboardData({ source: "sample" });
```

| Source | Status | Use |
|--------|--------|-----|
| `sample` | Implemented | Demo fixture (`src/data/sampleData.ts`) — default |
| `brain` | Stub | Future local `BRAIN.md` / scan parser adapter |

`App.tsx` must not import fixtures directly; swap adapters in `loadDashboardData.ts` only.

Expertise categories follow [docs/brain-spec.md](../docs/brain-spec.md): **Strong / Growing / Exposure**.

## Hosting & Privacy

Engineer Brain keeps personal data **local** ([architecture — Security & Privacy](../docs/architecture.md)).

| Mode | Allowed | Notes |
|------|---------|-------|
| **Local** (`npm run dev` / `preview`) | Yes — supported path for real brain data (once the `brain` adapter lands) | Prefer this for personal `BRAIN.md` |
| **Vercel / GitHub Pages / public CDN** | Demo **only** | Deploy the app with `source: "sample"`. **Do not** upload or bake personal `BRAIN.md` into a public deploy |

Public demo tip (Vercel): set **Root Directory** to `dashboard`, build command `npm run build`, output `dist`.

## Architecture

```
dashboard/
├── public/
│   └── favicon.svg
├── src/
│   ├── components/          # React presentation components
│   ├── data/
│   │   ├── loadDashboardData.ts  # Stable data port
│   │   ├── sampleData.ts         # Demo adapter payload
│   │   └── brainAdapter.ts       # Stub for BRAIN.md parser
│   ├── colors.ts            # Chart colors (UI layer)
│   ├── types.ts             # DashboardData + brain-spec types
│   ├── App.tsx
│   ├── main.tsx
│   └── index.css
├── package.json
└── vite.config.ts
```

## Related

- Issue [#26](https://github.com/Hrithik-Gavankar/brainstack/issues/26) — LTS follow-ups
- PR [#25](https://github.com/Hrithik-Gavankar/brainstack/pull/25) — MVP merge
