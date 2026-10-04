from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, subprocess, sys

root=Path.cwd()
assert root==Path('C:/Users/Administrator/.codex/worktrees/pluggable-framework-v2/HardCore')
owned=root/'outputs/framework_v2/state_loan_20261004'
baseline=json.loads((owned/'BEFORE.json').read_text(encoding='utf-8-sig'))
names=['scripts/features/runtime/effect_runtime.gd','scripts/features/compilation/child_capacity_proof.gd']
candidate={name:(root/name).read_bytes() for name in names}
for name in names:
    target=root/name
    assert target.is_relative_to(root) and not target.is_symlink()
    original=(owned/'before_bytes'/name).read_bytes()
    entry=next(row for row in baseline['files'] if row['path']==name)
    assert hashlib.sha256(original).hexdigest()==entry['sha256']
    backup=owned/'candidate_before_parent_control'/name
    backup.parent.mkdir(parents=True,exist_ok=True)
    assert not backup.exists()
    backup.write_bytes(candidate[name])
record={'parent':baseline['parent'],'scope':names,'started_utc':datetime.now(timezone.utc).isoformat(),
        'candidate_before':{name:hashlib.sha256(data).hexdigest() for name,data in candidate.items()},
        'description':'Exact two-file parent control; not a full parent checkout. New test fixture is unchanged.'}
try:
    for name in names:(root/name).write_bytes((owned/'before_bytes'/name).read_bytes())
    record['control_before']={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in names}
    result=subprocess.run(['py','-3.12','-X','utf8',str(owned/'run_owned.py'),
        'state_loan_root_parent_red','tests/framework/feature_state_loan_root_test.tscn'],
        cwd=root,capture_output=True,text=True,encoding='utf-8')
    (owned/'state_loan_root_parent_control_outer.log').write_text(result.stdout+result.stderr,encoding='utf-8')
    record['native_wrapper_exit']=result.returncode
    record['control_after']={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in names}
    print(result.stdout,flush=True)
    print(result.stderr,flush=True)
finally:
    for name,data in candidate.items():(root/name).write_bytes(data)
    record['candidate_restored']={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in names}
    record['finished_utc']=datetime.now(timezone.utc).isoformat()
    record['restored_exact']=record['candidate_restored']==record['candidate_before']
    (owned/'ROOT_PARENT_CONTROL.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
assert record['restored_exact'] and record['control_before']==record['control_after']
assert record['native_wrapper_exit']==1,record
print(json.dumps({'expected_red':True,'candidate_restored':True}),flush=True)
