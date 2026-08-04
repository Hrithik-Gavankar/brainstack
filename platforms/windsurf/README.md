# Brainstack — Windsurf Setup

## Installation

### Option 1: Auto-install (recommended)

```bash
cd /path/to/your/workspace
bash /path/to/brainstack/install.sh windsurf
```

### Option 2: Manual install

1. Copy the Windsurf rules file:

```bash
cp platforms/windsurf/.windsurfrules /path/to/your/workspace/.windsurfrules
```

2. Create the engineer-brain data directory:

```bash
mkdir -p /path/to/your/workspace/.engineer-brain/scripts
cp core/BRAIN.md /path/to/your/workspace/.engineer-brain/BRAIN.md
cp core/scripts/scan.sh /path/to/your/workspace/.engineer-brain/scripts/scan.sh
cp core/COMMANDS.md /path/to/your/workspace/.engineer-brain/COMMANDS.md
```

3. Edit `.windsurfrules` — fill in your career details.

4. Edit `.engineer-brain/scripts/scan.sh` — set your workspace path and git author pattern.

5. Ask Cascade: "engineer-brain update" to auto-populate BRAIN.md.

## Usage

| Trigger | What You Get |
|---------|-------------|
| "engineer-brain sync" / "daily sync" | Ready-to-paste standup notes |
| "engineer-brain update" / "update brain" | Refreshes BRAIN.md with latest data |
| "engineer-brain quarterly" | Quarterly review content |
| "engineer-brain reflect" | Pattern analysis & recommendations |
| "engineer-brain scan 14" | Raw git scan output |

## How It Works

- **`.windsurfrules`** — loaded as project rules on every Cascade interaction
- **`.engineer-brain/BRAIN.md`** — your living engineering profile
- **`.engineer-brain/COMMANDS.md`** — full command reference
- **`.engineer-brain/scripts/scan.sh`** — multi-repo git scanner
