from pathlib import Path
import datetime, hashlib, json, shutil

root=Path.cwd()
folder=root/'outputs/r3_takeover/20260930/validation/periodic_dispatch_service_characterization_20261004_1505_230828_815284'
out=root/'outputs/framework_v2/periodic_dispatch_20261004'
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
before,after=read(folder/'before.json'),read(folder/'after.json')
assert before['files']==after['files'] and before['content_set_sha256']==after['content_set_sha256']
runner=read(folder/'runner_results.json')
assert runner['failed']==3 and runner['passed']==0 and runner['engine_log_errors']==0
receipt=read(folder/'framework/periodic_refresh_service_boundary_test.result.json')
trace_path=root/'outputs/test_logs/framework/periodic_refresh_service_boundary_test.trace.json'
trace=read(trace_path)
assert trace['source_content_sha256']==before['content_set_sha256']==receipt['source_content_sha256']
assert trace['run_id']==receipt['run_id']==runner['results'][0]['framework_run_id']
assert trace['invocation_id']==receipt['invocation_id']==runner['invocation_id']
assert receipt['count']==len(receipt['checks'])==37 and receipt['failed']==3
assert trace['rows'][0]['delivered_sample_ticks']==2231 and trace['rows'][1]['delivered_sample_ticks']==1024
assert runner['results'][0]['process_exited'] and runner['results'][0]['effective_exit_code']==1
assert all(r['timeout'] and not r['process_exited'] for r in runner['results'][1:])
archive=folder/'service_diagnostic_original.trace.json'
assert not archive.exists()
shutil.copyfile(trace_path,archive)
rows=[]
for r in runner['results']:
    rows.append({'scene':r['test_name'],'run_id':r['framework_run_id'],'native_exit':r['effective_exit_code'],
        'timeout':r['timeout'],'reason':r['reason'],'classification':
        'new fixture local 8-second wait incomplete; 4000 delivery remains unproven in this run' if not r['timeout'] else
        'incorrect 30-second process window; same eight-world scene previously took 37 seconds in a 60-second window'})
result={'status':'PASS','classification':'evidence verification only; the native suite remains FAIL',
    'read_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source':before['content_set_sha256'],
    'source_stable':True,'native_failed':3,'complete_receipt_checks':37,'failed_checks':3,
    'trace_sha256':digest(archive),'trace':str(archive.relative_to(root)),'rows':rows,
    'reporting_correction_needed':'old trace fully_drained names intended case, not achieved completion; old future_ticks_not_run=0 is incorrect for first partial run. Preserve original; next trace must report actual remaining 1769.',
    'observed_quantum_scope':'controlled one-state periodic chain; maximum 10365/1662us includes possible scheduling/cold effects, not a proven worst bound or natural performance result'}
(out/'SERVICE_INITIAL_FAILURE_CLASSIFICATION.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:result[k] for k in ['status','native_failed','complete_receipt_checks','failed_checks','source']}))
