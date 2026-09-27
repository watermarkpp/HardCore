"""Verify a completed fixed-source runner without rewriting its raw evidence."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


parser = argparse.ArgumentParser()
parser.add_argument("evidence", type=Path)
args = parser.parse_args()
root = args.evidence.resolve()
if not (root / "completion.json").is_file():
    raise SystemExit("NOT_RUN: native runner is not complete; no verdict written")
identity = read(root / "identity.json")
completion = read(root / "completion.json")
expected_file = root / "expected_paths.json"
expected = read(expected_file)
results = list((root / "runner").glob("runner_results_*.json"))
if len(results) != 1:
    raise SystemExit("FAIL: require exactly one native runner result")
native = read(results[0])
rows = native["results"]
actual = [row["test_path"] for row in rows]
failures = [row for row in rows if row["result"] == "FAIL"]
errors = []
if len(expected) != identity["expected_count"] or len(set(expected)) != len(expected):
    errors.append("expected_set_identity")
if digest(expected_file).lower() != identity["expected_paths_sha256"].lower():
    errors.append("expected_set_hash")
if len(actual) != len(set(actual)) or actual != expected:
    errors.append("actual_execution_set_or_order")
if native["suite"] != identity["suite"]:
    errors.append("suite_identity")
if native["git_head"] != identity["source_head"] or completion["source_head"] != identity["source_head"]:
    errors.append("native_source_identity")
if native["total"] != len(rows) or native["failed"] != len(failures) or native["passed"] + len(failures) != len(rows):
    errors.append("aggregate_counts")
if completion["exit_code"] != (1 if failures else 0):
    errors.append("outer_native_exit")
if any(row["result"] not in ("PASS", "FAIL") for row in rows):
    errors.append("unknown_runner_status")
project = Path(identity["project_root"])


def git(*arguments):
    return subprocess.check_output(["git", "-C", str(project), *arguments], text=True).strip()


if git("rev-parse", "HEAD") != identity["source_head"]:
    errors.append("checkout_head_changed")
if git("rev-parse", "HEAD^{tree}") != identity["source_tree"]:
    errors.append("checkout_tree_identity")
if git("diff", "--name-only", "HEAD", "--", "scripts", "tests", "tools", "assets", "project.godot", "export_presets.cfg"):
    errors.append("tracked_runtime_input_dirty")
untracked_runtime = [path for path in git("ls-files", "--others", "--exclude-standard", "--",
                                         "scripts", "tests", "tools", "assets").splitlines()
                     if not path.endswith(".uid")]
if untracked_runtime:
    errors.append("untracked_runtime_inputs")
runner = project / "tools/run_godot_tests.ps1"
engine = project / "tools/godot-4.7/Godot_v4.7-stable_win64_console.exe"
if digest(runner).lower() != identity["runner_sha256"].lower():
    errors.append("runner_identity")
if digest(engine).lower() != identity["engine_sha256"].lower():
    errors.append("engine_identity")
raw = []
for row in rows:
    if row["result"] == "PASS" and (
        not row["pass_marker_found"] or not row["process_exited"]
        or row["effective_exit_code"] != 0 or row["timeout"]
        or row["child_process_exit_state"] != "exited"
        or row["stdout_failure_count"] or row["stderr_failure_count"]
        or row["engine_log_failure_count"] or row["reason"]
    ):
        errors.append("invalid_PASS:" + row["test_path"])
    for suffix in ("stdout.log", "stderr.log", "godot.log"):
        path = root / "runner" / (row["test_name"] + "." + suffix)
        if not path.is_file():
            errors.append("missing_raw:" + str(path))
        else:
            raw.append(dict(path=path.relative_to(root).as_posix(), bytes=path.stat().st_size, sha256=digest(path)))
if native["engine_log_errors"] != sum(row["engine_log_failure_count"] for row in rows):
    errors.append("engine_error_aggregate")
result = dict(collection_status="FAIL" if errors else "PASS",
              acceptance_status="FAIL" if errors or failures else "PASS",
              source_head=identity["source_head"], source_tree=identity["source_tree"],
              expected=len(expected), actual=len(actual), passed=native["passed"], failed=native["failed"],
              engine_log_errors=native["engine_log_errors"], failures=failures, errors=errors, raw=raw,
              untracked_runtime_inputs=untracked_runtime,
              runner_result=dict(path=results[0].relative_to(root).as_posix(), sha256=digest(results[0])),
              scope="Completed independent fixed-source critical run; performance, device and later integration are separate gates.")
output = root / "exact_execution_check.json"
if output.exists():
    raise SystemExit("FAIL: refuse to overwrite an existing verdict")
output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({key: value for key, value in result.items() if key != "raw"}, ensure_ascii=False))
raise SystemExit(2 if errors else 1 if failures else 0)
