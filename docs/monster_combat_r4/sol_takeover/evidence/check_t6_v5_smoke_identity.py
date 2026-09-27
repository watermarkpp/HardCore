import json,hashlib
from pathlib import Path
r=Path('docs/monster_combat_r4/sol_takeover/evidence/t6_v5_identity_smoke_fresh')
a=json.loads((r/'BASE/load.json').read_text(encoding='utf-8-sig'));b=json.loads((r/'CAND/load.json').read_text(encoding='utf-8-sig'))
fields=('item_id','item_index','sequence','stable_key','digest','instance_id','modifiers')
def aff(d):return {(row['stable_key'],int(row['item_id'])):{k:row[k] for k in fields} for row in d['random_inputs']['equipment_identity_inputs']}
x,y=aff(a),aff(b);shared=sorted(x.keys()&y.keys());bad=[k for k in shared if x[k]!=y[k]]
result={'status':'PASS' if shared and not bad and not a['failures'] and not b['failures'] else 'FAIL','note':'Actual native equipment generation for shared fixed identities; variable terminal counts recorded. Smoke does not substitute 72 paired samples.','base_deaths':a['death_signals'],'candidate_deaths':b['death_signals'],'base_equipment_inputs':len(x),'candidate_equipment_inputs':len(y),'shared_identity_count':len(shared),'different_shared_instances':bad,'same_key_different_item_ids':[k for k in sorted({z[0] for z in x}&{z[0] for z in y}) if {z[1] for z in x if z[0]==k}!={z[1] for z in y if z[0]==k}],'base_only':sorted(x.keys()-y.keys()),'candidate_only':sorted(y.keys()-x.keys()),'probe_sha256':hashlib.sha256(Path('tests/hc_monster_combat_r4/t6_real_load_probe.gd').read_bytes()).hexdigest()}
(r/'actual_identity_comparison.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))
