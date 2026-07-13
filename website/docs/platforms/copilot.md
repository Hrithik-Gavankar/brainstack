---
sidebar_position: 3
---

# GitHub Copilot (VS Code)

Engineer Brain integrates with GitHub Copilot via `.github/copilot-instructions.md`.

## Files installed

- `.github/copilot-instructions.md` — Copilot custom instructions
- `.engineer-brain/BRAIN.md` — Your living profile
- `.engineer-brain/COMMANDS.md` — Command definitions
- `.engineer-brain/scripts/scan.sh` — Git scanner

## Installation

```bash
bash install.sh vscode-copilot ~/my-workspace
```

## Usage

In VS Code with Copilot Chat:

```
@workspace engineer-brain sync
@workspace engineer-brain update
```

Or use natural language — Copilot reads the instructions file automatically.
