from pathlib import Path
import datetime, hashlib, json, re

ROOT = Path.cwd()
OUT = ROOT / 'outputs/framework_v2/feature_templates_20261004'
BASE = ROOT / 'outputs/r3_takeover/20260930/validation'
LABELS = ['periodic_dispatch_policy_related_2114_211428_922565', 'periodic_dispatch_policy_world_2131_213126_203389']
SOURCE = 'd1781a0f05ab5c2c765785b0167979141aeb1b6e6d4918c4d55a05bf732c600b'
def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

errors, rows, handoff_rows, log_rows = [], [], [], []
seen_runs, seen_scenes = set(), set()
def require(condition, label):
    if not condition:
        errors.append(label)

current_files = None
for label in LABELS:
    folder = BASE / label
    before, after = read(folder/'before.json'), read(folder/'after.json')
    runner, validation = read(folder/'runner_results.json'), read(folder/'validation.json')
    require(before['files'] == after['files'], label+':stable_source')
    require(before['engine_sha256'] == after['engine_sha256'] == 'd8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c', label+':stable_engine')
    require(before['engine_version'] == after['engine_version'] == '4.7.stable.official.5b4e0cb0f', label+':engine_version')
    require(before['content_set_sha256'] == SOURCE == after['content_set_sha256'], label+':source')
    require(hashlib.sha256(json.dumps(before['files'], sort_keys=True).encode()).hexdigest() == SOURCE, label+':manifest_content_hash')
    if current_files is None:
        current_files = before['files']
    require(current_files == before['files'], label+':same_final_bytes')
    require(validation['status'] == 'PASS' and validation['exit_code'] == 0 and validation['source_stable_during_run'] is True, label+':validation')
    require(runner['failed'] == 0 and runner['total'] == runner['passed'] == len(runner['results']) and runner['engine_log_errors'] == 0, label+':runner')
    receipts = {p.stem.removesuffix('.result'): p for p in (folder/'framework').glob('*.result.json')}
    require(set(receipts) == {r['test_name'] for r in runner['results']}, label+':receipt_set')
    for native in runner['results']:
        scene = native['test_name']
        path = receipts[scene]
        proof = read(path)
        require(scene not in seen_scenes and proof['run_id'] not in seen_runs, scene+':unique_identity')
        seen_scenes.add(scene); seen_runs.add(proof['run_id'])
        require(proof['scene_id'] == scene and proof['run_id'] == native['framework_run_id'] and proof['invocation_id'] == runner['invocation_id'], scene+':identity')
        require(proof['source_content_sha256'] == SOURCE and proof['runtime_environment']['runtime_appdata'] == native['runtime_appdata'], scene+':environment')
        require(native['result'] == 'PASS' and native['process_exited'] is True and native['wrapper_exit_code'] == native['effective_exit_code'] == 0 and native['timeout'] is False and native['framework_receipt_valid'] is True, scene+':native_terminal')
        require(all(native[k] == 0 for k in ['stdout_failure_count','stderr_failure_count','engine_log_failure_count']), scene+':native_errors')
        count = len(proof['checks'])
        require([c['id'] for c in proof['checks']] == list(range(1,count+1)), scene+':check_ids')
        require(all(c['passed'] is True for c in proof['checks']) and proof['status'] == 'PASS' and proof['failed'] == proof['reported_failures'] == 0 and proof['count'] == proof['passed'] == proof['reported_checks'] == count, scene+':complete_checks')
        rows.append({'suite':label,'scene':scene,'run_id':proof['run_id'],'invocation_id':proof['invocation_id'],'checks':count,'failed':proof['failed'],'status':proof['status'],'native_exit':native['effective_exit_code'],'timeout':native['timeout'],'receipt_path':path.relative_to(ROOT).as_posix(),'receipt_sha256':digest(path)})
        for suffix in ['stdout.log','stderr.log','godot.log']:
            log = folder/'native_logs'/(scene+'.'+suffix)
            require(log.exists(), scene+':archived_'+suffix)
            if log.exists():
                text = log.read_text(encoding='utf-8-sig',errors='replace')
                log_rows.append({'path':log.relative_to(ROOT).as_posix(),'sha256':digest(log),'objectdb_warning_lines':sum(bool(re.search(r'WARNING:.*ObjectDB.*leaked', line)) for line in text.splitlines())})
    handoff_path = folder/'framework/native_handoffs.json'
    if handoff_path.exists():
        handoff = read(handoff_path)
        require(handoff['invocation_id'] == runner['invocation_id'] and handoff['source_content_sha256'] == SOURCE, label+':handoff_header')
        for scene, transfer in handoff['producers'].items():
            proof_path = receipts[scene]
            proof = read(proof_path)
            require(transfer['scene_id'] == scene and transfer['run_id'] == proof['run_id'] and transfer['source_content_sha256'] == SOURCE and transfer['receipt_sha256'] == digest(proof_path) and transfer['result'] == 'PASS' and transfer['process_exited'] is True and transfer['effective_exit_code'] == 0, scene+':handoff_receipt')
        pairs = [('combined_effect_lifecycle','combined_effect_lifecycle'),('periodic_credit_safe_logout','periodic_credit_safe_logout'),('natural_effect_lifecycle','natural_effect_lifecycle'),('feature_resource_natural','feature_resource_natural')]
        for prefix, expected_prefix in pairs:
            if prefix+'_test' not in receipts:
                require(prefix+'_cold_test' not in receipts, prefix+':cold_without_live')
                continue
            require(prefix+'_test' in handoff['producers'], prefix+':successful_live_handoff')
            live = read(receipts[prefix+'_test'])
            cold = read(receipts[prefix+'_cold_test'])
            expected_path = folder/'framework'/(expected_prefix+'_expected.json')
            expected = read(expected_path)
            require(expected['producer_run_id'] == live['run_id'] != cold['run_id'] and expected['invocation_id'] == runner['invocation_id'] and expected['source_content_sha256'] == SOURCE, prefix+':current_producer')
            live_native = next(r for r in runner['results'] if r['test_name'] == prefix+'_test')
            cold_native = next(r for r in runner['results'] if r['test_name'] == prefix+'_cold_test')
            require(live_native['native_exit_observed_utc'] < cold_native['wrapper_started_utc'], prefix+':cold_after_successful_live')
            handoff_rows.append({'live_scene':live['scene_id'],'live_run_id':live['run_id'],'cold_scene':cold['scene_id'],'cold_run_id':cold['run_id'],'expected_path':expected_path.relative_to(ROOT).as_posix(),'expected_sha256':digest(expected_path),'generation_scope':'empty value only; separate earlier nonempty production test not rerun'})

