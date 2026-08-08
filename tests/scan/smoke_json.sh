#!/usr/bin/env bash
# Smoke test: scan.sh text + --json (issue #3).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCAN="$ROOT/core/scripts/scan.sh"
TMPWS=$(mktemp -d)
trap 'rm -rf "$TMPWS"' EXIT

mkdir -p "$TMPWS/test-repo"
cd "$TMPWS/test-repo"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
printf 'hello\n' > file.txt
git add .
git commit -qm "feat: initial commit"
printf 'fix\n' >> file.txt
git commit -am "fix: typo" -q
git checkout -qb feature/json-scan
printf 'more\n' >> file.txt
git commit -am "docs: note" -q
printf 'dirty\n' >> file.txt

cp "$SCAN" "$TMPWS/scan.sh"
python3 - <<PY
from pathlib import Path
p = Path(r"$TMPWS/scan.sh")
text = p.read_text()
old = r'AUTHOR_PATTERN="your-name\|your-username\|your-email"'
new = 'AUTHOR_PATTERN="Test User"'
if old not in text:
    raise SystemExit("AUTHOR_PATTERN placeholder not found in scan.sh copy")
p.write_text(text.replace(old, new, 1))
PY

echo "=== text mode (section headers) ==="
text_out=$(bash "$TMPWS/scan.sh" "$TMPWS" 7)
printf '%s\n' "$text_out" | grep -q "=== ENGINEER BRAIN SCAN ==="
printf '%s\n' "$text_out" | grep -q "## RECENT COMMITS"
printf '%s\n' "$text_out" | grep -q "## COMMIT TYPE BREAKDOWN"
printf '%s\n' "$text_out" | grep -q "## VELOCITY"
printf '%s\n' "$text_out" | grep -q "=== SCAN COMPLETE ==="
echo "text_ok"

echo "=== JSON schema ==="
bash "$TMPWS/scan.sh" "$TMPWS" 7 --json >"$TMPWS/out.json"
OUT="$TMPWS/out.json" python3 - <<'PY'
import json
import os
from pathlib import Path

d = json.loads(Path(os.environ["OUT"]).read_text())
required = [
    "metadata", "commits", "branches", "uncommitted",
    "type_breakdown", "files_touched", "velocity", "github",
]
missing = [k for k in required if k not in d]
assert not missing, f"missing keys: {missing}"
assert d["metadata"]["period_days"] == 7
assert d["metadata"]["since"]
assert d["metadata"]["scan_time"]
assert len(d["commits"]) >= 1
assert any(c.get("type") == "feat" for c in d["commits"])
assert d["velocity"]["total"] >= 1
assert d["velocity"]["scope"] == "team_repos_only"
assert isinstance(d["type_breakdown"], dict)
assert d["branches"], "expected non-default branch"
assert d["uncommitted"], "expected dirty worktree"
assert "available" in d["github"]
print(
    "schema_ok commits=%d total=%d types=%s"
    % (len(d["commits"]), d["velocity"]["total"], d["type_breakdown"])
)
PY

echo "=== flag positions + jq ==="
bash "$TMPWS/scan.sh" --json "$TMPWS" 7 | jq -e '.metadata.period_days == 7' >/dev/null
bash "$TMPWS/scan.sh" "$TMPWS" --json 7 | jq -e '.velocity.total >= 1' >/dev/null
echo "flag_positions_ok"

echo "=== validation ==="
bash "$TMPWS/scan.sh" --help | grep -q -- '--json'
set +e
bash "$TMPWS/scan.sh" "$TMPWS" 0 --json >/dev/null 2>"$TMPWS/bad.err"
rc=$?
set -e
test "$rc" -ne 0
grep -qi 'positive integer' "$TMPWS/bad.err"
echo "invalid_days_ok rc=$rc"

echo "ALL SMOKE CHECKS PASSED"
