from pathlib import Path
import os,sys,subprocess,uuid,json,datetime
root=Path.cwd(); assert root==Path('C:/Users/Administrator/.codex/worktrees/pluggable-framework-v2/HardCore')
owned=root/'outputs/framework_v2/child_chain_admission_20261004'
label=sys.argv[1]; paths=sys.argv[2:]; assert label.startswith('child_chain_admission_') and paths
env=os.environ.copy();env['GIT_INDEX_FILE']=str(root/'outputs/framework_v2/publication_closure_20261003/runner.index')
subprocess.run(['git','add','--','tests/framework/feature_child_chain_admission_test.gd','tests/framework/feature_child_chain_admission_test.tscn'],cwd=root,env=env,check=True)
account=root/'.godot/runtime_appdata'/(label+'_'+uuid.uuid4().hex);account.mkdir(parents=True)
env['HARDCORE_AUDIT_RUNTIME_APPDATA']=str(account)
command=['py','-3.12','tools/source176_r3_validation.py',label,'--tests',*paths,'--timeout','30']
(owned/(label+'_launch.json')).write_text(json.dumps({'time_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'launcher_pid':os.getpid(),'runtime_appdata':str(account),'command':command},indent=2)+'\n')
p=subprocess.run(command,cwd=root,env=env,capture_output=True,text=True,encoding='utf-8')
(owned/(label+'_launcher.log')).write_text(p.stdout+p.stderr,encoding='utf-8')
print(p.stdout);print(p.stderr);sys.exit(p.returncode)