for path, expected_hash in current_files.items():
    require((ROOT/path).exists() and digest(ROOT/path) == expected_hash, 'current_bytes:'+path)
require(len(rows) == 33 and sum(r['checks'] for r in rows) == 1252, 'declared_totals')
result = {'status':'FAIL' if errors else 'PASS','read_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_content_sha256':SOURCE,'source_files':len(current_files),'engine_version':before['engine_version'],'engine_sha256':before['engine_sha256'],'errors':errors,'totals':{'scenes':len(rows),'checks':sum(r['checks'] for r in rows),'failed_checks':sum(r['failed'] for r in rows),'cold_pairs':len(handoff_rows)},'rows':rows,'handoffs':handoff_rows,'native_logs':log_rows,'scope':'exact two final stages, complete receipt checks and current producer associations; original-period refresh and default-off delivery templates included; not global P6/GPU/Android/zero leak acceptance'}
(OUT/'POLICY_FINAL_ASSOCIATIONS.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Explicit controller extraction for a bounded read-only GLM counting task.
mechanical = {k:result[k] for k in ['source_content_sha256','source_files','rows','handoffs']}
(OUT/'POLICY_FINAL_MECHANICAL_INPUT.json').write_text(json.dumps(mechanical,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:result[k] for k in ['status','totals','source_files','errors']}))
raise SystemExit(bool(errors))
