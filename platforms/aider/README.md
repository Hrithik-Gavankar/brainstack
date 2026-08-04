# Brainstack — Aider Setup

## Installation

### Option 1: Auto-install (recommended)

```bash
cd /path/to/your/workspace
bash /path/to/brainstack/install.sh aider
```

### Option 2: Manual install

1. Copy the Aider conventions file:

```bash
cp platforms/aider/CONVENTIONS.md /path/to/your/workspace/CONVENTIONS.md
```

2. Create the engineer-brain data directory:

```bash
mkdir -p /path/to/your/workspace/.engineer-brain/scripts
cp core/BRAIN.md /path/to/your/workspace/.engineer-brain/BRAIN.md
cp core/scripts/scan.sh /path/to/your/workspace/.engineer-brain/scripts/scan.sh
cp core/COMMANDS.md /path/to/your/workspace/.engineer-brain/COMMANDS.md
```

3. Edit `CONVENTIONS.md` — fill in your career details.

4. Edit `.engineer-brain/scripts/scan.sh` — set your workspace path and git author pattern.

5. Add to your `.aider.conf.yml`:
```yaml
read:
  - CONVENTIONS.md
  - .engineer-brain/BRAIN.md
  - .engineer-brain/COMMANDS.md
```

## Usage

In Aider chat, use natural language:

| Trigger | What You Get |
|---------|-------------|
| "run my daily sync" | Ready-to-paste standup notes |
| "update my brain" | Refreshes BRAIN.md with latest data |
| "generate quarterly review" | Quarterly review content |
| "reflect on my patterns" | Pattern analysis & recommendations |
| "/run bash .engineer-brain/scripts/scan.sh . 14" | Raw git scan output |

## How It Works

- **`CONVENTIONS.md`** — read file loaded as context in every session
- **`.engineer-brain/BRAIN.md`** — your living engineering profile
- **`.engineer-brain/COMMANDS.md`** — full command reference
- **`.engineer-brain/scripts/scan.sh`** — multi-repo git scanner
