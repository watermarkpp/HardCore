"""Read exact native follow-up; preserve unfavorable rows, no automatic verdict."""
import json
from pathlib import Path

root = Path(__file__).parent
read = lambda p: json.loads(p.read_text(encoding="utf-8-sig"))
reports = []
for name in ("final_owner_full_small30_absolute", "final_owner_full_pets20", "final_owner_full_aoe30"):
    matrix = root / name
    assert read(matrix / "exact_execution_check.json")["status"] == "PASS"
    summary = read(matrix / "summary.json")
    condition = summary["conditions"][0]
    prefix = f'{condition["mode"]}-{condition["scale"]}'
    rows = []
    for n, (a, b) in enumerate(zip(condition["baseline_results"], condition["candidate_results"]), 1):
        raw = [read(matrix / f"{prefix}-AB-{n}-{side}" / "load.json") for side in ("BASE", "CAND")]
        fields = ("enemy_physics_calls", "enemy_physics_usec", "enemy_movement_strategy_calls",
                  "enemy_movement_strategy_usec", "environment_guard_batches", "attack_los_evaluations",
                  "attack_los_usec", "death_settlement_usec", "drop_roll_usec", "drop_placement_usec")
        rows.append(dict(pair=n, p99=[v["callback_interval_p99_ms"] for v in (a,b)],
                         over33=[v["callbacks_over_33_33_ms"] for v in (a,b)],
                         over50=[v["callbacks_over_50_ms"] for v in (a,b)],
                         phases={k:[v["counter_deltas"].get(k,0) for v in raw] for k in fields},
                         starts=[v["starts"] for v in (a,b)], hp=[v["hp_delta"] for v in (a,b)],
                         deaths=[v["death_signals"] for v in (a,b)],
                         native_plans=[len(v["native_planned_death_keys"]) for v in raw],
                         created_nodes=[v["native_loot_nodes_created"] for v in raw]))
    reports.append(dict(matrix=name, condition={k:v for k,v in condition.items()
                    if k not in ("baseline_results","candidate_results")}, pairs=rows))
    print(prefix, reports[-1]["condition"])
    for row in rows:
        print(" pair", row["pair"], "P99",row["p99"],">33",row["over33"],">50",row["over50"],
              "calls",row["phases"]["enemy_physics_calls"],"starts",row["starts"],"deaths",row["deaths"])
(root / "final_owner_full_review.json").write_text(json.dumps(reports,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
