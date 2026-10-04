from pathlib import Path
import hashlib, json, subprocess, datetime

root=Path.cwd()
assert root==Path('C:/Users/Administrator/.codex/worktrees/pluggable-framework-v2/HardCore')
owned=root/'outputs/framework_v2/chain_state_pool_20261004'
target=root/'scripts/game_root.gd'
current=target.read_bytes()
old=(owned/'before_bytes/scripts/game_root.gd').read_bytes()
assert b'occupied_base_spawn_slot' in current and b'occupied_base_spawn_slot' not in old
backup=owned/'birth_body_green_root.gd'
assert not backup.exists()
backup.write_bytes(current)
record={'time_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'scope':'Only owned GameRoot source reverted temporarily to exact recorded 2b4 baseline for one isolated policy scene. This is not a full parent checkout/run.',
        'before_sha256':hashlib.sha256(current).hexdigest(),'control_sha256':hashlib.sha256(old).hexdigest()}
try:
    target.write_bytes(old)
    result=subprocess.run(['py','-3.12',str(owned/'run_owned.py'),'chain_state_pool_respawn_parent_control',
                           'tests/monster_formal_respawn_policy_audit_test.tscn'],cwd=root,
                          capture_output=True,text=True,encoding='utf-8')
    (owned/'respawn_parent_control_outer.log').write_text(result.stdout+result.stderr)
    record['launcher_exit']=result.returncode
    record['runner_summary']=json.loads(result.stdout.strip().splitlines()[-1])
    assert result.returncode==1 and record['runner_summary']['status']=='FAIL'
finally:
    assert target.read_bytes()==old,'Unexpected source edit while the controlled test ran'
    target.write_bytes(current)
    record['restored_exact_current_bytes']=target.read_bytes()==current
    (owned/'RESPAWN_PARENT_CONTROL.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record))
