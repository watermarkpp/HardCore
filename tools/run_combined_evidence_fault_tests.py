"""Retain native FAIL evidence for isolated final save/teardown/reload faults."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import os
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
SCENE = "combined_effect_lifecycle_test"
COLD = "combined_effect_lifecycle_cold_test"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main():
    output = ROOT / "outputs/framework_v2" / ("final_stage_faults_" + datetime.now().strftime("%H%M%S_%f"))
    output.mkdir(parents=True, exist_ok=False)
    matrix = []
    expected_path = ROOT / "outputs/test_logs/framework/combined_effect_lifecycle_expected.json"
    for fault in ("save", "teardown", "reload"):
        before = expected_path.read_bytes() if expected_path.is_file() else b""
        (output / (fault + "_prior_expectation.json")).write_bytes(before)
        env = os.environ.copy()
        env["HARDCORE_AUDIT_RUNTIME_APPDATA"] = str(ROOT / ".godot/runtime_appdata" / ("combined_fault_" + uuid.uuid4().hex))
        env["HARDCORE_COMBINED_FAILURE_STAGE"] = fault
        command = [sys.executable, "-X", "utf8", "tools/source176_r3_validation.py", "audit_c_fault_" + fault,
                   "--tests", "tests/framework/" + SCENE + ".tscn", "tests/framework/" + COLD + ".tscn", "--timeout", "30"]
        native = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, encoding="utf-8")
        (output / (fault + "_wrapper.log")).write_text(native.stdout + native.stderr, encoding="utf-8")
        summary = json.loads(native.stdout.splitlines()[-1])
        directory = Path(summary["evidence"])
        live = read(directory / "framework" / (SCENE + ".result.json"))
        cold = read(directory / "framework" / (COLD + ".result.json"))
        trace = read(directory / "framework/combined_effect_lifecycle_trace.json")
        handoff = read(directory / "framework/native_handoffs.json")
        runner = read(directory / "runner_results.json")
        failed_labels = [row["label"] for row in live["checks"] if not row["passed"]]
        required = {"save": ["final production durability checkpoint succeeds: world_clock_checkpoint_failed"],
                    "teardown": ["explicit world teardown releases final receipt ownership", "official reload retains exactly the combined reward"],
                    "reload": ["official reload retains exactly the combined reward"]}[fault]
        # The intentional blocked directory fails in the production world
        # checkpoint before profile promotion. Preserve that exact I/O error;
        # do not turn an arbitrary engine error into an accepted fault result.
        error_lines = (directory / "raw" / (SCENE + ".stderr.log")).read_text(encoding="utf-8-sig").splitlines()
        actual_errors = [line for line in error_lines if line.startswith("ERROR:") or "SCRIPT ERROR:" in line]
        expected_error = ("ERROR: Could not create directory: '" + env["HARDCORE_AUDIT_RUNTIME_APPDATA"].replace("\\", "/")
                          + "/Godot/app_userdata/HardCore/combined-save-blocker-" + live["run_id"] + "/profiles'.")
        expected_errors = [expected_error] if fault == "save" else []
        verified = (native.returncode == 1 and summary["status"] == "FAIL" and summary["source_stable_during_run"]
                    and runner["failed"] == 2 and runner["engine_log_errors"] == len(expected_errors) and actual_errors == expected_errors
                    and all(row["process_exited"] and row["effective_exit_code"] == 1 for row in runner["results"])
                    and live["status"] == "FAIL" and failed_labels == required
                    and live["count"] == len(live["checks"]) == live["reported_checks"]
                    and cold["status"] == "FAIL" and cold["count"] <= 3
                    and "status" not in trace and "checks" not in trace and trace["phase_status"] == "PASS"
                    and trace["phase"] == "workload_observation_before_final_save_teardown_reload"
                    and trace["phase_checks"] < live["count"] and SCENE not in handoff["producers"]
                    and before == expected_path.read_bytes())
        row = {"fault": fault, "evidence": str(directory), "command": command,
               "isolated_appdata": env["HARDCORE_AUDIT_RUNTIME_APPDATA"],
               "prior_expectation_sha256": hashlib.sha256(before).hexdigest(),
               "native_scene_status": "FAIL", "failed_labels": failed_labels,
               "expected_injected_engine_errors": expected_errors,
               "negative_case_verification": "PASS" if verified else "FAIL"}
        matrix.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)
    report = {"time_utc": datetime.now(timezone.utc).isoformat(), "cases": matrix,
              "status": "PASS" if all(row["negative_case_verification"] == "PASS" for row in matrix) else "FAIL",
              "scope": "Negative test verification only; the six original native FAIL results remain FAIL."}
    (output / "matrix.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"evidence": str(output), "status": report["status"]}), flush=True)
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
