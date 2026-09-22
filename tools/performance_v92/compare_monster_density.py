"""Archive serial density experiments; keep functional and device claims separate."""

import argparse
import hashlib
import json
import re
import shutil
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/repair_v92/evidence/monster_density"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def collect(root, filename, console_name):
    raw = root / "outputs/repair_v92" / filename
    console = root / "outputs/test_logs" / console_name
    result = read(raw)
    match = re.search(r"RUNNER_RESULTS_JSON=(.+)", console.read_text(encoding="utf-8-sig"))
    assert match, console
    runner = Path(match.group(1).strip())
    verdict = read(runner)
    assert verdict["passed"] == 1 and verdict["failed"] == 0
    assert verdict["engine_log_errors"] == 0
    check = verdict["results"][0]
    assert check["effective_exit_code"] == 0 and check["process_exited"]
    assert check["result"] == "PASS" and not check["timeout"]
    assert result["display_server"] == "headless"
    artifacts = []
    for path in (raw, console, runner):
        destination = OUT / path.name
        if destination.exists():
            assert digest(destination) == digest(path), f"Historical evidence changed: {destination}"
        else:
            shutil.copy2(path, destination)
        artifacts.append({"file": destination.name, "sha256": digest(destination)})
    return result, {"raw": raw.name, "runner": runner.name, "artifacts": artifacts}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-root", required=True, type=Path)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    runs = []
    groups = []
    fixture_hashes = set()
    production_hashes = []
    for condition in ("idle", "occluded"):
        for distance in ("near", "far"):
            samples = []
            for repeat in (1, 2):
                label = f"{condition}_{distance}_{repeat}"
                sample, evidence = collect(ROOT, f"density_{label}.json", f"density_{label}.console.log")
                assert sample["enemy_count"] == 62 and sample["sample_physics_frames"] == 240
                assert sample["damage_calls"] == 16
                assert sample["mode"] == distance
                assert sample["occluded_pursuit"] == (condition == "occluded")
                expected_active = 62 if condition == "occluded" and distance == "near" else 12
                for state in (sample["start_state"], sample["end_state"]):
                    assert state["engaged"] == expected_active
                    assert state["physics_processing"] == expected_active
                    assert state["visual_processing"] == (62 if distance == "near" else 12)
                fixture_hashes.add(sample["fixture_sha256"])
                production_hashes.append(sample["source_hashes"])
                runs.append(evidence)
                samples.append(sample)
            groups.append({
                "condition": condition, "distance": distance,
                "p95_ms_median": statistics.median(s["frame_ms"]["p95"] for s in samples),
                "p95_ms_runs": [s["frame_ms"]["p95"] for s in samples],
                "enemy_cpu_usec_per_physics_frame_median": statistics.median(
                    s["counters"]["enemy_physics_usec"] / 240 for s in samples),
                "visual_updates": [s["counters"]["visual_animation_updates"] for s in samples],
                "start_states": [s["start_state"] for s in samples],
                "end_states": [s["end_state"] for s in samples],
                "scheduler_at_end": [s["scheduler"] for s in samples],
                "damage_calls": [s["damage_calls"] for s in samples],
            })
    assert len(fixture_hashes) == 1
    assert all(item == production_hashes[0] for item in production_hashes)
    maps = []
    for label in ("black_1", "death_1", "red_1", "current_black_no_fire", "v91_black"):
        root = args.baseline_root if label == "v91_black" else ROOT
        raw, evidence = collect(root, f"world_density_census_{label}.json", f"density_census_{label}.console.log")
        maps.append({"label": label, "map_id": raw["map_id"], "enemies": raw["enemy_count"],
                     "layout_sha256": raw["initial_layout_sha256"], "fields": raw["fire_wall_count"],
                     "before": raw["monster_census_before"]["counts"],
                     "after": raw["monster_census_after"]["counts"],
                     "scheduler_before": raw["scheduler_before"], "scheduler_after": raw["scheduler_after"],
                     "renderer": raw["wall_renderer"], "source_hashes": raw["source_hashes"],
                     "frame_interval_ms": raw["frame_interval_ms"]})
        runs.append(evidence)
    # The old and new actors do not produce identical combat states. These
    # two runs establish sleep/render-mode behavior, not a speedup percentage.
    assert maps[-1]["layout_sha256"] == maps[-2]["layout_sha256"]
    snapshots = {}
    for relative in ("tests/monster_background_density_profile_test.gd",
                     "tests/world_crowd_firewall_profile_test.gd"):
        source = ROOT / relative
        expected = next(iter(fixture_hashes)) if "background_density" in relative else maps[0]["source_hashes"]["res://" + relative]
        assert digest(source) == expected, f"Fixture changed after recording: {relative}"
        target = OUT / (source.name + ".txt")
        target.write_bytes(source.read_bytes())
        snapshots[relative] = {"file": target.name, "sha256": expected}
    result = {"functional_status": "PASS", "valid_runs": len(runs),
              "phone_fps_status": "NOT_RUN", "overall_performance_acceptance": "FAIL",
              "method": "12 attacking + 50 additional actors, near/far x idle/last-seen pursuit x two repeats; formal-map census outside timed window.",
              "limitations": ["Headless display uses dummy rendering; intervals are not device FPS.",
                              "Occluded fixture uses a grid WORLD wall and seeded prior target observation, not an authored polygon map.",
                              "Formal map stationary census did not reproduce path queueing.",
                              "Resident texture byte counters estimate decoded RGBA8, not actual mobile GPU residency."],
              "density_source_hashes": production_hashes[0], "fixture_snapshots": snapshots,
              "groups": groups, "formal_maps": maps, "runs": runs}
    (OUT / "comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for group in groups:
        print(group["condition"], group["distance"], group["p95_ms_runs"], group["enemy_cpu_usec_per_physics_frame_median"])
    print(f"MONSTER_DENSITY_EVIDENCE_PASS runs={len(runs)}; DEVICE TEST: NOT_RUN")


if __name__ == "__main__":
    main()
