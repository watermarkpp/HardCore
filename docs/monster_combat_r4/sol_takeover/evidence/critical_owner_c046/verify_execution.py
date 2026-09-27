"""Audit native completion and the exact formal set; preserve every FAIL."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).parent
read = lambda p: json.loads(p.read_text(encoding="utf-8-sig"))
identity = read(root / "identity.json")
completion = read(root / "completion.json")
expected = read(root / "expected_paths.json")
files = list((root / "runner").glob("runner_results_*.json"))
assert len(files) == 1
native = read(files[0])
rows = native["results"]
actual = [r["test_path"] for r in rows]
errors = []
if len(actual) != len(set(actual)) or sorted(actual) != sorted(expected):
    errors.append("execution_set")
if native["git_head"] != identity["source_head"] or completion["source_head"] != identity["source_head"]:
    errors.append("source_identity")
failed = [r for r in rows if r["result"] == "FAIL"]
if native["failed"] != len(failed) or native["passed"] + len(failed) != len(rows):
    errors.append("aggregate_counts")
if completion["exit_code"] != (1 if failed else 0):
    errors.append("native_exit")
raw = []
for row in rows:
    if row["result"] == "PASS" and (
        not row["pass_marker_found"] or not row["process_exited"]
        or row["effective_exit_code"] != 0 or row["timeout"]
        or row["stderr_failure_count"] or row["engine_log_failure_count"]
    ):
        errors.append("invalid_PASS:" + row["test_path"])
    for suffix in ("stdout.log", "stderr.log", "godot.log"):
        path = root / "runner" / (row["test_name"] + "." + suffix)
        if not path.is_file():
            errors.append("missing_raw:" + str(path))
        else:
            raw.append(dict(path=path.relative_to(root).as_posix(), sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
result = dict(collection_status="FAIL" if errors else "PASS", acceptance_status="FAIL" if failed else "PASS",
              source_head=identity["source_head"], expected=len(expected), actual=len(actual),
              passed=native["passed"], failed=native["failed"], engine_log_errors=native["engine_log_errors"],
              failures=failed, errors=errors, raw=raw,
              scope="Fixed c046 critical run; all original failures retained. Later repairs do not alter this result.")
(root / "exact_execution_check.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({k: v for k, v in result.items() if k != "raw"}, ensure_ascii=False))
raise SystemExit(bool(errors))
