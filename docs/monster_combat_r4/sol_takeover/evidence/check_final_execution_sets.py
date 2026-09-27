"""Check actual final execution identities; does not decide performance acceptance."""
import json
import hashlib
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
EVIDENCE = Path(__file__).resolve().parent
SOURCE = "6407fddaaa9ac3e1e388ff866758d91610ea26fd"
CRITICAL_SOURCE = "3b21c115da6b8d5ed57e706432912dafcb377748"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def check_set(directory, expected, source):
    files = list((directory / "runner").glob("runner_results_*.json"))
    if len(files) != 1:
        return {"status": "MISSING", "runner_count": len(files)}
    data = read(files[0])
    rows = data["results"]
    paths = [row["test_path"] for row in rows]
    invalid = [row for row in rows if not (
        row.get("result") == "PASS" and row.get("process_exited") is True
        and row.get("timeout") is False and row.get("wrapper_exit_code") == 0
        and row.get("effective_exit_code") == 0
        and row.get("stdout_failure_count") == 0
        and row.get("stderr_failure_count") == 0
        and row.get("engine_log_failure_count") == 0
    )]
    missing, extra = sorted(set(expected) - set(paths)), sorted(set(paths) - set(expected))
    valid = (
        len(paths) == len(set(paths)) == len(expected) and not missing and not extra
        and not invalid and data["git_head"] == source
        and data["failed"] == 0 and data["engine_log_errors"] == 0
    )
    return {
        "status": "PASS" if valid else "FAIL", "runner": files[0].name,
        "source_head": data["git_head"], "expected": len(expected),
        "actual": len(paths), "unique": len(set(paths)),
        "missing": missing, "extra": extra, "invalid_results": invalid,
    }


def main():
    pipeline = read(EVIDENCE / "verification_pipeline_report_closure.json")
    if any(pipeline.get(key) != "PASS" for key in (
        "critical", "clean_import", "clean_tests", "performance_matrix"
    )):
        raise SystemExit("Final collection not complete; no gate result written")
    critical = check_set(EVIDENCE / "final_critical_after_closure", read(EVIDENCE / "expected_critical_paths.json"), CRITICAL_SOURCE)
    plan = read(EVIDENCE / "clean_checkout_final/planned_tests.json")
    clean = check_set(EVIDENCE / "clean_checkout_report_closure", plan["paths"], SOURCE)
    matrix = EVIDENCE / "t6_pairs_final_v5"
    identity, runs = read(matrix / "identity.json"), read(matrix / "runs.json")
    invalid_samples = []
    for row in runs:
        sample = read(matrix / row["label"] / "load.json")
        runner_files = list((matrix / row["label"] / "runner").glob("runner_results_*.json"))
        expected_head = identity["base_head"] if row["side"] == "BASE" else SOURCE
        invalid = (
            row["exit_code"] != 0 or sample["source_head"] != expected_head
            or sample["label"] != row["label"] or len(sample["frames"]) != 600
            or bool(sample["failures"]) or sample.get("production_hot_test_mode") is not False
            or sample.get("random_input_version") != "all_gameplay_actors_spawn_casts_drop_identities_production_hot.v5"
            or len(runner_files) != 1
        )
        inputs = sample.get("random_inputs", {})
        deaths = inputs.get("death_identity_inputs", [])
        keys = [d["fixed_key"] for d in deaths]
        invalid = invalid or inputs.get("drop_session") != "20260927000000000000000000000000" or sample.get("isolated_profile_namespace") != matrix.name
        if row["mode"] == "aoe_death_loot":
            invalid = invalid or len(deaths) != sample["death_signals"] or len(keys) != len(set(keys)) or not inputs.get("equipment_identity_inputs")
        for d in deaths:
            expected_key = f"death:{int(d['map_id'])}:{int(d['generation'])}:{int(d['sequence'])}:{int(d['spawn_ordinal'])}"
            invalid = invalid or d["fixed_key"] != expected_key
        for equipment in inputs.get("equipment_identity_inputs", []):
            key = equipment["stable_key"]
            digest = hashlib.sha256(f"item.drop.instance.v1|{int(equipment['item_id'])}|{key}".encode()).hexdigest()
            invalid = invalid or equipment["digest"] != digest or equipment["instance_id"] != f"drop:v1:{int(equipment['item_id'])}:{digest[:24]}"
        if len(runner_files) == 1:
            actual_runner = read(runner_files[0])
            invalid = invalid or actual_runner["git_head"] != expected_head or actual_runner["passed"] != 1 or actual_runner["failed"] != 0 or actual_runner["engine_log_errors"] != 0
        if invalid:
            invalid_samples.append(row["label"])
    labels = [row["label"] for row in runs]
    perf_valid = (
        len(labels) == len(set(labels)) == 72 and not invalid_samples
        and identity["candidate_head"] == SOURCE
        and identity["base_head"] == "1381d2838a3736f4a06699dd24a8cf4a10714950"
    )
    source_diff = subprocess.run([
        "git", "-C", str(ROOT), "diff", "--quiet", SOURCE, "--",
        "scripts", "tests", "tools", "assets", "map_editor_workspace", "project.godot", "export_presets.cfg"
    ]).returncode
    result = {
        "source_head": SOURCE, "critical_source_head": CRITICAL_SOURCE, "critical": critical, "clean": clean,
        "performance_collection": {"status": "PASS" if perf_valid else "FAIL", "count": len(labels), "invalid_samples": invalid_samples},
        "source_worktree_difference_exit_code": source_diff,
        "performance_acceptance": "NOT_RUN",
        "note": "Exact execution sets, normal exits and fixed source identities only. Controller must review paired CPU/noise and tail latency separately. Device/GPU NOT_RUN.",
    }
    result["status"] = "PASS" if critical["status"] == clean["status"] == "PASS" and perf_valid and source_diff == 0 else "FAIL"
    (EVIDENCE / "final_execution_sets.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))
    raise SystemExit(0 if result["status"] == "PASS" else 1)


if __name__ == "__main__":
    main()
