from pathlib import Path
import hashlib,json,subprocess,sys,shutil
r=Path('.').resolve();o=r/'outputs/v115_multicore/codex_resume_20261015_182255';inv=r/'outputs/v115_multicore/invocations/codex_map_reply_observation_cold_capture_20261017';out=o/'map_reply_observation_code_catalogue_20261017';out.mkdir(exist_ok=False)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
pro=json.loads((inv/'PROTECTION.json').read_text(encoding='utf-8-sig'));assert pro['real_index_preserved'] and pro['source_unchanged']
# Require the exact current Native capture invocation to complete successfully.
# Catalogue generation remains distinct from Source/World runtime acceptance.
assert pro['native_runner_exit']==0
binding=json.loads((inv/'SOURCE_BINDING.json').read_text(encoding='utf-8-sig'));art={};records=[];commands=[]
for kind,scene,suffix in [('namespace','code_preparation_engine_namespace_capture_test','namespace'),('symbols','code_preparation_native_symbol_probe_test','symbols'),('fold','code_preparation_scalar_math_probe_test','symbols')]:
 receipt=next((inv/'native').glob('*/'+scene+'.result.json'));data=json.loads(receipt.read_text(encoding='utf-8-sig'));assert data['status']=='PASS' and data['reported_failures']==0
 original=r/'outputs/test_logs/framework'/(scene+'.'+suffix+'.json');a=json.loads(original.read_text(encoding='utf-8-sig'))
 assert a['run_id']==receipt.parent.name and a['invocation_id']==data['invocation_id'] and a['source_content_sha256']==binding['source_content_sha256']
 assert a['engine']['binary_sha256']=='7f54a5090cfde94a7d2fcf37c22c14ecd23e00eefcc0bf5e23d1c0326bc7b8de'
 assert sha(original) in (receipt.parent/(scene+'.stdout.log')).read_text(encoding='utf-8-sig')
 dest=out/original.name;shutil.copy2(original,dest);assert sha(dest)==sha(original)
 art[kind]=dest;records.append({'kind':kind,'path':str(dest),'sha256':sha(dest),'actual_run':a['run_id'],'receipt':str(receipt),'receipt_sha256':sha(receipt)})
plan=out/'caster_inputs.json';cache=r/'.godot/global_script_class_cache.cfg';compiler=r/'tools/compile_code_preparation_inputs.py';compiler_sha=sha(compiler)
def run(args):
 commands.append([str(x) for x in args]);p=subprocess.run([str(x) for x in args],capture_output=True,text=True,encoding='utf-8');print(p.stdout);print(p.stderr) if p.stderr else None
 if p.returncode:raise RuntimeError('Formal producer failed '+str(p.returncode))
run([sys.executable,'-B',compiler,'--root',r,'--entry','res://scripts/caster_skill_animation_player.gd','--class-cache',cache,'--max-source-nodes','64','--native-namespace',art['namespace'],'--expected-engine-binary-sha256','7f54a5090cfde94a7d2fcf37c22c14ecd23e00eefcc0bf5e23d1c0326bc7b8de','--global-symbols',art['symbols'],'--expected-global-symbols-sha256',sha(art['symbols']),'--fold-symbols',art['fold'],'--expected-fold-symbols-sha256',sha(art['fold']),'--out',plan])
assert json.loads(plan.read_text(encoding='utf-8'))['status']=='PASS'
gen=out/'generated/internal_code_preparation_catalog_data.gd'
run([sys.executable,'-B',r/'tools/build_internal_code_catalogue.py','--root',r,'--class-cache',cache,'--max-source-nodes','64','--entry-id','framework.code.caster_animation.v1','--expected-producer-sha256',compiler_sha,'--plan',plan,'--namespace',art['namespace'],'--symbols',art['symbols'],'--fold',art['fold'],'--expected-namespace-sha256',sha(art['namespace']),'--expected-symbols-sha256',sha(art['symbols']),'--expected-fold-sha256',sha(art['fold']),'--out',gen])
assert sha(compiler)==compiler_sha
p=r/'scripts/features/generated/internal_code_preparation_catalog_data.gd';before=out/'internal_code_preparation_catalog_data.preimage.gd';before.write_bytes(p.read_bytes());p.write_bytes(gen.read_bytes());assert sha(p)==sha(gen)
(out/'GENERATION_RECEIPT.json').write_text(json.dumps({'status':'PASS','scope':'Exact current Native 58a1b306 namespace/symbol/fold capture invocation PASS; formal code catalogue generation only; Source/full World runtime NOT_RUN','captures':records,'commands':commands,'producer_sha256':compiler_sha,'old_catalogue_sha256':sha(before),'new_catalogue_sha256':sha(p),'class_cache_sha256':sha(cache),'engine_sha256':'7f54a5090cfde94a7d2fcf37c22c14ecd23e00eefcc0bf5e23d1c0326bc7b8de'},indent=2),encoding='utf-8')
