# Contributing to Engineer Brain

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

```bash
git clone https://github.com/<your-username>/engineer-brain.git
cd engineer-brain
```

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
