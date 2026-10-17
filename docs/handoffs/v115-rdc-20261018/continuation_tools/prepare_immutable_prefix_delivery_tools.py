from pathlib import Path
import json,hashlib,ast,subprocess,sys,shutil
D=Path(__file__).resolve().parent;R=D.parents[3];O=D.parent;V=O.parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
win=O/'windows_immutable_prefix_cache_20261018_build';android=O/'android_immutable_prefix_cache_20261018_build'
w=json.loads((win/'BUILD_RECEIPT.json').read_text(encoding='utf-8-sig'));a=json.loads((android/'ANDROID_TEMPLATE_RECEIPT.json').read_text(encoding='utf-8-sig'))
assert w['status']=='BUILD_WINDOWS_ONLY_PASS' and w['exit_code']==0 and a['status']=='PASS'
main=next(x['sha256'] for x in w['artifacts'] if x['path'].endswith('win64.exe'))
console=next(x['sha256'] for x in w['artifacts'] if x['path'].endswith('console.exe'))
mapping={'fc43ab30cb3ebddb089278d67bafbbe18cedd878ed849b589e8761ad4750c9de':'037be686708445d86cc4abc6bd6b13072f3de9e67ebeb6b32051d45434415cfb','c27aafa68a39b846bed00d8498ee9880cad0f11af0bfd1167c651e6f5293f744':'422f0773560e1a3cc07c1d92ea8b86b13a3445204e05662cb78063dfd322c06c','b53112aad768c933a7b31af6470ec19ca35280d8b733d19ef7aa946ba0133cc1':main,'fc3f8e67a3570b0d764ff525e9fd7172f4b24399fb8e7597d497a645e7d862a2':console,'SOURCE_MANIFEST.caster_close_cleanup_20261018.json':'SOURCE_MANIFEST.immutable_prefix_cache_20261018.json','windows_caster_close_cleanup_20261018_build':'windows_immutable_prefix_cache_20261018_build'}
def updated(s):
    for old,new in mapping.items():s=s.replace(old,new)
    return s
old=V/'source_save_runtime_caster_selection180_20261018';new=V/'source_save_runtime_immutable_prefix180_20261018';new.mkdir(exist_ok=False)
guards=['runner_bridge.ps1','isolated_git.py','STAGE_BUDGET_GATE.json','SOURCE_SAVE_FIXTURE_BINDING.json']
for name in guards:shutil.copy2(old/name,new/name);assert sha(old/name)==sha(new/name)
fixture=json.loads((new/'SOURCE_SAVE_FIXTURE_BINDING.json').read_text(encoding='utf-8-sig'))
for row in fixture['files']:assert sha(R/row['path'])==row['sha256']
for name in ['prepare_snapshot.py','run_stage.py']:
    s=updated((old/name).read_text(encoding='utf-8-sig'));ast.parse(s);(new/name).write_text(s,encoding='utf-8')
b=json.loads(updated((old/'CANDIDATE_BINDING.json').read_text(encoding='utf-8-sig')))
b.update(scope='PREPARATION ONLY new037 Native: unchanged six180s stages, fixture, original guards and real World gate. No snapshot/stage run.',previous_bundle_binding_sha256=sha(old/'CANDIDATE_BINDING.json'))
b['native_revision']['id']='source_save180_immutable_prefix_20261018';b['native_revision']['actual_Windows_build_receipt_sha256']=sha(win/'BUILD_RECEIPT.json')
for row in b['files']:row['previous_bundle_tool_sha256']=sha(old/row['path']);row['candidate_sha256']=sha(new/row['path'])
(new/'UPSTREAM_REVIEWED_BINDING.json').write_bytes((old/'CANDIDATE_BINDING.json').read_bytes());(new/'CANDIDATE_BINDING.json').write_text(json.dumps(b,indent=2)+'\n',encoding='utf-8')
for name in ['prepare_snapshot.py','run_stage.py']:
    result=subprocess.run([sys.executable,str(new/name),'--help'],capture_output=True,text=True,encoding='utf-8');assert result.returncode==0,result.stderr
(new/'PREPARATION_REVIEW.json').write_text(json.dumps({'status':'PASS','scope':'AST/help/pinned inputs only; World gate unchanged; no game acceptance','guards_byte_identical':guards,'snapshots':0,'stages':0},indent=2)+'\n',encoding='utf-8')
old=V/'fixed_release_snapshot_caster_selection_20261018';new=V/'fixed_release_snapshot_immutable_prefix_20261018';new.mkdir(exist_ok=False)
for name in ['isolated_git.py','fixed_release_objects.py','test_fixed_release_objects.py']:shutil.copy2(old/name,new/name);assert sha(old/name)==sha(new/name)
s=updated((old/'fixed_release_snapshot.py').read_text(encoding='utf-8-sig'));ast.parse(s);(new/'fixed_release_snapshot.py').write_text(s,encoding='utf-8')
result=subprocess.run([sys.executable,str(new/'fixed_release_snapshot.py'),'--help'],capture_output=True,text=True,encoding='utf-8');assert result.returncode==0,result.stderr
(new/'PREPARATION_REVIEW.json').write_text(json.dumps({'status':'PASS','scope':'AST/help/pinned Native only; private Git API byte identical, reuse previous41/0 evidence; real World/native0/no leaks/protection + immutable override witness still required','source_object':'NOT_RUN'},indent=2)+'\n',encoding='utf-8')
config=json.loads((D/'delivery_config.fc43_pending_world_20261018.json').read_text(encoding='utf-8-sig'))
def file(p):return {'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p)}
config['native_manifest']=file(O/'SOURCE_MANIFEST.immutable_prefix_cache_20261018.json');config['templates_receipt']=file(android/'ANDROID_TEMPLATE_RECEIPT.json');config['windows_binaries']=[file(win/n) for n in ['Godot_v115-stable_win64_console.exe','Godot_v115-stable_win64.exe']]
config['current_gate_note']='PREPARATION ONLY new037: Windows + matching Android4JNI/Gradle + actual6 Native scenes PASS. Catalogue4af generated. World40 RUNNING; require real full World normal exit PASS, all six oldsave stages and fixed source/signature/content before APK115. No APK.'
(D/'delivery_config.037_pending_world_20261018.json').write_text(json.dumps(config,indent=2)+'\n',encoding='utf-8')
print('new037 tools prepared; unchanged guards/fixtures/World requirements; no snapshots or stages')
