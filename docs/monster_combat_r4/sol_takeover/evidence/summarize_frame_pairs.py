"""Frame-only native pacing, without inventing unmeasured enemy CPU."""
import json, statistics, sys
from pathlib import Path

def read(p): return json.loads(p.read_text(encoding="utf-8-sig"))
def percentile(values, q):
    values=sorted(values); pos=(len(values)-1)*q; lo=int(pos); hi=min(lo+1,len(values)-1)
    return values[lo]+(values[hi]-values[lo])*(pos-lo)

def sample(root, label):
    x=read(root/label/"load.json"); intervals=[f["physics_callback_interval_ms"] for f in x["frames"]]
    assert x["observation_detail_mode"]=="frame_only" and x["enemy_cpu_attribution"]=="NOT_RUN"
    assert all(f["enemy_inclusive_cpu_ms"] is None for f in x["frames"])
    return dict(label=label, head=x["source_head"], interval_mean_ms=statistics.mean(intervals),
      interval_p95_ms=percentile(intervals,.95), interval_p99_ms=percentile(intervals,.99),
      callbacks_over_33_33_ms=sum(v>33.33 for v in intervals), callbacks_over_50_ms=sum(v>50 for v in intervals),
      starts=x["starts_surviving_actors"], hp_loss=x["player_hp_delta"], pet_damage=x["pet_actual_damage"],
      live_min=min(f["live_count"] for f in x["frames"]),live_max=max(f["live_count"] for f in x["frames"]),
      engine_physics_monitor_mean_ms=statistics.mean(f["engine_physics_monitor_ms"] for f in x["frames"]),
      scheduler=x["scheduler_identity_inputs"], enemy_cpu_attribution="NOT_RUN")

root=Path(sys.argv[1]); identity=read(root/"identity.json"); execution=read(root/"exact_execution_check.json")
assert execution["status"]=="PASS" and identity["observation_detail_mode"]=="frame_only"
rows=[]
for mode in identity["modes"]:
 for scale in identity["scales"]:
    prefix=f"{mode}-{scale}"; aa=[sample(root,f"{prefix}-AA-{i}-BASE") for i in (1,2)]
    pairs=[dict(base=sample(root,f"{prefix}-AB-{i}-BASE"),candidate=sample(root,f"{prefix}-AB-{i}-CAND")) for i in (1,2,3)]
    row=dict(mode=mode,scale=scale,aa=aa,pairs=pairs,
      aa_mean_interval_difference_ms=abs(aa[0]["interval_mean_ms"]-aa[1]["interval_mean_ms"]),
      mean_interval_deltas_ms=[p["candidate"]["interval_mean_ms"]-p["base"]["interval_mean_ms"] for p in pairs])
    rows.append(row)
    print(prefix, 'AA',row['aa_mean_interval_difference_ms'],'deltas',row['mean_interval_deltas_ms'])
    for p in pairs: print({k:[p["base"][k],p["candidate"][k]] for k in ['interval_p99_ms','callbacks_over_33_33_ms','callbacks_over_50_ms','engine_physics_monitor_mean_ms','starts','hp_loss','pet_damage']})
(root/"frame_summary.json").write_text(json.dumps(dict(status="PASS",conditions=rows, scope="Collection only; per-actor CPU attribution, GPU and device NOT_RUN. Engine window monitors have means only, never frame percentiles. Original full-observation warnings remain separately retained."),ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
