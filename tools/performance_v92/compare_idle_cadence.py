"""Archive the idle wake cadence change without rewriting prior measurements."""

import json
import re
import shutil
import statistics
from pathlib import Path

import compare_monster_density as evidence

ROOT = evidence.ROOT
OUT = ROOT / "docs/repair_v92/evidence/idle_cadence"


def main():
    evidence.OUT = OUT
    OUT.mkdir(parents=True, exist_ok=True)
    rows, runs, formal, validation = [], [], [], []
    source_hashes = set()
    for distance in ("near", "far"):
        stages = {"before": [], "after": []}
        for repeat in (1, 2):
            old = evidence.read(ROOT / f"docs/repair_v92/evidence/idle_acquisition/density_idle_gate_{distance}_{repeat}.json")
            new, artifacts = evidence.collect(
                ROOT, f"density_idle_cadence_{distance}_{repeat}.json",
                f"density_idle_cadence_{distance}_{repeat}.console.log")
            for key in ("enemy_count", "sample_physics_frames", "engaged_layout", "damage_calls", "damage_total", "fixture_sha256", "start_state", "end_state"):
                assert old[key] == new[key], key
            assert old["counters"]["enemy_physics_calls"] == new["counters"]["enemy_physics_calls"]
            assert new["counters"]["enemy_background_tick_calls"] < old["counters"]["enemy_background_tick_calls"]
            for path, sha in old["source_hashes"].items():
                if path != "res://scripts/enemy.gd":
                    assert new["source_hashes"][path] == sha, path
            source_hashes.add(new["source_hashes"]["res://scripts/enemy.gd"])
            stages["before"].append(old)
            stages["after"].append(new)
            runs.append(artifacts)
        row = {"distance": distance}
        for stage, samples in stages.items():
            row[stage] = {
                "p95_ms": [s["frame_ms"]["p95"] for s in samples],
                "background_calls": [s["counters"]["enemy_background_tick_calls"] for s in samples],
                "background_usec": [s["counters"]["enemy_background_tick_usec"] for s in samples],
                "actor_usec_per_physics_frame": [s["counters"]["enemy_physics_usec"] / 240 for s in samples],
                "enemy_sha256": samples[0]["source_hashes"]["res://scripts/enemy.gd"],
            }
        for key in ("p95_ms", "background_calls", "background_usec"):
            row[key + "_median_change_percent"] = 100 * (
                statistics.median(row["after"][key]) / statistics.median(row["before"][key]) - 1)
        rows.append(row)
    for repeat in (1, 2):
        sample, artifacts = evidence.collect(ROOT, f"world_idle_cadence_black_{repeat}.json", f"idle_cadence_black_{repeat}.console.log")
        assert sample["enemy_count"] == 62 and sample["fire_wall_count"] == 8
        assert sample["wall_renderer"]["wall_render_mode"] == "OPTIMIZED"
        assert not sample["direction_mismatches"]
        source_hashes.add(sample["source_hashes"]["res://scripts/enemy.gd"])
        formal.append({"frame_interval_ms": sample["frame_interval_ms"],
                       "counts": sample["monster_census_after"]["counts"],
                       "layout_sha256": sample["initial_layout_sha256"],
                       "background_calls": sample["counters"]["enemy_background_tick_calls"],
                       "background_usec": sample["counters"]["enemy_background_tick_usec"],
                       "actor_usec": sample["counters"]["enemy_physics_usec"]})
        runs.append(artifacts)
    assert source_hashes == {evidence.digest(ROOT / "scripts/enemy.gd")}
    for label, expected_failed in (("idle_scan_cadence_red", 1), ("idle_scan_cadence_green", 0), ("idle_scan_cadence_regression", 0)):
        console = ROOT / f"outputs/test_logs/{label}.console.log"
        match = re.search(r"RUNNER_RESULTS_JSON=(.+)", console.read_text(encoding="utf-8-sig"))
        assert match
        runner = Path(match.group(1).strip())
        result = evidence.read(runner)
        assert result["failed"] == expected_failed
        record = {"label": label, "results": result, "artifacts": []}
        for path in (console, runner):
            target = OUT / path.name
            if target.exists():
                assert evidence.digest(target) == evidence.digest(path)
            else:
                shutil.copy2(path, target)
            record["artifacts"].append({"file": target.name, "sha256": evidence.digest(target)})
        validation.append(record)
    result = {"functional_status": "PASS", "device_status": "NOT_RUN",
              "policy": "Resting untargeted ordinary actors wake every 0.5 s; returning/active maintenance and shared target grid remain 0.25 s; damage wakes immediately.",
              "limitations": "Headless desktop, separated runs, wall intervals include scheduling. This is not an Android CPU/GPU or FPS result. The previous retarget deadline already skipped some 0.25 s maintenance wakes.",
              "enemy_sha256": next(iter(source_hashes)), "density": rows,
              "formal_black": formal, "runs": runs, "validation": validation}
    (OUT / "comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for row in rows:
        print(json.dumps(row, ensure_ascii=False))
    print("IDLE_CADENCE_EVIDENCE_PASS runs=6; DEVICE TEST: NOT_RUN")


if __name__ == "__main__":
    main()
