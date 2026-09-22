"""Preserve real-input roaming attribution separately from fixed-layout A/B."""
import json
import compare_monster_density as evidence

ROOT = evidence.ROOT
OUT = ROOT / "docs/repair_v92/evidence/roaming_monsters"


def main():
    evidence.OUT = OUT
    OUT.mkdir(parents=True, exist_ok=True)
    rows, runs = [], []
    for name, expected_count, fields in (("black", 62, 0), ("black_fire", 62, 8), ("death", 71, 0), ("red", 54, 0)):
        label = f"roaming_{name}_1"
        sample, artifacts = evidence.collect(ROOT, f"world_{label}.json", f"{label}.console.log")
        assert sample["enemy_count"] == expected_count
        assert sample["fire_wall_count"] == fields
        assert sample["wall_renderer"]["wall_render_mode"] == "OPTIMIZED"
        assert not sample["direction_mismatches"]
        for path, sha in sample["source_hashes"].items():
            assert evidence.digest(ROOT / path.removeprefix("res://")) == sha, path
        motion = sample["monster_census_after"]["roaming"]
        assert len(motion["phases"]) == 8 and motion["distance_gu"] > 1
        assert len(motion["frames"]) == 240
        rows.append({"name": name, "map_id": sample["map_id"], "enemy_count": expected_count,
                     "fire_wall_count": fields, "actual_distance_gu": motion["distance_gu"],
                     "active_min": min(s["physics_active"] for s in motion["frames"]),
                     "active_max": max(s["physics_active"] for s in motion["frames"]),
                     "pending_max": max(s["pending_paths"] for s in motion["frames"]),
                     "actor_ms": motion["actor_ms_per_observed_physics_frame"],
                     "process_interval_ms": sample["frame_interval_ms"],
                     "scheduler": sample["scheduler_after"], "source_hashes": sample["source_hashes"]})
        runs.append(artifacts)
    result = {"functional_status": "PASS", "device_status": "NOT_RUN", "rows": rows, "runs": runs,
              "scope": "Real GameRoot movement input, player physics/collision, original spawn population, eight 0.5-second directional phases, 240 sampled physics frames.",
              "limits": "Short local route, not all corridors or a long session. Diagnostic snapshot/census overhead is present. Cached Godot physics monitor values include pre-sample loading and must not be called instantaneous long frames. Actor counter deltas are direct CPU attribution; no GPU rendering is measured."}
    (OUT / "comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for row in rows:
        print(json.dumps({key: value for key, value in row.items() if key != "source_hashes"}, ensure_ascii=False))
    print("ROAMING_MONSTER_EVIDENCE_PASS runs=4; DEVICE TEST: NOT_RUN")


if __name__ == "__main__":
    main()
