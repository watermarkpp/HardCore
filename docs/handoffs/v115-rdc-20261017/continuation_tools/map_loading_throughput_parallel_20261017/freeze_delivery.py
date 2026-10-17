from pathlib import Path
import hashlib, json

out=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
binding=json.loads((out/'CANDIDATE_BINDING.json').read_text())
validation=json.loads((out/'STATIC_VALIDATION.json').read_text())
assert validation['status']=='PASS' and validation['checks']==29 and validation['failed']==0
assert validation['candidate_sha256']==binding['candidate_sha256']
report={
 'status':'PASS','scope':'DIAGNOSTIC_CANDIDATE_STATIC_ONLY',
 'production_applied':False,'runtime_root_cause':'NOT_PROVEN',
 'static_protocol_projection':{'status':'PASS','checks':29,'failed':0,'native_exit':0},
 'Godot_parser':'NOT_RUN','actual_World':'NOT_RUN','actual_SourceSave':'NOT_RUN',
 'production_source_unchanged':validation['source_before_sha256']==validation['source_after_sha256'],
 'index_unchanged':validation['index_before_sha256']==validation['index_after_sha256'],
 'binding':binding,'static_validation_sha256':sha(out/'STATIC_VALIDATION.json'),
 'limitations':['Trace wall intervals include waits and adjacent API calls, not exclusive CPU',
 'Godot Variant request bytes are not Native wire bytes',
 'Enabled diagnostics have explicitly measured encoding and unmeasured output overhead',
 'No heartbeat if existing Source continuation never resumes',
 'Runtime, performance fix, normal exit and six SourceSave stages remain unverified'],
}
(out/'FINAL_RESULT.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
rows=[]
for path in sorted(out.rglob('*')):
    if path.is_file() and path.name!='DELIVERY_SHA256.json':
        rows.append({'path':path.relative_to(out).as_posix(),'bytes':path.stat().st_size,'sha256':sha(path)})
(out/'DELIVERY_SHA256.json').write_text(json.dumps({'frozen':True,'files':rows},indent=2)+'\n',encoding='utf-8')
print(json.dumps({'candidate_sha256':binding['candidate_sha256'],'patch_sha256':binding['patch_sha256'],'final_sha256':sha(out/'FINAL_RESULT.json'),'delivery_sha256':sha(out/'DELIVERY_SHA256.json')}))
