from pathlib import Path
import hashlib, json, os, subprocess
ROOT = Path.cwd()
assert ROOT == Path(r'C:/Users/Administrator/.codex/worktrees/pluggable-framework-v2/HardCore')
OWNED = ROOT / 'outputs/framework_v2/chain_state_pool_20261004'
PARENT = '2b4ab20a142fe09117b9b996c2d85bc1d6d742f9'
env = os.environ.copy(); env['GIT_OPTIONAL_LOCKS'] = '0'
def git(*args, input=None, alternate=False):
    task_env = env.copy()
    if alternate: task_env['GIT_INDEX_FILE'] = str(OWNED / 'review.index')
    else: task_env.pop('GIT_INDEX_FILE', None)
    return subprocess.check_output(['git', *args], cwd=ROOT, env=task_env, input=input)
prior = json.loads(git('show', PARENT+':docs/review/framework_child_chain_admission_20261004/SOURCE_MANIFEST.json'))
files = {}
for folder in ('scripts', 'tests', 'scenes', 'assets/data', 'shaders'):
    for path in (ROOT/folder).rglob('*'):
        if path.is_file() and path.suffix.lower() in {'.gd','.tscn','.tres','.json','.gdshader'}:
            files[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
for name in ('project.godot','tools/run_godot_tests.ps1','tools/source176_r3_validation.py','tools/test_framework_receipt.ps1'):
    files[name] = hashlib.sha256((ROOT/name).read_bytes()).hexdigest()
assert not set(prior['files']) - set(files), 'unexpected source removal'
delta = [path for path in sorted(files) if files[path] != prior['files'].get(path)]
git('read-tree', PARENT, alternate=True)
for path in delta:
    blob = git('hash-object','-w','--path='+path,'--stdin',input=(ROOT/path).read_bytes()).decode().strip()
    git('update-index','--add','--cacheinfo','100644,'+blob+','+path,alternate=True)
(OWNED/'source_delta_paths.json').write_text(json.dumps(delta,indent=2)+'\n',encoding='utf-8')
for label,args in [('source_review.diff',('diff','--cached',PARENT)),('source_review.stat',('diff','--cached','--stat',PARENT))]:
    (OWNED/label).write_bytes(git(*args,alternate=True))
check = subprocess.run(['git','diff','--cached','--check',PARENT],cwd=ROOT,
    env={**env,'GIT_INDEX_FILE':str(OWNED/'review.index')},capture_output=True)
(OWNED/'source_review_check.log').write_bytes(check.stdout+check.stderr)
print(json.dumps({'parent':PARENT,'source_delta_count':len(delta),'paths':delta,'diff_check_exit':check.returncode}))
raise SystemExit(check.returncode)
