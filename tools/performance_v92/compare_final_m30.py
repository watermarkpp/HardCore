"""Verify adjacent baseline/current M30 runs without conflating device FPS."""
import argparse
import json
import re
import shutil
import statistics
from pathlib import Path

import compare_monster_density as evidence

ROOT = evidence.ROOT
OUT = ROOT / "docs/repair_v92/evidence/m30_idle_final_ab"


def collect(root, label):
    raw = root / f"outputs/hc_monster_ai_package/rev07_{label}.json"
    console = root / f"outputs/test_logs/{label}.console.log"
    match = re.search(r"RUNNER_RESULTS_JSON=(.+)", console.read_text(encoding="utf-8-sig"))
    assert match
    runner = Path(match.group(1).strip())
    verdict = evidence.read(runner)
    assert verdict["passed"] == 1 and verdict["failed"] == 0 and verdict["engine_log_errors"] == 0
    item = verdict["results"][0]
    assert item["process_exited"] and item["effective_exit_code"] == 0 and not item["timeout"]
    sample = evidence.read(raw)
    assert sample["display_driver"] == "headless"
    for path, sha in sample["source_hashes_sha256"].items():
        assert evidence.digest(root / path.removeprefix("res://")) == sha, path
    artifacts = []
    for path in (raw, console, runner):
        destination = OUT / path.name
        if destination.exists():
            assert evidence.digest(destination) == evidence.digest(path)
        else:
            shutil.copy2(path, destination)
        artifacts.append({"file": destination.name, "sha256": evidence.digest(destination)})
    return sample, artifacts


def main():
    global OUT
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-root", required=True, type=Path)
    parser.add_argument("--phase", choices=("idle", "query_lane"), default="idle")
    args = parser.parse_args()
    prefix = "v92_cpu_close2" if args.phase == "idle" else "v92_cpu_lane_final"
    if args.phase == "query_lane":
        OUT = ROOT / "docs/repair_v92/evidence/m30_query_lane_final_ab"
    OUT.mkdir(parents=True, exist_ok=True)
    runs, rows, samples = [], [], {}
    mismatches = []
    for lane in ("baseline", "current"):
        for mode in ("crowd", "aoe"):
            for repeat in (1, 2):
                label = f"{prefix}_{lane}_{mode}_{repeat}"
                sample, artifacts = collect(args.baseline_root if lane == "baseline" else ROOT, label)
                assert sample["counts"] == [30] and sample["warmup_frames"] == 45 and sample["sample_frames"] == 320
                assert sample["source_hashes_sha256"]["res://tests/hc_monster_ai/m30_sampling_copy.gd"] == "b7350a05afeab07b2896d16280f8b88cd45040167ebf8a211359142e56cbd7d4"
                samples[lane, mode, repeat] = sample
                runs.append({"label": label, "artifacts": artifacts, "source_hashes": sample["source_hashes_sha256"]})
    # The first old-code AOE run advanced 322 actual physics ticks during its
    # 320 await iterations. Retain it as a valid execution, but use the named
    # replacement for an exactly matched 320-tick comparison, not for speed.
    exclusions = []
    if args.phase == "idle":
        excluded = samples["baseline", "aoe", 1]
        assert excluded["rows"][0]["sample_physics_ticks"] == 322
        replacement, artifacts = collect(args.baseline_root, "v92_cpu_close2_baseline_aoe_3")
        assert replacement["rows"][0]["sample_physics_ticks"] == 320
        assert replacement["source_hashes_sha256"] == excluded["source_hashes_sha256"]
        samples["baseline", "aoe", 1] = replacement
        runs.append({"label": "v92_cpu_close2_baseline_aoe_3", "artifacts": artifacts,
                     "source_hashes": replacement["source_hashes_sha256"]})
        exclusions.append({"label": "v92_cpu_close2_baseline_aoe_1", "reason": "322 actual physics ticks, not the common 320; functional PASS retained", "actual_physics_ticks": 322})
    for mode, scenarios in (("crowd", ("open_pursuit", "sustained_close_attacks", "dense_crowd")), ("aoe", ("sustained_close_attacks",))):
        for scenario in scenarios:
            comparison = {"mode": mode, "scenario": scenario}
            invariant = None
            case_mismatches = []
            for lane in ("baseline", "current"):
                cases = []
                for repeat in (1, 2):
                    case = next(row for row in samples[lane, mode, repeat]["rows"] if row["scenario"] == scenario)
                    proof = {key: case[key] for key in ("layout_signature", "initial_layout", "actual_actor_count", "total_attack_starts", "total_attack_damage_applications", "target_damage_calls", "sample_physics_ticks", "fire_wall_fields")}
                    if invariant is None:
                        invariant = proof
                    if proof != invariant:
                        case_mismatches.append({
                            "lane": lane, "mode": mode, "repeat": repeat, "scenario": scenario,
                            "differences": {key: {"reference": invariant[key], "observed": proof[key]}
                                            for key in proof if proof[key] != invariant[key]},
                        })
                    cases.append(case)
                comparison[lane] = {"p95_ms": [c["full_frame_ms"]["p95"] for c in cases],
                                    "actor_usec_per_call": [c["enemy_metrics"]["enemy_physics_usec"] / c["enemy_metrics"]["enemy_physics_calls"] for c in cases],
                                    "physics_calls": [c["enemy_metrics"]["enemy_physics_calls"] for c in cases]}
            old = statistics.median(comparison["baseline"]["p95_ms"])
            new = statistics.median(comparison["current"]["p95_ms"])
            comparison["p95_change_percent"] = 100 * (new / old - 1)
            comparison["performance_gate"] = "PASS" if new <= max(old * 1.05, old + 0.5) else "FAIL"
            comparison["behavior"] = {key: value for key, value in invariant.items() if key != "initial_layout"}
            if case_mismatches:
                comparison["performance_gate"] = "BLOCKED"
                comparison["p95_change_percent"] = None
                comparison["behavior"] = None
                comparison["comparison_mismatches"] = case_mismatches
                mismatches.extend(case_mismatches)
            rows.append(comparison)
    result = {"functional_status": "PASS", "device_status": "NOT_RUN",
              "order": "baseline1, current1, current2, baseline2; crowd then aoe in each block; replacements, if any, are explicitly recorded",
              "excluded_from_ab": exclusions,
              "scope": "Desktop headless fixed 30 real actors, original fixture and collision/attack schedule; no phone GPU or presented-frame claim.",
              "comparison_status": "FAIL" if mismatches else "PASS",
              "comparison_mismatches": mismatches,
              "rows": rows, "runs": runs}
    (OUT / "comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for row in rows:
        print(json.dumps(row, ensure_ascii=False))
    # Preserve the rejected batch and every raw timing, while keeping the
    # original strict equality gate fatal. Never silently discard a bad pair
    # or substitute a faster repeat to manufacture performance acceptance.
    assert not mismatches, f"M30_FINAL_AB_COMPARABILITY_FAIL phase={args.phase}; see comparison.json"
    print(f"M30_FINAL_AB_EVIDENCE_PASS phase={args.phase} runs={len(runs)}; DEVICE TEST: NOT_RUN")


if __name__ == "__main__":
    main()
