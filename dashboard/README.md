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

Open [http://localhost:5173](http://localhost:5173) to view the engineer dashboard.

**Team Brain admin review inbox** (local only — [#69](https://github.com/Hrithik-Gavankar/brainstack/issues/69)):

```bash
# Optional: pre-fill Supabase project (same vars as CLI / supabase/project.public.env)
export VITE_TEAM_BRAIN_SUPABASE_URL=https://xxxx.supabase.co
export VITE_TEAM_BRAIN_SUPABASE_ANON_KEY=eyJ...

npm run dev
# → http://localhost:5173/admin/review
```

Connect with a crew **admin** `tb_…` API key (session storage only). Approve/reject calls the same RPCs as `pending list|approve|reject` in `core/scripts/team-brain-api.sh`. Never deploy real keys to GitHub Pages.

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
| `brain` | Stub | Future local `BRAIN.md` / `scan.sh --json` adapter (#3 unlocks structured scan input) |

`App.tsx` must not import fixtures directly; swap adapters in `loadDashboardData.ts` only.

Expertise categories follow [docs/brain-spec.md](../docs/brain-spec.md): **Strong / Growing / Exposure**.

## Hosting & Privacy

`engineer-brain` keeps personal data **local** ([architecture — Security & Privacy](../docs/architecture.md)).

| Mode | Allowed | Notes |
|------|---------|-------|
| **Local** (`npm run dev` / `preview`) | Yes — supported path for real brain data (once the `brain` adapter lands) | Prefer this for personal `BRAIN.md` |
| **Vercel / GitHub Pages / public CDN** | Demo **only** | Deploy the app with `source: "sample"`. **Do not** upload or bake personal `BRAIN.md` into a public deploy |

### GitHub Pages (demo)

The dashboard auto-deploys from `main` when files under `dashboard/` change (see [`.github/workflows/dashboard-pages.yml`](../.github/workflows/dashboard-pages.yml)).

**Live demo:** https://hrithik-gavankar.github.io/brainstack/

One-time repo setup (Settings → Pages → Build and deployment → Source: **GitHub Actions**).

Local build with the same base path as Pages:

```bash
VITE_BASE_PATH=/brainstack/ npm run build
npm run preview
```

Public demo tip (Vercel): set **Root Directory** to `dashboard`, build command `npm run build`, output `dist`.

## Team Brain admin review queue

Admin-only inbox for pending memory overrides (#67 / #69). Workshop-friendly alternative to `pending list` JSON in the terminal.

| View | Source |
|------|--------|
| Pending queue | `list_pending_memories` RPC (`status = pending`, optional `p_jira_key`) |
| Diff panel | Proposed `body_preview` vs live capture via `list_recent` + `target_capture_id` |
| Metadata | `conflict_reason`, author, `match_metadata.matches`, timestamps |
| Actions | `approve_pending_memory` · `reject_pending_memory` (admin role required) |

**Auth:** Same trust model as CLI — `tb_…` api_key in `sessionStorage`, Supabase anon key for REST RPC calls. No anon `SELECT` on `memory_pending_submissions`; RPC-only.

**Privacy:** Team-scoped like `list_members`. Never surfaces personal `BRAIN.md`.

**Route:** `/admin/review` (pathname switch in `Root.tsx`; no extra router dependency).

```
dashboard/src/
├── admin/                   # Team Brain review inbox (#69)
│   ├── AdminReviewApp.tsx
│   ├── AdminCredentialsForm.tsx
│   ├── PendingSubmissionCard.tsx
│   └── MemoryDiffPanel.tsx
├── team-brain/
│   ├── rpc.ts               # Supabase REST RPC client
│   ├── session.ts             # sessionStorage credentials
│   └── types.ts
├── Root.tsx                   # /admin/review vs engineer dashboard
```

See [docs/team-brain-memory.md §7c](../docs/team-brain-memory.md#7c-redundant-memory-feedback--admin-approval-queue-67).

## Architecture

```
dashboard/
├── public/
│   └── favicon.svg
├── src/
│   ├── admin/               # Team Brain review inbox (local admin only)
│   ├── team-brain/          # RPC client + types
│   ├── components/          # Engineer dashboard presentation
│   ├── data/
│   │   ├── loadDashboardData.ts  # Stable data port
│   │   ├── sampleData.ts         # Demo adapter payload
│   │   └── brainAdapter.ts       # Stub for BRAIN.md parser
│   ├── colors.ts            # Chart colors (UI layer)
│   ├── types.ts             # DashboardData + brain-spec types
│   ├── App.tsx              # Engineer dashboard (sample data)
│   ├── Root.tsx             # Route: /admin/review → AdminReviewApp
│   ├── main.tsx
│   └── index.css
├── package.json
└── vite.config.ts
```

## Related

- Issue [#26](https://github.com/Hrithik-Gavankar/brainstack/issues/26) — LTS follow-ups
- PR [#25](https://github.com/Hrithik-Gavankar/brainstack/pull/25) — MVP merge
