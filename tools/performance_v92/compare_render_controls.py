"""Compare the serial legacy/optimized formal-map runs without estimating GPU FPS.

Input: world_render_control_<map id>_<legacy|optimized>_<1|2>.json,
produced by tests/world_crowd_firewall_profile_test.tscn through the normal runner.
Run from any directory with Python 3.12; no third-party dependencies.
"""

import hashlib
import json
import shutil
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INPUT = ROOT / "outputs/repair_v92"
OUTPUT = ROOT / "docs/repair_v92/evidence/render_control"
MAPS = {913203: "黑暗地带", 913207: "死亡棺材", 916003: "抉择之地"}


def median(values):
    return statistics.median(values)


def percent(before, after):
    return (after / before - 1.0) * 100.0 if before else None


def physical_sprites(counts):
    # All map environment sprites, including unchanged decorations/bridges.
    # A Sprite2D count is not a measured draw-call count.
    return sum(counts[k] for k in (
        "wrapper_dynamic_children", "static_sprite_count",
        "static_chunk_count", "bridge_overlay_count"))


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    # Bind historical runs to their frozen inputs. Reading today's source here
    # would silently relabel old measurements after another production repair.
    manifest = json.loads((OUTPUT / "source_manifest.json").read_text(encoding="utf-8-sig"))
    input_hashes = {row["label"]: row["sha256"] for row in manifest["input_hashes"]}
    evidence = {
        "baseline_head": manifest["baseline_head"],
        "method": "Same working-tree code, legacy/optimized each twice in reversed order; headless only.",
        "source_hashes": manifest["source_hashes"], "maps": [], "runs": [],
        "device_test": "NOT_RUN", "gpu_frame_time": "NOT_RUN",
    }
    for map_id, name in MAPS.items():
        groups = {}
        common = []
        for mode in ("legacy", "optimized"):
            runs = []
            for repetition in (1, 2):
                label = f"render_control_{map_id}_{mode}_{repetition}"
                path = INPUT / f"world_{label}.json"
                assert hashlib.sha256(path.read_bytes()).hexdigest() == input_hashes[label], f"historical input overwritten: {label}"
                data = json.loads(path.read_text(encoding="utf-8"))
                assert data["display_server"] == "headless"
                assert data["wall_renderer"]["wall_render_mode"] == mode.upper()
                assert data["expected_renderer"] == mode.upper()
                assert data["formal_cast"] and data["fire_wall_count"] == 8
                assert data["sample_physics_frames"] == 240
                assert data["direction_mismatches"] == {}
                assert len(data["fire_wall"]) == 8
                for field in data["fire_wall"]:
                    assert field["visual_cell_count"] == 9
                    assert field["duplicate_damage_count"] == 0
                    assert field["tick_count"] == 5
                if mode == "optimized":
                    assert data["wall_renderer"]["wall_render_plan_valid"]
                    assert not data["wall_renderer"]["wall_render_fallback_reason"]
                    assert data["wall_renderer"]["derived_prefetch_failure_count"] == 0
                else:
                    assert data["wall_renderer"]["wall_render_fallback_reason"] == "forced legacy (WALL_RENDER_FORCE_LEGACY)"
                common.append(tuple(data[k] for k in (
                    "enemy_count", "initial_layout_sha256", "focus", "nearby_initial",
                    "camera_position", "camera_zoom")))
                counts = data["wall_object_counts"]
                run = {
                    "label": label, "input_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                    "frame_interval_ms": data["frame_interval_ms"],
                    "enemy_cpu_ms": data["counters"]["enemy_physics_usec"] / 1000.0,
                    "enemy_physics_calls": data["counters"]["enemy_physics_calls"],
                    "enemy_cpu_usec_per_call": data["counters"]["enemy_physics_usec"] / data["counters"]["enemy_physics_calls"],
                    "wall_object_counts": counts, "physical_environment_sprites": physical_sprites(counts),
                    "fire_wall_damage_applications": sum(f["damage_application_count"] for f in data["fire_wall"]),
                    "fire_wall_ticks": [f["tick_count"] for f in data["fire_wall"]],
                }
                runs.append(run)
                evidence["runs"].append(run)
                shutil.copy2(path, OUTPUT / path.name)
                log = ROOT / f"outputs/test_logs/{label}.console.log"
                shutil.copy2(log, OUTPUT / log.name)
                for line in log.read_text(encoding="utf-8-sig").splitlines():
                    if line.startswith("RUNNER_RESULTS_JSON="):
                        runner = Path(line.split("=", 1)[1])
                        result = json.loads(runner.read_text(encoding="utf-8-sig"))
                        assert result["passed"] == 1 and result["failed"] == 0 and result["engine_log_errors"] == 0
                        assert "TEST_SUMMARY suite=adhoc passed=1 failed=0 engine_log_errors=0" in log.read_text(encoding="utf-8-sig")
                        shutil.copy2(runner, OUTPUT / runner.name)
            groups[mode] = runs
        assert all(value == common[0] for value in common), f"workload/camera changed in {map_id}"
        for mode, runs in groups.items():
            assert runs[0]["wall_object_counts"] == runs[1]["wall_object_counts"], f"physical layout drift: {map_id}/{mode}"
        before, after = groups["legacy"], groups["optimized"]
        row = {"map_id": map_id, "name": name, "enemy_count": common[0][0],
               "layout_sha256": common[0][1], "workload_match": "PASS"}
        for key in ("logical_total", "logical_y_sort", "logical_static", "wrapper_count"):
            assert before[0]["wall_object_counts"][key] == after[0]["wall_object_counts"][key]
        for key in ("physical_environment_sprites", "enemy_cpu_ms", "enemy_cpu_usec_per_call"):
            old, new = median(r[key] for r in before), median(r[key] for r in after)
            row[key] = {"legacy": old, "optimized": new, "change_percent": percent(old, new)}
        old = median(r["frame_interval_ms"]["p95"] for r in before)
        new = median(r["frame_interval_ms"]["p95"] for r in after)
        row["headless_p95_ms"] = {"legacy": old, "optimized": new, "change_percent": percent(old, new),
            "legacy_runs": [r["frame_interval_ms"]["p95"] for r in before],
            "optimized_runs": [r["frame_interval_ms"]["p95"] for r in after]}
        row["legacy_counts"] = before[0]["wall_object_counts"]
        row["optimized_counts"] = after[0]["wall_object_counts"]
        row["damage_application_counts"] = {mode: [r["fire_wall_damage_applications"] for r in runs] for mode, runs in groups.items()}
        evidence["maps"].append(row)
    evidence["functional_control"] = "PASS"
    (OUTPUT / "comparison.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence["maps"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
