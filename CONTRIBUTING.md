# Contributing to Brainstack

Thank you for your interest in contributing! Engineer Brain is an open-source project and we welcome contributions of all kinds.

---

## Ways to Contribute

### Code
- Add support for a new AI platform
- Improve the scanner's pattern detection
- Add new commands
- Fix bugs

### Documentation
- Improve existing docs
- Add examples for different engineering profiles
- Translate documentation
- Fix typos

### Ideas
- Propose new features via GitHub Issues
- Share how you use Engineer Brain
- Suggest improvements to the BRAIN.md spec

---

## Getting Started

### 1. Fork and clone

Fork this repository on GitHub first, then clone **your** fork:

```bash
git clone https://github.com/<your-username>/brainstack.git
cd brainstack
git remote add upstream https://github.com/Hrithik-Gavankar/brainstack.git
```

- `origin` = your fork (you push here)
- `upstream` = this project (you fetch updates from here)

### 2. Create a branch

```bash
git checkout -b feat/your-feature-name
```

Branch naming convention:
- `feat/` — new features
- `fix/` — bug fixes
- `docs/` — documentation changes
- `refactor/` — code restructuring
- `platform/` — new platform adapters

### 3. Make your changes

Follow the existing code style and patterns. Key guidelines:
- Keep Markdown files clean and well-structured
- Use conventional commit messages (`feat:`, `fix:`, `docs:`, etc.)
- Test your changes with at least one platform before submitting

### 4. Commit

```bash
git add .
git commit -m "feat: add support for Zed editor"
```

### 5. Push and create a PR

```bash
git push origin feat/your-feature-name
```

Then open a Pull Request on GitHub.

---

## First-time contributors

New to open source? This section is for you.

### The basic loop

1. **Fork** the repo on GitHub (your copy under your account).
2. **Clone your fork**, then add the original project as `upstream` (see Getting Started above).
3. Create a branch, make one focused change, commit, push to `origin`, open a Pull Request.

### Good first contributions

- Improve documentation (typos, clarity, beginner tips)
- Add an example `BRAIN.md` profile under `examples/` for a role that isn't covered yet
- Fix a small bug or improve `scan.sh` output (check open issues)

Larger items (new platforms, new commands, Web UI) are welcome too — just keep the PR focused on one change.

### Try the tool without polluting your clone

If you want to install Engineer Brain while working on a contribution, point the installer at a **separate playground directory**, not this repository's root:

```bash
mkdir -p /tmp/engineer-brain-playground
bash install.sh cursor /tmp/engineer-brain-playground
```

Installing into the clone root creates `.cursor/` (or other platform files) that are easy to commit by mistake.

### Keeping your fork up to date

```bash
git fetch upstream
git checkout main
git merge upstream/main
git push origin main
```

Do this before starting a new branch so you're building on the latest code.

---

## Adding a New Platform

This is the most common contribution. Here's how:

1. Create `platforms/<platform-name>/`
2. Add the context file in the platform's native format
3. Include the same core content: identity summary, skills, workspace layout, commands, and behavior instructions
4. Add a `README.md` explaining setup for that platform
5. Add an install case in `install.sh`
6. Test it works end-to-end

Reference existing adapters in `platforms/` for examples.

---

## Pull Request Guidelines

- **One feature per PR** — keep PRs focused and reviewable
- **Describe the change** — explain what and why in the PR description
- **Link related issues** — reference any GitHub issues your PR addresses
- **Test your changes** — verify commands work, context loads properly
- **Keep it backwards-compatible** — don't break existing platform installs

---

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you agree to uphold a welcoming, inclusive environment.

---

## Questions?

Open a GitHub Discussion or reach out to [@Hrithik-Gavankar](https://github.com/Hrithik-Gavankar).
