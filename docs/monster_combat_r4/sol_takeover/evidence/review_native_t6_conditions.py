"""Collect exact, completed native pairs without deciding performance policy."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
read = lambda p: json.loads(p.read_text(encoding="utf-8-sig"))
names = [
    "native_t6_aoe30_1b74_20260928_0556",
    "native_t6_small30_1b74_20260928_0604",
    "native_t6_large_pets30_1b74_20260928_0604",
]
required = {"aoe_death_loot", "small", "large_pets"}
rows = []
raw = []
heads = set()
for name in names:
    root = ROOT / name
    identity, completion, exact, summary = [read(root / part) for part in
                                           ("identity.json", "completion.json", "exact_execution_check.json", "summary.json")]
    assert completion["exit_code"] == 0 and exact["status"] == summary["status"] == "PASS", name
    assert exact["actual"] == exact["unique"] == exact["expected"] == 8 and not exact["errors"], name
    assert identity["candidate_head"] == completion["candidate_head"] == exact["candidate_head"], name
    assert identity["base_head"] == completion["base_head"] == exact["base_head"], name
    heads.add((exact["base_head"], exact["candidate_head"]))
    assert identity["sampling_boundary_version"] == "consecutive_native_physics_end.v1", name
    assert identity["frames"] == 600 and len(summary["conditions"]) == 1, name
    c = summary["conditions"][0]
    assert c["status"] == "PASS" and c["mode"] in required and c["scale"] == 30, name
    required.remove(c["mode"])
    base, candidate = c["baseline_results"], c["candidate_results"]
    assert len(base) == len(candidate) == 3, name
    pairs = []
    for b, d in zip(base, candidate):
        assert b["sampling_boundary_version"] == d["sampling_boundary_version"] == identity["sampling_boundary_version"]
        assert b["physics_tick_span"] == d["physics_tick_span"] == 600
        pairs.append({
            "base": b["label"], "candidate": d["label"],
            "enemy_cpu_delta_ms": d["enemy_cpu_mean_per_callback_ms"] - b["enemy_cpu_mean_per_callback_ms"],
            "physics_p99_delta_ms": d["callback_interval_p99_ms"] - b["callback_interval_p99_ms"],
            "process_p99_delta_ms": d["process_callback_interval_p99_ms"] - b["process_callback_interval_p99_ms"],
            "physics_over_50_delta": d["callbacks_over_50_ms"] - b["callbacks_over_50_ms"],
            "process_over_50_delta": d["process_callbacks_over_50_ms"] - b["process_callbacks_over_50_ms"],
            "base_deaths": b["death_signals"], "candidate_deaths": d["death_signals"],
            "base_drop_nodes": b["drop_nodes"], "candidate_drop_nodes": d["drop_nodes"],
            "base_native_process_callbacks": b["process_callback_count"],
            "candidate_native_process_callbacks": d["process_callback_count"],
        })
    native_runs = read(root / "runs.json")
    assert len(native_runs) == 8 and len({row["label"] for row in native_runs}) == 8, name
    for run in native_runs:
        for suffix in ("stdout.log", "stderr.log", "godot.log"):
            p = root / run["label"] / "runner" / ("t6_real_load_probe." + suffix)
            data = p.read_bytes()
            raw.append({"path": p.relative_to(ROOT).as_posix(), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    rows.append({"mode": c["mode"], "scale": 30, "aa_cpu_noise_ms": c["aa_absolute_cpu_noise_ms"],
                 "sustained_cpu_above_aa_noise": c["sustained_above_aa_noise_regression"],
                 "pairs": pairs, "directory": name})
assert not required
assert len(heads) == 1, "paired branches differ across conditions"
result = {"collection_status": "PASS", "performance_acceptance": "NOT_RUN",
          "candidate_head": exact["candidate_head"], "base_head": exact["base_head"],
          "rows": rows, "raw": sorted(raw, key=lambda r: r["path"]),
          "scope": "Desktop native physics/process callback observations; genuine work counts disclosed. Human performance ruling follows."}
output = ROOT / "native_t6_conditions_receipt.json"
assert not output.exists(), "refuse to replace an earlier verdict"
output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({k: v for k, v in result.items() if k != "raw"}, ensure_ascii=False))
