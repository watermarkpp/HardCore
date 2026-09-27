"""Read raw fixed pairs; report workload and inclusive phase timing, no verdict."""
import json
from pathlib import Path

ROOT = Path(__file__).parent / "t6_f03_full"
read = lambda p: json.loads(p.read_text(encoding="utf-8-sig"))
summary = read(ROOT / "summary.json")
fields = ["enemy_physics_calls", "enemy_physics_usec", "foreground_ai_ticks",
          "enemy_retarget_calls", "enemy_retarget_usec", "enemy_projection_calls",
          "enemy_projection_usec", "safe_zone_queries", "safe_zone_usec",
          "attack_los_evaluations", "attack_los_usec", "crowd_queries",
          "crowd_candidates", "crowd_usec", "enemy_movement_usec",
          "death_settlement_usec", "drop_roll_usec", "drop_placement_usec"]
report = []
for condition in summary["conditions"]:
    prefix = f'{condition["mode"]}-{condition["scale"]}'
    rows = []
    for n in (1, 2, 3):
        a, b = [read(ROOT / f"{prefix}-AB-{n}-{side}" / "load.json") for side in ("BASE", "CAND")]
        phase = {k: [a["counter_deltas"].get(k, 0), b["counter_deltas"].get(k, 0)] for k in fields}
        rows.append(dict(pair=n, phases=phase,
                         starts=[a["starts_surviving_actors"], b["starts_surviving_actors"]],
                         hp=[a["player_hp_delta"], b["player_hp_delta"]],
                         deaths=[a["death_signals"], b["death_signals"]],
                         enemy_cpu_per_call_us=[x["counter_deltas"]["enemy_physics_usec"] / x["counter_deltas"]["enemy_physics_calls"] for x in (a,b)],
                         queue=[x["death_queue_at_end"] for x in (a,b)],
                         scheduler=[x["scheduler_identity_inputs"] for x in (a,b)]))
    report.append(dict(mode=condition["mode"], scale=condition["scale"], pairs=rows))
    print(prefix, "mean flag", condition["sustained_above_aa_noise_regression"])
    for i, (a,b) in enumerate(zip(condition["baseline_results"],condition["candidate_results"])):
        print(" ",i+1,"CPU/call us",[round(v,3) for v in rows[i]["enemy_cpu_per_call_us"]],
              "calls",rows[i]["phases"]["enemy_physics_calls"],"starts", rows[i]["starts"],
              "P99",[round(x["callback_interval_p99_ms"],2) for x in (a,b)],
              ">33",[x["callbacks_over_33_33_ms"] for x in (a,b)],
              ">50",[x["callbacks_over_50_ms"] for x in (a,b)])
(ROOT / "controller_phase_trace.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
