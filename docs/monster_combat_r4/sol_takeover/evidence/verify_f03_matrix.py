"""Exact completed native matrix checks, separate from performance verdict."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).parent / "t6_f03_full"
read = lambda p: json.loads(p.read_text(encoding="utf-8-sig"))
identity = read(ROOT / "identity.json")
runs = read(ROOT / "runs.json")
errors = []
labels = [r["label"] for r in runs]
expected = {f"{mode}-{scale}-{phase}-{n}-{side}"
            for mode in identity["modes"] for scale in identity["scales"]
            for phase, rounds, sides in [("AA", (1,2), ("BASE",)), ("AB", (1,2,3), ("BASE","CAND"))]
            for n in rounds for side in sides}
if len(labels) != 72 or len(set(labels)) != 72 or set(labels) != expected:
    errors.append("execution_set")
for row in runs:
    label = row["label"]
    sample = read(ROOT / label / "load.json")
    runners = list((ROOT / label / "runner").glob("runner_results_*.json"))
    head = identity["base_head"] if row["side"] == "BASE" else identity["candidate_head"]
    if row["exit_code"] != 0 or sample["source_head"] != head or sample["label"] != label or sample["failures"] or len(sample["frames"]) != 600:
        errors.append(label+":sample")
    if len(runners) != 1:
        errors.append(label+":runner_count")
    else:
        runner = read(runners[0])
        results = runner["results"]
        if runner["git_head"] != head or runner["passed"] != 1 or runner["failed"] or runner["engine_log_errors"] or len(results) != 1:
            errors.append(label+":runner")
        elif not (results[0]["result"] == "PASS" and results[0]["process_exited"] and not results[0]["timeout"] and results[0]["effective_exit_code"] == 0 and results[0]["wrapper_exit_code"] == 0):
            errors.append(label+":native_exit")
    if sample["production_hot_test_mode"] is not False or sample["isolated_profile_namespace"] != ROOT.name or sample["random_input_version"] != identity["random_input_version"]:
        errors.append(label+":input_mode")
    inputs = sample["random_inputs"]
    if inputs["drop_session"] != "20260927000000000000000000000000" or inputs["player_seed"] != 20260928 or inputs["durability_seed"] != 20260929:
        errors.append(label+":seed")
    deaths = inputs["death_identity_inputs"]
    if row["mode"] == "aoe_death_loot" and (len(deaths) != sample["death_signals"] or len({d["fixed_key"] for d in deaths}) != len(deaths) or not inputs["equipment_identity_inputs"]):
        errors.append(label+":death_inputs")
    for d in deaths:
        if d["fixed_key"] != f'death:{int(d["map_id"])}:{int(d["generation"])}:{int(d["sequence"])}:{int(d["spawn_ordinal"])}':
            errors.append(label+":death_identity")
    for item in inputs["equipment_identity_inputs"]:
        digest = hashlib.sha256(f'item.drop.instance.v1|{int(item["item_id"])}|{item["stable_key"]}'.encode()).hexdigest()
        if item["digest"] != digest or item["instance_id"] != f'drop:v1:{int(item["item_id"])}:{digest[:24]}':
            errors.append(label+":affix_identity")
result = dict(status="FAIL" if errors else "PASS", candidate_head=identity["candidate_head"], base_head=identity["base_head"], actual=len(labels), unique=len(set(labels)), expected=len(expected), errors=errors, performance_acceptance="FAIL", note="Collection only. PERFORMANCE_REVIEW_9e7.md retains unresolved CPU/tail warnings; GPU/device NOT_RUN.")
(ROOT / "exact_execution_check.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(json.dumps(result,ensure_ascii=False))
raise SystemExit(bool(errors))
