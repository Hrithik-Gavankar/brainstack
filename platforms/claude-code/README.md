# Brainstack — Claude Code Setup

## Installation

### Option 1: Auto-install (recommended)

```bash
cd /path/to/your/workspace
bash /path/to/brainstack/install.sh claude-code
```

### Option 2: Manual install

1. Copy the Claude Code instructions file to your workspace:

```bash
cp platforms/claude-code/CLAUDE.md /path/to/your/workspace/CLAUDE.md
```

2. Create the engineer-brain data directory:

```bash
mkdir -p /path/to/your/workspace/.engineer-brain/scripts
cp core/BRAIN.md /path/to/your/workspace/.engineer-brain/BRAIN.md
cp core/scripts/scan.sh /path/to/your/workspace/.engineer-brain/scripts/scan.sh
```

3. Edit `CLAUDE.md` — fill in your career details in the Brainstack Context section.

4. Edit `.engineer-brain/scripts/scan.sh` — set your workspace path and git author pattern.

5. Ask Claude: "engineer-brain update" to auto-populate BRAIN.md.

## Usage

Claude Code responds to natural language. These all work:

| Trigger | What You Get |
|---------|-------------|
| "engineer-brain sync" / "daily sync" / "standup" | Ready-to-paste standup notes |
| "engineer-brain update" / "update my brain" | Refreshes BRAIN.md with latest data |
| "engineer-brain quarterly" / "quarterly review" | Quarterly review content |
| "engineer-brain reflect" / "how am I doing" | Pattern analysis & recommendations |
| "engineer-brain scan 14" / "scan my repos" | Raw git scan output |

## How It Works

- **`CLAUDE.md`** — loaded as project instructions on every interaction
- **`.engineer-brain/BRAIN.md`** — your living engineering profile
- **`.engineer-brain/scripts/scan.sh`** — multi-repo git scanner
- Command logic is embedded in the CLAUDE.md instructions
