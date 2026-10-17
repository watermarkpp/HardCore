"""Prepare tools only. Does not create the test snapshot or run any stage."""
from pathlib import Path
import shutil,json,hashlib,ast
new=Path(__file__).resolve().parent; r=new.parents[2]
old=r/'outputs/v115_multicore/source_save_runtime_180_20261017'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
names=['prepare_snapshot.py','run_stage.py','runner_bridge.ps1','isolated_git.py','SOURCE_SAVE_FIXTURE_BINDING.json','STAGE_BUDGET_GATE.json']
for name in names:
 assert not (new/name).exists(),'never overwrite existing prepared tools'
 shutil.copy2(old/name,new/name)
shutil.copy2(old/'CANDIDATE_BINDING.json',new/'UPSTREAM_REVIEWED_BINDING.json')
shutil.copy2(old/'TIMEOUT_SCOPE_GUARD_RESULT.json',new/'UPSTREAM_TIMEOUT_SCOPE_GUARD_RESULT.json')
before={n:sha(old/n) for n in names}
changes={
 '4035170f8e8396d3cc25075a8a2c1860d024006ae314567cb38f0b61d3168558':'58a1b306f62b5d805bd2ff282ab37367cc807e7dd2672c0fb265c2e2289de5f8',
 '2b732cc61aed686562eb704555586d7cbb9261d704c8fee5185260444e638715':'0f3b37d1f43279e9b4633870768e64f610581a354afba777c9b404b7ac496178',
 'SOURCE_MANIFEST.published_admission_20261017.json':'SOURCE_MANIFEST.map_reply_observation_20261017.json',
 'fixed4035':'fixed58a1',
}
files=[]
for name in ['prepare_snapshot.py','run_stage.py']:
 p=new/name;t=p.read_text(encoding='utf-8')
 for a,b in changes.items():t=t.replace(a,b)
 if name=='run_stage.py':
  t=t.replace('CONSOLE="263944936f6a21530f2ea3c507e456885c20d8b5dd9ad9a711ac2b6704608229"','CONSOLE="" # BLOCKED until actual new Windows console receipt')
  t=t.replace('MAIN="9f50e92f89ef21131db2dbd09c9e7c7cf6630bd433d275f5f073e2b37bf26da1"','MAIN="" # BLOCKED until actual new Windows executing PE receipt')
 p.write_text(t,encoding='utf-8',newline='\n');ast.parse(t)
 files.append({'path':name,'historical_source_sha256':before[name],'pending_sha256':sha(p),'python_ast':'PASS'})
man=r/'outputs/v115_multicore/codex_resume_20261015_182255/SOURCE_MANIFEST.map_reply_observation_20261017.json'
assert sha(man)=='0f3b37d1f43279e9b4633870768e64f610581a354afba777c9b404b7ac496178'
d=json.loads(man.read_text(encoding='utf-8-sig'))
assert d['source_sha256']=='58a1b306f62b5d805bd2ff282ab37367cc807e7dd2672c0fb265c2e2289de5f8'
fixture=json.loads((new/'SOURCE_SAVE_FIXTURE_BINDING.json').read_text(encoding='utf-8'))
assert all(sha(r/x['path'])==x['sha256'] for x in fixture['files'])
result={'status':'BLOCKED','scope':'new Native58a tool preparation only; no snapshot or positive stage','native_manifest':str(man),'native_manifest_sha256':sha(man),'native_source_sha256':d['source_sha256'],'console_sha256':None,'main_sha256':None,'pending_tool_files':files,'unchanged_guard_files':[{'path':n,'sha256':sha(new/n),'matches_historical':sha(new/n)==before[n]} for n in ['runner_bridge.ps1','isolated_git.py','SOURCE_SAVE_FIXTURE_BINDING.json','STAGE_BUDGET_GATE.json']],'fixture_files_verified':len(fixture['files']),'upstream_reviewed_binding_sha256':sha(new/'UPSTREAM_REVIEWED_BINDING.json'),'final_CANDIDATE_BINDING_created':False,'snapshots_created':0,'positive_stages_started':0,'gate':'actual new Windows PE pair + final four-tool binding + actual matching World normal-exit PASS evidence'}
(new/'PENDING_BINDING.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'native_source_sha256':d['source_sha256'],'fixture_files_verified':len(fixture['files']),'PE':'PENDING','positive':'NOT_RUN','snapshot_created':False}))
