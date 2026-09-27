"""Read existing native samples; do not infer causality from timing correlation."""
import hashlib
import json
import subprocess
from pathlib import Path

root = Path(__file__).parent
base = "1381d2838a3736f4a06699dd24a8cf4a10714950"
cand = "e367150b0c46c040e67b4ebd1b750ccd1ff5a536"
repo = next(p for p in root.parents if (p / ".git").exists())


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def source(rev, path):
    return subprocess.check_output(["git", "show", f"{rev}:{path}"], cwd=repo).decode().replace("\r\n", "\n")


def function(text, name):
    start = text.index(f"func {name}(")
    following = text.find("\nfunc ", start + 1)
    return text[start:following if following >= 0 else len(text)].rstrip()


functions = []
for name in ("_advance_autonomous_step_internal", "_move_with_spatial_rules", "_spatial_index_update"):
    a, b = (function(source(rev, "scripts/enemy.gd"), name) for rev in (base, cand))
    functions.append(dict(name=name, normalized_identical=a == b,
                          base_sha256=hashlib.sha256(a.encode()).hexdigest(),
                          candidate_sha256=hashlib.sha256(b.encode()).hexdigest()))
phases = ("enemy_physics_usec", "enemy_movement_strategy_usec", "move_and_slide_usec",
          "environment_query_usec", "crowd_usec", "death_settlement_usec")
matrices = []
for directory in ("r4_owner_final_e367/aoe_death_loot_30", "quiet_full_aoe_e367_20260928_0410"):
    folder = root / directory
    execution = read(folder / "exact_execution_check.json")
    assert execution["status"] == "PASS" and execution["actual"] == 8
    pairs = []
    for i in range(1, 4):
        samples = [read(folder / f"aoe_death_loot-30-AB-{i}-{side}" / "load.json") for side in ("BASE", "CAND")]
        a, b = samples
        assert a["source_head"] == base and b["source_head"] == cand
        facts = []
        for d in samples:
            c = d["counter_deltas"]
            facts.append(dict(source_head=d["source_head"], physics_calls=c["enemy_physics_calls"],
                              movement_strategy_calls=c["enemy_movement_strategy_calls"],
                              physics_tick_span=d["frames"][-1]["tick"]-d["frames"][0]["tick"]+1,
                              death_signals=d["death_signals"], moving_survivors=d["moving_surviving_actors"],
                              inclusive_usec_per_actor_call=c["enemy_physics_usec"]/c["enemy_physics_calls"],
                              movement_usec_per_strategy_call=c["enemy_movement_strategy_usec"]/c["enemy_movement_strategy_calls"],
                              phase_totals_usec={k: c.get(k, 0) for k in phases}))
        pairs.append(dict(pair=i, base=facts[0], candidate=facts[1],
                          phase_deltas_ms_per_callback={k: (b["counter_deltas"].get(k, 0)-a["counter_deltas"].get(k, 0))/600000 for k in phases}))
    matrices.append(dict(path=directory, summary=read(folder/"summary.json")["conditions"][0], pairs=pairs))
result = dict(source_base=base, source_candidate=cand, collection_status="PASS", performance_acceptance="FAIL",
              unchanged_movement_functions=functions,
              diagnostic_source_identical=source(base, "scripts/runtime_diagnostics.gd") == source(cand, "scripts/runtime_diagnostics.gd"),
              matrices=matrices,
              limitations=["Inclusive phases overlap and are not additive.",
                           "Different native clock spans, movement, death and allocation-dependent schedules are retained.",
                           "Move-and-slide segment includes spatial-index update; no isolated engine collision cost is claimed.",
                           "Unchanged function text and timing correlation do not prove a sole cause.",
                           "No further same-source repeats are used to turn warnings green; CPU acceptance remains open.",
                           "GPU and device are NOT_RUN."])
out = root / "r4_owner_final_e367" / "phase_cost_review.json"
out.write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
print(json.dumps({k:v for k,v in result.items() if k != "matrices"}, ensure_ascii=False))
