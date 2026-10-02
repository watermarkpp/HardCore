from pathlib import Path
import json, statistics
ROOT=Path(__file__).resolve().parents[3]
V=ROOT/'outputs/r3_takeover/20260930/validation';OUT=Path(__file__).resolve().parent
patterns={'A1':'r3_bucket_A1_native_*','B1':'r3_bucket_B1_*','B2':'r3_bucket_B2_*','A2':'r3_bucket_A2_*'}
runs={k:sorted(V.glob(p))[-1] for k,p in patterns.items()}
manifests={};cases={}
for label,p in runs.items():
 validation=json.loads((p/'validation.json').read_text());assert validation['status']=='PASS'
 before=json.loads((p/'before.json').read_text());after=json.loads((p/'after.json').read_text());assert before['files']==after['files']
 manifests[label]=before
 for count in [10,20,30]:
  d=json.loads((p/f'traces/native_performance_{count}.json').read_text());assert not d['errors']
  for row in d['rows']:
   assert row['samples']==180
   for field,sample in [('cpu','cpu_samples_us'),('frame_interval','frame_intervals_us')]:
    ordered=sorted(row[sample]);assert len(ordered)==180
    for q,n in [(.95,'p95'),(.99,'p99')]:assert row[field+'_'+n+'_ms']==ordered[int(179*q)]/1000
   cases.setdefault((count,row['temperature'],row['motion']),{})[label]=row
assert manifests['A1']['files']==manifests['A2']['files']
assert manifests['B1']['files']==manifests['B2']['files']
changes=[n for n,h in manifests['A1']['files'].items() if manifests['B1']['files'][n]!=h]
assert set(changes)=={'scripts/enemy.gd','scripts/runtime_combat_spatial_index.gd'},changes
assert len({m['engine_sha256'] for m in manifests.values()})==1
rows=[];regressions=[]
for key,raw in sorted(cases.items()):
 row=dict(zip(['count','temperature','motion'],key))
 for field in ['cpu_p50_ms','cpu_p95_ms','cpu_p99_ms','frame_interval_p95_ms','frame_interval_p99_ms']:
  a=[raw[n][field] for n in ['A1','A2']];b=[raw[n][field] for n in ['B1','B2']]
  row[field]={'baseline':a,'candidate':b,'median_delta':statistics.median(b)-statistics.median(a),'candidate_above_both_baselines':min(b)>max(a)}
 row['behavior']={n:{k:r[k] for k in ['motion_gu','starts','hp_delta']} for n,r in raw.items()}
 row['counters']={n:r['counters'] for n,r in raw.items()}
 if any(row[f]['candidate_above_both_baselines'] for f in ['cpu_p95_ms','cpu_p99_ms']):regressions.append(key)
 rows.append(row)
report={'status':'FAIL' if regressions else 'PASS','method':'ABBA same 18 cases, two repeats; descriptive ranges, not confidence intervals; original percentile algorithm independently recomputed','runs':{n:str(p.relative_to(ROOT)) for n,p in runs.items()},'source':{n:m['content_set_sha256'] for n,m in manifests.items()},'changed_production':changes,'cases':rows,'investigate_cpu_regressions':regressions,'historical_v4':'not relabelled by this comparison','device_test':'NOT_RUN'}
(OUT/'ABBA_COMPARISON.json').write_text(json.dumps(report,indent=2))
print(json.dumps({'status':report['status'],'cases':len(rows),'regressions':regressions}))
for r in rows:print(r['count'],r['temperature'],r['motion'],'p95',r['cpu_p95_ms']['baseline'],r['cpu_p95_ms']['candidate'],'p99',r['cpu_p99_ms']['baseline'],r['cpu_p99_ms']['candidate'])
