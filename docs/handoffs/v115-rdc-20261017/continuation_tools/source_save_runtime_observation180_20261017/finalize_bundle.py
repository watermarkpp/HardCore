from pathlib import Path
import json,hashlib,ast
O=Path(__file__).resolve().parent;R=O.parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def write(p,d):p.write_text(json.dumps(d,indent=2)+'\n',encoding='utf-8')
assert not (O/'CANDIDATE_BINDING.json').exists(),'new actual binding may only be finalized once'
native=R/'outputs/v115_multicore/codex_resume_20261015_182255/SOURCE_MANIFEST.map_reply_observation_20261017.json'
build=R/'outputs/v115_multicore/codex_resume_20261015_182255/windows_map_reply_observation_20261017_build'
receipt=build/'BUILD_RECEIPT.json';actual_receipt=read(receipt)
assert actual_receipt.get('status')=='BUILD_WINDOWS_ONLY_PASS'
console=build/'Godot_v115-stable_win64_console.exe';main=build/'Godot_v115-stable_win64.exe'
console_sha='1b69c0d26f54df88301791e5f3dbd43f7e20aad30a727addfff3287ea9d11c91'
main_sha='7f54a5090cfde94a7d2fcf37c22c14ecd23e00eefcc0bf5e23d1c0326bc7b8de'
aggregate='58a1b306f62b5d805bd2ff282ab37367cc807e7dd2672c0fb265c2e2289de5f8'
assert sha(native)=='0f3b37d1f43279e9b4633870768e64f610581a354afba777c9b404b7ac496178'
assert sha(console)==console_sha and console.stat().st_size==298496
assert sha(main)==main_sha and main.stat().st_size==175887872 and aggregate.encode() in main.read_bytes()
p=O/'run_stage.py';t=p.read_text(encoding='utf-8')
assert 'CONSOLE="" # BLOCKED until actual new Windows console receipt' in t
assert 'MAIN="" # BLOCKED until actual new Windows executing PE receipt' in t
t=t.replace('CONSOLE="" # BLOCKED until actual new Windows console receipt','CONSOLE="'+console_sha+'"').replace('MAIN="" # BLOCKED until actual new Windows executing PE receipt','MAIN="'+main_sha+'"')
p.write_text(t,encoding='utf-8',newline='\n')
binding=read(O/'UPSTREAM_REVIEWED_BINDING.json')
for row in binding['files']:
 row['previous_bundle_tool_sha256']=row['candidate_sha256']
 row['candidate_sha256']=sha(O/row['path'])
binding['scope']='Exact human180 Source save/warehouse tools with new actual Native58a read-only Map reply observation engine identity; all actual World/normal-exit/stages remain pending'
binding['previous_bundle_binding_sha256']=sha(O/'UPSTREAM_REVIEWED_BINDING.json')
binding['native_revision']={'id':'source_save180_map_reply_observation_20261017','native_source_sha256':aggregate,'native_manifest':str(native),'native_manifest_sha256':sha(native),'actual_Windows_build_receipt':str(receipt),'actual_Windows_build_receipt_sha256':sha(receipt),'console':{'path':str(console),'bytes':console.stat().st_size,'sha256':console_sha},'executing_PE':{'path':str(main),'bytes':main.stat().st_size,'sha256':main_sha},'actual_PE_contains_complete_native_identity':True,'new_snapshot_created':False,'positive_stages_started':0,'actual_upstream_World_normal_exit':'NOT_RUN'}
write(O/'CANDIDATE_BINDING.json',binding)
checks=[]
for name in ['prepare_snapshot.py','run_stage.py','isolated_git.py']:
 ast.parse((O/name).read_text(encoding='utf-8'));checks.append({'path':name,'sha256':sha(O/name),'AST':'PASS'})
for row in binding['files']:assert sha(O/row['path'])==row['candidate_sha256']
for row in read(O/'SOURCE_SAVE_FIXTURE_BINDING.json')['files']:assert sha(R/row['path'])==row['sha256']
write(O/'CURRENT_TOOL_BINDING_REVIEW.json',{'status':'PASS','scope':'exact actual PE/Native manifest/unchanged guard bytes and AST preparation only','binding_sha256':sha(O/'CANDIDATE_BINDING.json'),'ast_checks':checks,'fixture_files_verified':6,'new_snapshot_created':False,'positive_stages_started':0,'still_blocked_on':'actual matching full World+normal-exit PASS framework receipt/runner/source manifest/protection from parent'})
doc=(O/'SIX_STAGE_COMMANDS.pending.md').read_text(encoding='utf-8')
doc=doc.replace('Native is58a1; new actual PE binding is PENDING.','Native is58a1 and the actual Windows PE pair is bound in CANDIDATE_BINDING.json.').replace('<PENDING-new-Windows-build>','windows_map_reply_observation_20261017_build')
(O/'SIX_STAGE_COMMANDS.md').write_text(doc,encoding='utf-8')
print(json.dumps({'binding_sha256':sha(O/'CANDIDATE_BINDING.json'),'actual_build_receipt_sha256':sha(receipt),'guard_review_sha256':sha(O/'CURRENT_TOOL_BINDING_REVIEW.json'),'new_snapshot_created':False,'positive_stages_started':0}))
