"""Native monotonic event intersection, no roll/frame-window source guessing."""
import json
from pathlib import Path

root = Path(__file__).parent / "overhead_constructor_trace"
read = lambda p: json.loads(p.read_text(encoding="utf-8-sig"))
identity = read(root / "identity.json")
rows = []
for side in ("BASE", "CAND"):
    data = read(root / side / "load.json")
    runner_paths = list((root / side / "runner").glob("runner_results_*.json"))
    assert len(runner_paths) == 1
    runner = read(runner_paths[0])
    head = identity["base_head"] if side == "BASE" else identity["candidate_head"]
    assert data["source_head"] == runner["git_head"] == head
    assert data["fixture_spawn_trace_enabled"] and not data["failures"] and len(data["frames"]) == 600
    assert data["enemy_cpu_attribution"] == "NOT_RUN" and runner["failed"] == runner["engine_log_errors"] == 0
    native = runner["results"][0]
    assert native["process_exited"] and not native["timeout"] and native["effective_exit_code"] == native["wrapper_exit_code"] == 0
    intervals = []
    for frame in data["frames"]:
        start, end = frame["sample_start_usec"], frame["sample_end_usec"]
        events = [e for e in data["fixture_spawn_events"] if e["start_usec"] < end and e["end_usec"] > start]
        spawn_us = sum(max(0, min(end,e["end_usec"])-max(start,e["start_usec"])) for e in events)
        if len(events) >= 10 or frame["physics_callback_interval_ms"] > 50:
            intervals.append(dict(tick=frame["tick"], interval_ms=frame["physics_callback_interval_ms"],
                                  spawns=len(events), actual_factory_region_ms=spawn_us/1000))
    rows.append(dict(side=side, source_head=head, status="PASS", intervals=intervals,
                     over50=sum(f["physics_callback_interval_ms"]>50 for f in data["frames"]),
                     deaths=data["death_signals"], plans=len(data["native_planned_death_keys"]),
                     created_nodes=data["native_loot_nodes_created"],
                     scope="Fixture sustained30 replacements; actual inherited factory plus deterministic audit tail. Elapsed wall time, not isolated OS CPU. Native production due-respawn scheduling is not exercised by this probe."))
    print(side, "over50",rows[-1]["over50"],"deaths",rows[-1]["deaths"],"bursts", intervals)
(root / "actual_factory_trace_review.json").write_text(json.dumps(rows,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
