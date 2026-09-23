"""Compare local, real-map crowd profiles; never infer device FPS from headless.

Run after both baseline and candidate, each with at least three repetitions.
Only reads raw evidence. Writes a compact, independently reproducible summary.
"""
import argparse
import hashlib
import json
import statistics
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=Path("outputs/repair_v92"))
    parser.add_argument("--output", type=Path, default=Path("outputs/repair_v93/comparison.json"))
    parser.add_argument("--baseline-commit", default="3eb1cb8f4a80ba24d43cb0f07102b1f79763576d")
    args = parser.parse_args()
    changed_sources = {"res://scripts/enemy.gd", "res://scripts/map_editor/polygon/poly_index.gd",
                       "res://scripts/map_editor/polygon/poly_geometry.gd"}
    baseline_hashes = {}
    for path in changed_sources:
        raw = subprocess.check_output(["git", "show", args.baseline_commit + ":" + path.removeprefix("res://")])
        lf = raw.replace(b"\r\n", b"\n")
        baseline_hashes[path] = {hashlib.sha256(lf).hexdigest(), hashlib.sha256(lf.replace(b"\n", b"\r\n")).hexdigest()}
    groups = {}
    evidence = []
    source_hashes = {"baseline": {}, "candidate": {}}
    for variant in ("baseline", "candidate"):
        prefix = f"world_v93_{variant}_"
        for path in sorted(args.input.glob(prefix + "*.json")):
            data = json.loads(path.read_text(encoding="utf-8"))
            case, trial = path.stem[len(prefix):].rsplit("_", 1)
            assert trial.isdigit(), path
            workload = data["workload"]
            for source, digest in data["source_hashes"].items():
                source_hashes[variant].setdefault(source, set()).add(digest)
                if variant == "baseline" and source in changed_sources:
                    assert digest in baseline_hashes[source], f"baseline is not the recorded commit: {path} {source}"
            count = workload["requested_crowd"]
            total = {913203: 62, 913205: 67}[data["map_id"]]
            assert data["enemy_count"] == total, path
            assert not data["direction_mismatches"], path
            for census in (data["monster_census_before"], data["monster_census_after"]):
                assert census["counts"]["alive"] == total, path
                assert census["counts"]["physics_processing"] == count, path
                assert census["counts"]["target_player"] == count, path
            if "light" in case:
                assert not data["detailed_timing"], path
                assert data["physics_cpu_ms"]["samples"] == 240, path
            else:
                assert data["detailed_timing"], path
                assert data["counters"]["enemy_physics_calls"] == count * 240, path
                assert data["counters"]["engaged_enemy_count"] == count * 240, path
            expected_fields = 0 if "nofire" in case else 8
            assert data["fire_wall_count"] == expected_fields, path
            assert data["sample_physics_frames"] == 240, path
            groups.setdefault(case, {}).setdefault(variant, []).append(data)
            evidence.append({"path": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    rows = []
    for case, variants in sorted(groups.items()):
        assert set(variants) == {"baseline", "candidate"}, f"incomplete pair {case}"
        assert all(len(v) >= 3 for v in variants.values()), f"need 3 repetitions: {case}"
        hashes = {d["workload"]["layout_sha256"] for values in variants.values() for d in values}
        assert len(hashes) == 1, f"layout changed: {case}"
        row = {"case": case, "layout_sha256": hashes.pop(), "runs": {k: len(v) for k, v in variants.items()}}
        metrics = {"enemy_cpu_ms_per_tick": lambda d: d["counters"]["enemy_physics_usec"] / 240000,
                   "environment_cpu_ms_per_tick": lambda d: d["counters"]["environment_query_usec"] / 240000,
                   "physics_moves": lambda d: d["counters"]["physics_moves"]}
        if "light" in case:
            metrics = {"physics_cpu_p50_ms": lambda d: d["physics_cpu_ms"]["p50"],
                       "physics_cpu_p95_ms": lambda d: d["physics_cpu_ms"]["p95"],
                       "physics_cpu_mean_ms": lambda d: statistics.mean(d["physics_cpu_samples_ms"]),
                       "attack_starts": lambda d: sum(a["attack_starts"] for a in d["monster_census_after"]["actors"]),
                       "attack_settlements": lambda d: sum(a["attack_settlements"] for a in d["monster_census_after"]["actors"])}
        for name, getter in metrics.items():
            values = {v: [getter(d) for d in samples] for v, samples in variants.items()}
            medians = {v: statistics.median(nums) for v, nums in values.items()}
            row[name] = {"samples": values, "median": medians,
                         "change_percent": 100 * (medians["candidate"] / medians["baseline"] - 1)
                         if medians["baseline"] else None}
        rows.append(row)
    assert rows, "no evidence found"
    for source in source_hashes["candidate"]:
        assert len(source_hashes["candidate"][source]) == 1, f"candidate source changed during sampling: {source}"
        if source not in changed_sources:
            assert source_hashes["candidate"][source] == source_hashes["baseline"][source], f"fixture or unrelated source changed: {source}"
    result = {"status": "PASS", "scope": "headless local CPU; device performance NOT_RUN",
              "baseline_commit": args.baseline_commit, "fixture_and_unrelated_source_parity": "PASS",
              "comparability": "same layout, map total, engaged count, fields and physics ticks; live AI retains real-time retry clocks",
              "rows": rows, "evidence": evidence}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": "PASS", "cases": len(rows), "output": str(args.output)}))


if __name__ == "__main__":
    main()
