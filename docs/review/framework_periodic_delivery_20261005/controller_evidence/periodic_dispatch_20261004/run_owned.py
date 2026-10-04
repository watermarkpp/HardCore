from pathlib import Path
import os, sys, subprocess, uuid, json, datetime, hashlib, shutil

root=Path.cwd(); assert root==Path('C:/Users/Administrator/.codex/worktrees/pluggable-framework-v2/HardCore')
owned=root/'outputs/framework_v2/periodic_dispatch_20261004'
label=sys.argv[1]; paths=sys.argv[2:]; timeout=30
if paths and paths[0].startswith('--timeout='):
    timeout=int(paths.pop(0).split('=',1)[1])
assert timeout in [30,60] and label.startswith('periodic_dispatch_') and paths
git_root=Path(r'C:/Users/Administrator/Documents/HardCore/.git/worktrees/HardCore/index')
before=hashlib.sha256(git_root.read_bytes()).hexdigest()
assert before=='df5a01dd0d87c14620e0021d70c25a830eb2cc37aa7b012eeb14ee1f2c58c5fb'
env=os.environ.copy(); env['GIT_INDEX_FILE']=str(root/'outputs/framework_v2/publication_closure_20261003/runner.index')
subprocess.run(['git','add','--','tests/framework/periodic_producer_identity_test.gd','tests/framework/periodic_producer_identity_test.tscn','tests/framework/periodic_refresh_horizon_test.gd','tests/framework/periodic_refresh_horizon_test.tscn','tests/framework/periodic_child_root_test.gd','tests/framework/periodic_child_root_test.tscn','tests/framework/periodic_child_g2_root_test.tscn','tests/framework/periodic_dispatch_lifecycle_test.gd','tests/framework/periodic_dispatch_lifecycle_test.tscn'],cwd=root,env=env,check=True)
selected=[]
for scene in paths:
    candidate=(root/scene).resolve()
    assert candidate.is_relative_to(root/'tests') and candidate.suffix=='.tscn' and candidate.exists()
    selected.append(scene)
    script=candidate.with_suffix('.gd')
    if script.exists(): selected.append(str(script.relative_to(root)))
subprocess.run(['git','add','--',*selected],cwd=root,env=env,check=True)
account=root/'.godot/runtime_appdata'/(label+'_'+uuid.uuid4().hex); account.mkdir(parents=True)
env['HARDCORE_AUDIT_RUNTIME_APPDATA']=str(account)
command=['py','-3.12','tools/source176_r3_validation.py',label,'--tests',*paths,'--timeout',str(timeout)]
(owned/(label+'_launch.json')).write_bytes((json.dumps({'time_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'launcher_pid':os.getpid(),'runtime_appdata':str(account),'command':command,'timeout_seconds':timeout,'true_index_sha256':before},indent=2)+'\n').encode())
p=subprocess.run(command,cwd=root,env=env,capture_output=True,text=True,encoding='utf-8')
(owned/(label+'_launcher.log')).write_bytes((p.stdout+p.stderr).encode('utf-8'))
for line in p.stdout.splitlines():
    if not line.startswith('{'): continue
    try: terminal=json.loads(line)
    except json.JSONDecodeError: continue
    if 'evidence' not in terminal: continue
    destination=Path(terminal['evidence'])/'native_logs'; destination.mkdir()
    assert destination.resolve().is_relative_to(root/'outputs/r3_takeover/20260930/validation')
    for scene in paths:
        for suffix in ['stdout.log','stderr.log','godot.log']:
            raw=root/'outputs/test_logs'/(Path(scene).stem+'.'+suffix)
            if raw.exists(): shutil.copyfile(raw,destination/raw.name)
assert hashlib.sha256(git_root.read_bytes()).hexdigest()==before
print(p.stdout); print(p.stderr); sys.exit(p.returncode)
