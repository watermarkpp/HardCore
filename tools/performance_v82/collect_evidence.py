"""Collect the final serial A/B runs without mixing earlier diagnostic samples."""
import hashlib
import json
from pathlib import Path
import shutil
import statistics

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "outputs/performance_v82"
EVIDENCE = ROOT / "docs/performance_v82/evidence"
PREFIX = "v82_final"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main():
    receipt = read(OUT / (PREFIX + "_receipt.json"))
    assert receipt["candidate_restored"] and len(receipt["runs"]) == 12
    assert all(run["exit_code"] == 0 for run in receipt["runs"])
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    groups = {}
    layout = {}
    for run in receipt["runs"]:
        label = run["label"]
        mode, version, _ = label.removeprefix(PREFIX + "_").split("_")
        source = ROOT / "outputs/hc_monster_ai_package" / ("rev07_" + label + ".json")
        report = read(source)
        assert report["sample_frames"] == 320 and report["counts"] == [30]
        assert report["layout_seed"] == 20260909
        for row in report["rows"]:
            # The fixture waits 320 physics ticks; unlocked process callbacks
            # can run more often. Keep every interval, as the fixture does.
            assert row["actual_actor_count"] == 30 and len(row["full_frame_ms_raw"]) >= 320
            assert row["enemy_metrics"]["enemy_physics_calls"] == 30 * 320
            key = mode + ":" + row["scenario"]
            initial = [actor["initial_ground_gu"] for actor in row["actor_proof"]]
            assert layout.setdefault(key, initial) == initial, "Initial actor placement changed"
            hits = sum(f["damage_application_count"] for f in row["fire_wall_diagnostics"])
            if mode == "aoe":
                assert row["fire_wall_fields"] == 6 and hits > 0
                assert all(f["visual_cell_count"] == 9 and f["tick_count"] >= 5
                           and f["duplicate_damage_count"] == 0 for f in row["fire_wall_diagnostics"])
            groups.setdefault(key, {}).setdefault(version, []).append({
                "label": label,
                "process_interval_count": len(row["full_frame_ms_raw"]),
                "p95_ms": row["full_frame_ms"]["p95"],
                "max_ms": row["full_frame_ms"]["max"],
                "enemy_physics_ms_per_tick": row["enemy_metrics"]["enemy_physics_usec"] / 320000.0,
                "attacks": row["total_attack_starts"],
                "motion_gu": row["total_motion_gu"],
                "aoe_damage_applications": hits,
            })
        shutil.copyfile(source, EVIDENCE / source.name)
    for group in groups.values():
        medians = {}
        for version in ("baseline", "candidate"):
            assert len(group[version]) == 3
            medians[version] = {key: statistics.median(row[key] for row in group[version])
                                for key in ("p95_ms", "max_ms", "enemy_physics_ms_per_tick")}
        group["medians"] = medians
        group["p95_reduction_percent"] = 100 * (1 - medians["candidate"]["p95_ms"] / medians["baseline"]["p95_ms"])
    for name in (PREFIX + "_inputs.json", PREFIX + "_receipt.json",
                 "component_baseline_r1.json", "component_texture_cache_r1.json",
                 "component_prepared_music_r1.json"):
        shutil.copyfile(OUT / name, EVIDENCE / name)
    source_hashes = {}
    for path in ("scripts/enemy.gd", "scripts/caster_skill_visual_registry.gd",
                 "scripts/prepared_music_stream.gd", "scripts/town_music_controller.gd",
                 "tests/hc_monster_ai/m30_sampling_copy.gd"):
        data = (ROOT / path).read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if path in receipt["candidate_sha256"]:
            assert digest == receipt["candidate_sha256"][path]
        source_hashes[path] = {"sha256": digest,
            "lf_normalized_sha256": hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest()}
    summary = {"status": "PASS", "measurement_scope": "desktop headless CPU and frame intervals; not Android/GPU",
               "baseline_commit": receipt["baseline_commit"], "source_hashes": source_hashes,
               "groups": groups, "device": "NOT_RUN"}
    (EVIDENCE / "performance_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for key, group in groups.items():
        print(key, group["medians"], "P95 reduction %", round(group["p95_reduction_percent"], 2))


if __name__ == "__main__":
    main()
