from pathlib import Path
import hashlib,json,difflib
o=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
r=json.loads((o/'COMPONENT_RESULT.json').read_text())
assert r['status']=='PASS' and r['checks']==41 and r['failed']==0 and r['not_run']==0
assert r['real_index_before']==r['real_index_after']=='3180f91855b8bc8d7a22848592ff9f95f2d19574a73f7a3eea90e962f7151b22'
patch=''.join(''.join(difflib.unified_diff([],p.read_text(encoding='utf-8').splitlines(True),fromfile='/dev/null',tofile='b/outputs/v115_multicore/fixed_release_snapshot_parallel_20261017/'+p.name)) for p in [*sorted(o.glob('*.py')),o/'README.md'])
(o/'NEW_FILES.patch').write_text(patch,encoding='utf-8',newline='\n')
result={'status':'PASS','scope':'PRIVATE_GIT_COMPONENT_ONLY','actual_test':{'checks':41,'failed':0,'not_run':0,'native_exit':0,'receipt_sha256':sha(o/'COMPONENT_RESULT.json')},'production_snapshot':'NOT_RUN','production_common_objects_publication':'NOT_RUN','formal_CLI_runtime':'NOT_RUN','World_and_normal_exit':'FAIL upstream; not retested','SourceSave_six_stages':'NOT_RUN','viewport_followup':'NOT_RUN; not started per stop instruction','remote_ref_and_push':'NOT_RUN by worker; parent-owned handoff-only','real_index_preserved':True,'files':[{'path':p.name,'sha256':sha(p),'bytes':p.stat().st_size} for p in sorted(o.glob('*.py'))], 'remaining':['Parent review of formal CLI full production selection/gates','True World/normal-exit PASS required for formal release snapshot','Parent handoff-only documents/evidence policy and ref/push','Parent delivery archive validation must cover all assets/','Viewport identity and other known World blockers','SourceSave six actual180s stages and final APK/device gates']}
(o/'FINAL_RESULT.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
files=[{'path':p.relative_to(o).as_posix(),'sha256':sha(p),'bytes':p.stat().st_size} for p in sorted(o.rglob('*')) if p.is_file() and p.name!='DELIVERY_SHA256.json']
(o/'DELIVERY_SHA256.json').write_text(json.dumps({'frozen':True,'files':files},indent=2)+'\n',encoding='utf-8')
print(json.dumps({'final_sha256':sha(o/'FINAL_RESULT.json'),'delivery_sha256':sha(o/'DELIVERY_SHA256.json'),'files':len(files),'component_receipt_sha256':sha(o/'COMPONENT_RESULT.json'),'tools':result['files']}))
