# Brainstack — VS Code Copilot Setup

## Installation

### Option 1: Auto-install (recommended)

```bash
cd /path/to/your/workspace
bash /path/to/brainstack/install.sh vscode-copilot
```

### Option 2: Manual install

1. Copy the Copilot instructions file:

```bash
mkdir -p /path/to/your/workspace/.github
cp platforms/vscode-copilot/.github/copilot-instructions.md /path/to/your/workspace/.github/
```

2. Create the engineer-brain data directory:

```bash
mkdir -p /path/to/your/workspace/.engineer-brain/scripts
cp core/BRAIN.md /path/to/your/workspace/.engineer-brain/BRAIN.md
cp core/scripts/scan.sh /path/to/your/workspace/.engineer-brain/scripts/scan.sh
cp core/COMMANDS.md /path/to/your/workspace/.engineer-brain/COMMANDS.md
```

3. Edit `.github/copilot-instructions.md` — fill in your career details.

4. Edit `.engineer-brain/scripts/scan.sh` — set your workspace path and git author pattern.

5. Ask Copilot: "@workspace engineer-brain update" to auto-populate BRAIN.md.

## Usage

| Trigger | What You Get |
|---------|-------------|
| `@workspace` "engineer-brain sync" | Ready-to-paste standup notes |
| `@workspace` "update my brain" | Refreshes BRAIN.md with latest data |
| `@workspace` "quarterly review" | Quarterly review content |
| `@workspace` "how am I doing" | Pattern analysis & recommendations |
| `@workspace` "scan my repos 14 days" | Raw git scan output |

## How It Works

- **`.github/copilot-instructions.md`** — loaded as workspace instructions for Copilot Chat
- **`.engineer-brain/BRAIN.md`** — your living engineering profile
- **`.engineer-brain/COMMANDS.md`** — full command reference
- **`.engineer-brain/scripts/scan.sh`** — multi-repo git scanner

## Notes

- GitHub Copilot Chat in VS Code reads `.github/copilot-instructions.md` automatically
- Use `@workspace` to ensure Copilot has full repo context when running commands
- The scanner requires terminal access — Copilot may need you to run it manually
