from pathlib import Path
import hashlib,importlib.util,json,subprocess
R=Path(r'C:/Users/Administrator/.codex/worktrees/multicore-v115/HardCore');O=R/'outputs/v115_multicore/codex_resume_20261015_182255';D=O/'release_source_binding_repair_test_20261017';D.mkdir(exist_ok=False)
def load(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
safe=load('isolated_git',R/'outputs/v115_multicore/source_save_runtime_180_20261017/isolated_git.py');repo=D/'project';box=safe.GitSandbox(repo,D);box.initialize();env=box.environment();env.update(GIT_AUTHOR_NAME='HardCore fixture',GIT_AUTHOR_EMAIL='fixture@example.invalid',GIT_COMMITTER_NAME='HardCore fixture',GIT_COMMITTER_EMAIL='fixture@example.invalid',GIT_AUTHOR_DATE='2000-01-01T00:00:00+00:00',GIT_COMMITTER_DATE='2000-01-01T00:00:00+00:00');commands=[]
def git(*args,stdin=None):
 box.verify();commands.append(list(args));p=subprocess.run(['git',*args],cwd=repo,env=env,input=stdin,stdout=subprocess.PIPE,stderr=subprocess.PIPE);assert p.returncode==0,p.stderr.decode();return p.stdout.decode().strip()
def commit(values):
 git('read-tree','--empty')
 for n,v in sorted(values.items()):git('update-index','--add','--cacheinfo','100644',git('hash-object','-w','--stdin',stdin=v),n)
 return git('commit-tree',git('write-tree'),stdin=b'Immutable release binding unit fixture\n')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def fact(p):return {'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size}
def save(n,v):p=D/n;p.write_text(json.dumps(v,indent=2)+'\n',encoding='utf-8');return p
files={'scripts/live.gd':b'extends Node\n','assets/data/data.json':b'{}\n','native/hardcore_simulation/SCsub':b'# actual unit fixture\n','project.godot':b'[physics]\n2d/external_owner_mode=true\n','scenes/world.tscn':b'[gd_scene format=3]\n[node name="World" type="Node2D"]\n'}
commits={'matching_source':commit(files),'changed_project':commit(dict(files,**{'project.godot':b'[physics]\n2d/external_owner_mode=false\n'})),'changed_world_scene':commit(dict(files,**{'scenes/world.tscn':b'[gd_scene format=3]\n[node name="WrongWorld" type="Node"]\n'}))};save('COMMIT_COMPONENT_INPUTS.json',commits)
source=save('SOURCE_COMPONENT_MANIFEST.json',[{'path':n,'sha256':hashlib.sha256(v).hexdigest()} for n,v in files.items() if not n.startswith('native/')]);native=save('NATIVE_COMPONENT_MANIFEST.json',{'module_inputs':[{'root':'project','relative_path':'native/hardcore_simulation/SCsub','sha256':hashlib.sha256(files['native/hardcore_simulation/SCsub']).hexdigest()}]});templates={'manifest':fact(native)};results=[]
for label,path in [('original',R/'outputs/v115_multicore/android_delivery_parallel_20261017/delivery.py'),('archive_only',O/'delivery_archive_only_20261017.py'),('candidate',O/'delivery_current_source_binding_20261017.py')]:
 m=load('delivery_'+label,path);m.ROOT=repo;records=[]
 for case,rev in commits.items():
  accepted=True;reason=''
  try:m.verify_release_sources({'fixed_release_commit':rev,'world_gate':{'source_manifest':fact(source)}},templates)
  except RuntimeError as e:accepted=False;reason=str(e)
  records.append({'case':case,'passed':accepted==(case=='matching_source'),'accepted':accepted,'reason':reason})
 failed=sum(not a['passed'] for a in records);result={'status':'FAIL' if failed else 'PASS','scope':'Actual isolated immutable Git archive only; explicit unit manifests are not World/Native/APK evidence','checks':len(records),'failed':failed,'helper_sha256':sha(path),'records':records};save(label+'_RESULT.json',result);results.append(result);print(label,'failed',failed)
assert results[1]['failed']==2 and results[2]['failed']==0
minimal={n:v for n,v in files.items() if n.startswith(('scripts/','assets/','native/'))};revision=commit(minimal);src=save('MINIMAL_SOURCE_COMPONENT_MANIFEST.json',[{'path':n,'sha256':hashlib.sha256(v).hexdigest()} for n,v in minimal.items() if not n.startswith('native/')]);result=m.verify_release_sources({'fixed_release_commit':revision,'world_gate':{'source_manifest':fact(src)}},templates);assert result['exact_source_files']==3
index=Path(r'C:/Users/Administrator/Documents/HardCore/.git/worktrees/HardCore1/index');assert sha(index)=='3180f91855b8bc8d7a22848592ff9f95f2d19574a73f7a3eea90e962f7151b22'
save('FINAL_RESULT.json',{'status':'PASS','scope':'Release source binding component; no World/export/APK acceptance','archive_only_red':'3checks2FAIL','candidate':'3checks0FAIL','legacy_minimal_regression':'PASS','index_sha256':sha(index),'commands':commands});print('RELEASE_SOURCE_BINDING_PASS 3/0 + minimal fixture')