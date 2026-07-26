# Example: Team spike crew

Demo fixture for **Team Brain** (git-backed sync).

## Use in a walkthrough

```bash
cp -r examples/team-spike-crew /path/to/workspace/.team-brain
```

Then in Cursor:

```
/team-brain attach DEMO-EE-1
/team-brain sync DEMO-EE-1
/team-brain breakdown DEMO-EE-1
```

Personal standups stay on `/engineer-brain sync` — do not mix personal `BRAIN.md` into these files.

Teammates stay aligned by committing captures under `.team-brain/` and pulling.
