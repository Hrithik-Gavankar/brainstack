# Engineer Brain — Cursor IDE Setup

## Installation

### Option 1: Auto-install (recommended)

```bash
cd /path/to/your/workspace
bash /path/to/engineer-brain/install.sh cursor
```

### Option 2: Manual install

1. Copy the `.cursor` folder structure into your workspace root:

```bash
cp -r platforms/cursor/rules /path/to/your/workspace/.cursor/rules
cp -r platforms/cursor/skills /path/to/your/workspace/.cursor/skills
cp core/scripts/scan.sh /path/to/your/workspace/.cursor/skills/engineer-brain/scripts/
cp core/BRAIN.md /path/to/your/workspace/.cursor/skills/engineer-brain/BRAIN.md
```

2. Edit `.cursor/rules/engineer-brain.mdc` — fill in your career details.

3. Edit `.cursor/skills/engineer-brain/scripts/scan.sh` — configure:
   - `WORKSPACE` default / author `AUTHOR_PATTERN`
   - `PERSONAL_REPOS` — side projects to exclude from team standup metrics
   - `GH_OWNERS` — org names used to filter review results (optional)
   - `RELEASE_REPOS` — `owner/name` repos to check for recent releases (optional)

4. Run `/engineer-brain update` in Cursor to auto-populate BRAIN.md.

**Note:** Your installed `.cursor/skills/engineer-brain/` copy is independent of this
repo. Upstream improvements land here; re-copy `SKILL.md` / `scan.sh` (or re-run
`install.sh`) when you want them in your live workspace. Keep personal `BRAIN.md`
local — never commit it back to this repository.

## Usage

| Command | What You Get |
|---------|-------------|
| `/engineer-brain sync` | Ready-to-paste standup notes |
| `/engineer-brain update` | Refreshes BRAIN.md with latest data |
| `/engineer-brain quarterly` | Quarterly review content |
| `/engineer-brain reflect` | Pattern analysis & recommendations |
| `/engineer-brain scan [days]` | Raw git scan output |

## How It Works

- **`engineer-brain.mdc`** — loaded on every AI interaction (always-on context)
- **`SKILL.md`** — defines the commands with Cursor's skill format
- **`BRAIN.md`** — your living engineering profile
- **`scan.sh`** — multi-repo git scanner
