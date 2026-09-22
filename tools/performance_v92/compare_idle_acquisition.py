"""Compare the existing density fixture before/after idle candidate filtering."""

import argparse
import json
import re
import shutil
import statistics
from pathlib import Path

import compare_monster_density as evidence

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/repair_v92/evidence/idle_acquisition"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-root", required=True, type=Path)
    args = parser.parse_args()
    evidence.OUT = OUT
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    runs = []
    for distance in ("near", "far"):
        before = []
        after = []
        for repeat in (1, 2):
            baseline = ROOT / f"docs/repair_v92/evidence/monster_density/density_idle_{distance}_{repeat}.json"
            old = evidence.read(baseline)
            new, artifacts = evidence.collect(
                ROOT, f"density_idle_gate_{distance}_{repeat}.json",
                f"density_idle_gate_{distance}_{repeat}.console.log")
            for field in ("enemy_count", "sample_physics_frames", "engaged_layout", "damage_calls", "damage_total", "fixture_sha256"):
                assert old[field] == new[field], field
            assert old["start_state"] == new["start_state"] and old["end_state"] == new["end_state"]
            assert old["counters"]["enemy_physics_calls"] == new["counters"]["enemy_physics_calls"]
            for path, digest in old["source_hashes"].items():
                if path != "res://scripts/enemy.gd":
                    assert new["source_hashes"][path] == digest, path
            before.append(old)
            after.append(new)
            runs.append(artifacts)
        row = {"distance": distance}
        for stage, samples in (("before", before), ("after", after)):
            row[stage] = {
                "p95_ms_runs": [sample["frame_ms"]["p95"] for sample in samples],
                "p95_ms_median": statistics.median(sample["frame_ms"]["p95"] for sample in samples),
                "background_usec_runs": [sample["counters"]["enemy_background_tick_usec"] for sample in samples],
                "background_calls_runs": [sample["counters"]["enemy_background_tick_calls"] for sample in samples],
                "background_usec_median": statistics.median(sample["counters"]["enemy_background_tick_usec"] for sample in samples),
                "actor_cpu_usec_per_physics_frame": statistics.median(sample["counters"]["enemy_physics_usec"] / 240 for sample in samples),
                "enemy_source_sha256": samples[0]["source_hashes"]["res://scripts/enemy.gd"],
            }
        rows.append(row)
    formal = []
    for repeat in (1, 2):
        sample, artifacts = evidence.collect(ROOT, f"world_idle_gate_black_{repeat}.json", f"idle_gate_black_{repeat}.console.log")
        assert sample["enemy_count"] == 62 and sample["fire_wall_count"] == 8
        assert not sample["direction_mismatches"]
        assert sample["wall_renderer"]["wall_render_mode"] == "OPTIMIZED"
        formal.append({"frame_ms": sample["frame_interval_ms"],
                       "counts": sample["monster_census_after"]["counts"],
                       "layout_sha256": sample["initial_layout_sha256"],
                       "actor_cpu_usec": sample["counters"]["enemy_physics_usec"],
                       "enemy_source_sha256": sample["source_hashes"]["res://scripts/enemy.gd"]})
        runs.append(artifacts)
    validation = []
    for root, label, classification in (
        (ROOT, "idle_acquisition_red", "FAIL: fixture attempted to override a static projection helper"),
        (ROOT, "idle_acquisition_valid_red", "FAIL: before production repair, 100 unnecessary safety/threat queries"),
        (ROOT, "idle_acquisition_green", "FAIL: fixture overlapped player at spawn; original acquisition/cache tests PASS"),
        (ROOT, "idle_acquisition_green_fixed_fixture", "PASS: exact boundary, threat, safety and real timer wake"),
        (ROOT, "idle_acquisition_regression", "8 PASS / 1 FAIL: baseline projection-counter expectation"),
        (args.baseline_root, "idle_density_baseline_repro", "FAIL: same projection-counter failure on unchanged b961 production"),
        (ROOT, "idle_acquisition_followup", "4 PASS: density fixture repaired plus HC runtime/world obstacle/magic target"),
    ):
        console = root / f"outputs/test_logs/{label}.console.log"
        match = re.search(r"RUNNER_RESULTS_JSON=(.+)", console.read_text(encoding="utf-8-sig"))
        assert match
        runner = Path(match.group(1).strip())
        record = {"classification": classification, "result": evidence.read(runner), "artifacts": []}
        for source in (console, runner):
            destination = OUT / source.name
            if destination.exists():
                assert evidence.digest(destination) == evidence.digest(source)
            else:
                shutil.copy2(source, destination)
            record["artifacts"].append({"file": source.name, "sha256": evidence.digest(destination)})
        validation.append(record)
    assert evidence.digest(ROOT / "scripts/enemy.gd") == rows[0]["after"]["enemy_source_sha256"]
    result = {"functional_status": "PASS", "phone_fps_status": "NOT_RUN",
              "method": "Unchanged density fixture, 12 engaged + 50 idle, 240 physics frames, near/far twice each; frozen prior runs retained.",
              "limitation": "Headless only; wall-clock p95 includes scheduling. Older/newer runs are not interleaved, so small differences do not prove total FPS benefit.",
              "density": rows, "formal_black": formal, "runs": runs, "validation": validation}
    (OUT / "comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for row in rows:
        print(json.dumps(row, ensure_ascii=False))
    print("IDLE_ACQUISITION_EVIDENCE_PASS runs=6; DEVICE TEST: NOT_RUN")


if __name__ == "__main__":
    main()
