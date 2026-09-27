"""Summarize actual paired intervals; never label engine window monitors P95."""
import argparse
import json
import statistics
from pathlib import Path


def percentile(values, q):
    values = sorted(values)
    p = (len(values) - 1) * q
    lo = int(p)
    hi = min(lo + 1, len(values) - 1)
    return values[lo] + (values[hi] - values[lo]) * (p - lo)


def summarize(path):
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    frames = data["frames"]
    cpu = [f["enemy_inclusive_cpu_ms"] for f in frames]
    intervals = [f["physics_callback_interval_ms"] for f in frames]
    counters = data["counter_deltas"]
    result = {
        "label": data["label"], "head": data["source_head"],
        "enemy_cpu_mean_per_callback_ms": statistics.mean(cpu),
        "enemy_cpu_p95_per_callback_ms": percentile(cpu, .95),
        "callback_interval_mean_ms": statistics.mean(intervals),
        "callback_interval_p95_ms": percentile(intervals, .95),
        "callback_interval_p99_ms": percentile(intervals, .99),
        "callbacks_over_33_33_ms": sum(v > 33.33 for v in intervals),
        "callbacks_over_50_ms": sum(v > 50 for v in intervals),
        "physics_tick_span": frames[-1]["tick"] - frames[0]["tick"] + 1,
        "live_min": min(f["live_count"] for f in frames),
        "live_max": max(f["live_count"] for f in frames),
        "corpse_peak": max(f["corpse_count"] for f in frames),
        "memory_peak_bytes": max(f["memory_bytes"] for f in frames),
        "boot_ms": data["boot_ms"], "runtime_first_casts": data["cold_casts"],
        "starts": data["starts_surviving_actors"], "hp_delta": data["player_hp_delta"],
        "pet_damage": data["pet_actual_damage"], "pet_attack_starts": data["pet_attack_starts"],
        "death_signals": data["death_signals"], "replacements": data["replacements"],
        "drop_rolls": counters.get("drop_roll_count", 0),
        "drop_nodes": counters.get("drop_node_spawn_count", 0),
        "deaths_committed": counters.get("death_queue_committed_count", 0),
        "queries": {k: v for k, v in counters.items() if any(x in k for x in ("query", "queries", "candidates", "path_expansions", "attack_los_"))},
        "failures": data["failures"],
    }
    if data.get("sampling_boundary_version") == "consecutive_native_physics_end.v1":
        ticks = [frame["tick"] for frame in frames]
        assert len(ticks) == 600 and ticks == list(range(data["hot_physics_tick_start"] + 1, data["hot_physics_tick_start"] + 601))
        process_samples = data["process_callbacks"]
        assert len(process_samples) >= 3 and not data["process_sample_overflow"]
        assert process_samples[0]["process_callback_interval_ms"] is None
        process_intervals = [frame["process_callback_interval_ms"] for frame in process_samples[1:]]
        assert all(value is not None and value >= 0 for value in process_intervals)
        result["sampling_boundary_version"] = data["sampling_boundary_version"]
        result["process_callback_count"] = len(process_intervals)
        result["process_callback_interval_mean_ms"] = statistics.mean(process_intervals)
        result["process_callback_interval_p95_ms"] = percentile(process_intervals, .95)
        result["process_callback_interval_p99_ms"] = percentile(process_intervals, .99)
        result["process_callbacks_over_33_33_ms"] = sum(value > 33.33 for value in process_intervals)
        result["process_callbacks_over_50_ms"] = sum(value > 50 for value in process_intervals)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    identity = json.loads((args.root / "identity.json").read_text(encoding="utf-8-sig"))
    runs = json.loads((args.root / "runs.json").read_text(encoding="utf-8-sig"))
    by_label = {r["label"]: summarize(args.root / r["label"] / "load.json") for r in runs if r["exit_code"] == 0}
    conditions = []
    modes = identity["modes"]
    scales = identity["scales"]
    expected_runs = len(modes) * len(scales) * (identity["aa_per_condition"] + 2 * identity["ab_pairs_per_condition"])
    for mode in modes:
        for scale in scales:
            prefix = f"{mode}-{scale}"
            aa = [by_label.get(f"{prefix}-AA-{i}-BASE") for i in (1, 2)]
            pairs = [(by_label.get(f"{prefix}-AB-{i}-BASE"), by_label.get(f"{prefix}-AB-{i}-CAND")) for i in (1, 2, 3)]
            if any(v is None for v in aa) or any(a is None or b is None for a, b in pairs):
                conditions.append({"mode": mode, "scale": scale, "status": "NOT_RUN", "reason": "incomplete AA or three pairs"})
                continue
            key = "enemy_cpu_mean_per_callback_ms"
            noise = abs(aa[0][key] - aa[1][key])
            deltas = [b[key] - a[key] for a, b in pairs]
            conditions.append({
                "mode": mode, "scale": scale, "status": "PASS",
                "aa_absolute_cpu_noise_ms": noise,
                "base_mean_cpu_ms": statistics.mean(a[key] for a, _ in pairs),
                "candidate_mean_cpu_ms": statistics.mean(b[key] for _, b in pairs),
                "paired_cpu_deltas_ms": deltas,
                "sustained_above_aa_noise_regression": all(d > noise for d in deltas),
                "baseline_results": [a for a, _ in pairs], "candidate_results": [b for _, b in pairs],
            })
    result = {"status": "PASS" if len(by_label) == expected_runs and len(runs) == expected_runs and not any(c["status"] != "PASS" for c in conditions) else "NOT_RUN",
              "runs": len(by_label), "expected_runs": expected_runs, "conditions": conditions,
              "scope": "Headless desktop CPU/callback intervals; engine monitor window values deliberately excluded from percentiles; GPU/device NOT_RUN",
              "noise_rule": "A/A absolute difference of mean inclusive enemy CPU per callback; regression flag requires all three paired deltas exceed it. It is a warning requiring trace, not an automatic performance PASS."}
    (args.root / "summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    for c in conditions:
        print({k: v for k, v in c.items() if k not in ("baseline_results", "candidate_results")})


if __name__ == "__main__":
    main()
