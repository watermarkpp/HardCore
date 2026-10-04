from pathlib import Path
import datetime,hashlib,json

root=Path.cwd()
base=root/'outputs/r3_takeover/20260930/validation'
green=base/'periodic_dispatch_period_policy_green_2102_210019_464305'
red=base/'periodic_dispatch_period_policy_red_2055_205629_991195'
owned=root/'outputs/framework_v2/feature_templates_20261004'
def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
before=read(green/'before.json'); after=read(green/'after.json')
assert before['files']==after['files'] and before['content_set_sha256']==after['content_set_sha256']
assert before['engine_sha256']==after['engine_sha256']=='d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c'
assert before['engine_version']==after['engine_version']=='4.7.stable.official.5b4e0cb0f'
for path,expected in before['files'].items():
    candidate=(root/path).resolve(); assert candidate.is_relative_to(root)
    assert digest(candidate)==expected,path
runner=read(green/'runner_results.json'); validation=read(green/'validation.json')
assert runner['passed']==runner['total']==4 and runner['failed']==runner['engine_log_errors']==0
assert validation['status']=='PASS' and validation['exit_code']==0 and validation['source_stable_during_run']
rows=[]
for native in runner['results']:
    scene=native['test_name']; path=green/'framework'/(scene+'.result.json'); receipt=read(path)
    assert receipt['scene_id']==scene and receipt['run_id']==native['framework_run_id']
    assert receipt['invocation_id']==runner['invocation_id'] and receipt['source_content_sha256']==before['content_set_sha256']
    assert receipt['status']=='PASS' and receipt['failed']==receipt['reported_failures']==0
    assert receipt['count']==receipt['passed']==receipt['reported_checks']==len(receipt['checks'])
    assert all(check['passed'] for check in receipt['checks'])
    assert native['effective_exit_code']==0 and native['process_exited'] and not native['timeout'] and native['framework_receipt_valid']
    logs=[]
    for extension in ['stdout.log','stderr.log','godot.log']:
        log=green/'native_logs'/(scene+'.'+extension); assert log.exists()
        logs.append({'path':log.relative_to(root).as_posix(),'sha256':digest(log)})
    rows.append({'scene':scene,'checks':receipt['count'],'run_id':receipt['run_id'],'invocation_id':receipt['invocation_id'],'receipt_sha256':digest(path),'native_exit':0,'logs':logs})
assert sum(row['checks'] for row in rows)==159
red_runner=read(red/'runner_results.json'); assert red_runner['failed']==2 and red_runner['engine_log_errors']==0
failures=[]
for native in red_runner['results']:
    receipt=read(red/'framework'/(native['test_name']+'.result.json'))
    assert receipt['status']=='FAIL' and native['effective_exit_code']==1 and not native['timeout']
    failures.append({'scene':receipt['scene_id'],'count':receipt['count'],'failed':receipt['failed'],'run_id':receipt['run_id'],'labels':[c['label'] for c in receipt['checks'] if not c['passed']]})
assert {r['scene']:r['failed'] for r in failures}=={'periodic_refresh_period_boundary_test':2,'feature_delivery_templates_test':13}
result={'status':'PASS','read_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_content_sha256':before['content_set_sha256'],'source_files':len(before['files']),'engine_version':before['engine_version'],'engine_sha256':before['engine_sha256'],'checks':159,'scenes':4,'green_rows':rows,'red_failures':failures,'red_scope':'26/2 policy failures are the confirmed contract mismatch; 57/13 template failures are no-op setter fixture expectations, all eight source-index assertions passed','scope':'controlled compiled refresh with original HP/Batch ports and complete expiry/new-state identity checks; template formal compiler/publisher and eight combinations; not natural deadline/GPU/Android acceptance'}
(owned/'POLICY_TEMPLATE_ASSOCIATIONS.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:result[k] for k in ['status','source_content_sha256','source_files','checks','scenes']}))
