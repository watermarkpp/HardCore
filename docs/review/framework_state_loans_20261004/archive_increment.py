from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, os, shutil, subprocess, sys, zipfile

ROOT = Path.cwd()
assert ROOT == Path(r'C:/Users/Administrator/.codex/worktrees/pluggable-framework-v2/HardCore')
OWNED = ROOT/'outputs/framework_v2/state_loan_20261004'
DEST = ROOT/'docs/review/framework_state_loans_20261004'
V = ROOT/'outputs/r3_takeover/20260930/validation'
PARENT = '800cca3cdb7cf21bc0802ae2650d982ec6cc0c9e'
DIRECT, WORLD = sys.argv[1:3]
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,d): p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def git(root,*args,env=None): return subprocess.check_output(['git',*args],cwd=root,env=env)
final = read(V/DIRECT/'before.json')
assert read(V/WORLD/'before.json')['files'] == final['files']
for path,digest in final['files'].items(): assert sha(ROOT/path)==digest,('changed',path)
prior = json.loads(git(ROOT,'show',PARENT+':docs/review/framework_periodic_retirement_20261004/SOURCE_MANIFEST.json'))
assert not set(prior['files'])-set(final['files']), 'unexpected source removal'
delta = [{'path':path,'before_sha256':prior['files'].get(path),'after_sha256':digest}
         for path,digest in final['files'].items() if prior['files'].get(path)!=digest]
DEST.mkdir(parents=True,exist_ok=True)
write(DEST/'SOURCE_MANIFEST.json',final)
write(DEST/'SOURCE_DELTA.json',{'parent':PARENT,'source_content_sha256':final['content_set_sha256'],'delta':delta})
prefixes = ('state_loan_',)
runs = sorted(p for p in V.iterdir() if p.is_dir() and p.name.startswith(prefixes) and (p/'runner_results.json').is_file())
entries,records,failures,adopted = [],[],[],{}
for source in runs:
    before,after,validation,report = [read(source/name) for name in ('before.json','after.json','validation.json','runner_results.json')]
    owned = [source/name for name in ('before.json','after.json','validation.json','runner_results.json','runner.log')]
    owned += [p for folder in ('raw','framework') for p in (source/folder).rglob('*') if p.is_file()]
    for p in owned:
        target=DEST/'native'/source.name/p.relative_to(source)
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(p,target)
        entries.append({'original_path':p.relative_to(ROOT).as_posix(),'archive_path':target.relative_to(DEST).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)})
    rows=[]
    for row in report['results']:
        receipt_path=source/'framework'/(row['test_name']+'.result.json')
        receipt=read(receipt_path) if receipt_path.is_file() else None
        receipt_valid = bool(receipt and receipt.get('run_id') == row['framework_run_id'] and receipt.get('invocation_id') == report['invocation_id'] and receipt.get('source_content_sha256') == before['content_set_sha256'])
        if receipt and not receipt_valid: receipt = None
        if receipt:
            assert receipt['run_id']==row['framework_run_id'] and receipt['invocation_id']==report['invocation_id']
            assert receipt['source_content_sha256']==before['content_set_sha256']
            assert receipt['count']==len(receipt['checks'])==receipt['passed']+receipt['failed']
            assert sum(not c['passed'] for c in receipt['checks'])==receipt['failed']
        item={'invocation':source.name,'test_path':row['test_path'],'run_id':row.get('framework_run_id'),
              'invocation_id':report['invocation_id'],'result':row['result'],'reason':row['reason'],
              'source_content_sha256':before['content_set_sha256'],'native_exit':row['effective_exit_code'],
              'timeout':row['timeout'],'receipt_count':receipt['count'] if receipt else None}
        rows.append(item)
        if row['result']!='PASS': failures.append(item)
        if source.name in (DIRECT,WORLD):
            assert validation['status']=='PASS' and before['files']==after['files']==final['files']
            assert row['result']=='PASS' and row['process_exited'] and row['effective_exit_code']==0 and not row['timeout']
            assert row['native_exit_observed_utc'] and not row['engine_log_failure_count']
            if row['test_path'].startswith('tests/framework/'):
                assert receipt and receipt['status']=='PASS' and receipt['failed']==0 and row['framework_receipt_valid']
            assert row['test_path'] not in adopted
            adopted[row['test_path']]=item
    records.append({'name':source.name,'status':validation['status'],'command':validation['command'],
                    'source_stable_during_run':validation['source_stable_during_run'],'rows':rows})
wrapper_rejections=[]
for source in sorted(p for p in V.iterdir() if p.is_dir() and p.name.startswith(prefixes)
                     and (p/'validation.json').is_file() and not (p/'runner_results.json').is_file()):
    validation=read(source/'validation.json')
    log=(source/'runner.log').read_text(encoding='utf-8-sig')
    assert validation['status']=='FAIL' and validation['passed'] is None and validation['failed'] is None
    assert 'TestPaths entry does not exist: tests/framework/frame_budget_fair_turn_test.tscn' in log, source.name
    for name in ('before.json','after.json','validation.json','runner.log'):
        p=source/name
        target=DEST/'native'/source.name/name
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(p,target)
        entries.append({'original_path':p.relative_to(ROOT).as_posix(),'archive_path':target.relative_to(DEST).as_posix(),
                        'bytes':p.stat().st_size,'sha256':sha(p)})
    wrapper_rejections.append({'invocation':source.name,'status':'FAIL','classification':'missing_requested_test_path_before_native_scenes',
                               'native_scenes_started':0,'command':validation['command'],'exit_code':validation['exit_code']})
write(DEST/'WRAPPER_REJECTIONS.json',{'attempts':wrapper_rejections,'scope':'Preserved startup rejection; excluded from native scene counts.'})
write(DEST/'NATIVE_MANIFEST.json',{'files':entries})
write(DEST/'RUN_INDEX.json',{'recorded_at_utc':datetime.now(timezone.utc).isoformat(),'parent':PARENT,'runs':records,
      'final_adopted_rows':list(adopted.values()),'preserved_failed_rows':failures,
      'scope':'Returned origin-owned state loans reserve N*S resident storage for supported direct/child finite chains, while keeping original cumulative facts/receipts/child frontier unchanged. Invalid old-life states return one loan only to a live origin before accepted new-life work needs it; shared refresh roots and original source/credit remain held until terminal. Controlled real HP/life/refresh/clear and real Player windup/Root planner/late-life child API probes are separate evidence scopes. Periodic fact/death-child compiler remains closed. Full Task3-5/natural P6R3/framework/APK remain NOT_RUN.'})
env=os.environ.copy(); env.pop('GIT_INDEX_FILE',None)
env['GIT_OPTIONAL_LOCKS']='0'
protection=read(ROOT/'outputs/framework_v2/resource_consumption_20261004/BEFORE.json')['protected']
index_check=read(ROOT/'outputs/framework_v2/resource_consumption_20261004/LIVE_INDEX_CHECK.json')
verified={'verified_at_utc':datetime.now(timezone.utc).isoformat()}
for name,root in [('main',Path(r'C:/Users/Administrator/Documents/HardCore')),
                  ('second',Path(r'C:/Users/Administrator/Documents/HardCore-worktrees/glm53-r1-20260929')),
                  ('third',ROOT)]:
    head=git(root,'rev-parse','HEAD',env=env).decode().strip()
    branch=git(root,'branch','--show-current',env=env).decode().strip()
    index=Path(git(root,'rev-parse','--git-path','index',env=env).decode().strip())
    if not index.is_absolute(): index=root/index
    assert head==protection[name]['head'] and branch==protection[name]['branch']
    expected_index=index_check['actual_sha256'] if name=='third' else protection[name]['index_sha256']
    assert sha(index)==expected_index,(name,'observed real index changed')
    if name=='third':
        assert hashlib.sha256(git(root,'ls-files','--stage',env=env)).hexdigest()==index_check['staged_entries_sha256']
    status=git(root,'status','--short',env=env)
    digest=hashlib.sha256(status).hexdigest()
    if name!='third': assert digest==protection[name]['status_sha256'],(name,'protected dirty changed')
    verified[name]={'path':str(root),'head':head,'branch':branch,'real_index_sha256':sha(index),
                    'dirty_count':len(status.splitlines()),'status_sha256':digest}
streaming=sha(ROOT/'scripts/monster_visual_streaming_coordinator.gd')
assert streaming==protection['frozen_streaming_sha256']
verified['frozen_monster_streaming_sha256']=streaming
write(DEST/'PROTECTION.json',verified)
write(DEST/'INDEX_CONTINUITY_BOUNDARY.json',index_check)
media=[]
for name in ['assets/art/items/service/inventory/client.classic_raw_complete/Items_00014.png',
             'assets/audio/sfx/client/137__M26-3.wav','assets/audio/sfx/client/10332__M33-3.wav']:
    p=ROOT/name; media.append({'path':name,'bytes':p.stat().st_size,'sha256':sha(p)})
    assert git(ROOT,'show',PARENT+':'+name)==p.read_bytes(),('primary media changed',name)
write(DEST/'PRIMARY_RESOURCES.json',{'resources':media,'scope':'Separate raw media verification; existing primary bytes unchanged.'})
audit=ROOT/'outputs/framework_v2/chain_state_pool_20261004/audit_800cca3c'
for name in ('PRO_REPORT.md','PRO_READ_MANIFEST.json','DOT_REPORT.md','DOT_READ_MANIFEST.json'):
    original=audit/name
    assert original.is_file(),name
    target=DEST/'audit_parent_800cca3c'/name
    target.parent.mkdir(exist_ok=True);shutil.copy2(original,target)
write(DEST/'AUDIT_PARENT_STATUS.json',{'fixed_sha':PARENT,'pro_full_report_read':True,
      'dot_full_report_read':True,'dot_original_outbound_status':'FAIL','dot_turn_status':'interrupted',
      'scope':'Both complete scoped bodies actually read. Dot body is its own complete authored outbound tool text retrieved directly from original thread; original failed delivery retained, not a successful relay or native rerun.'})
observed=ROOT/'outputs/framework_v2/heterogeneous_20261004'
index_originals=[('observed_index.bin',index_check['actual_sha256']),('observed_staged_entries.txt',index_check['staged_entries_sha256'])]
index_rows=[]
with zipfile.ZipFile(DEST/'INDEX_OBSERVED_BYTES.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for name,digest in index_originals:
        original=observed/name
        assert sha(original)==digest,(name,'existing backup changed')
        z.write(original,name)
        index_rows.append({'member':name,'original_path':original.relative_to(ROOT).as_posix(),'bytes':original.stat().st_size,'sha256':digest})
with zipfile.ZipFile(DEST/'INDEX_OBSERVED_BYTES.zip') as z:
    for item in index_rows:
        raw=z.read(item['member']); assert len(raw)==item['bytes'] and hashlib.sha256(raw).hexdigest()==item['sha256']
write(DEST/'INDEX_OBSERVED_BYTES.json',{'files':index_rows,'archive_sha256':sha(DEST/'INDEX_OBSERVED_BYTES.zip'),
      'archive_bytes':(DEST/'INDEX_OBSERVED_BYTES.zip').stat().st_size,'scope':'Already retained current observation, never restored or used to reconstruct missing historical bytes.',
      'historical_continuity_status':'FAIL','historical_original_backup_status':'MISSING'})
rfc=ROOT/'docs/architecture/pluggable_framework/RFC_V2_USER_SOURCE_20260930.md'
assert sha(rfc)=='4d4ddfac6b52e705ec91fb42dfc78f3cbec6a438b169a0a1932510b560664781'
with zipfile.ZipFile(DEST/'TESTED_SOURCE.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for name in final['files']: z.write(ROOT/name,name)
    z.write(rfc,rfc.relative_to(ROOT).as_posix())
    for item in media: z.write(ROOT/item['path'],item['path'])
with zipfile.ZipFile(DEST/'TESTED_SOURCE.zip') as z:
    for name,digest in final['files'].items(): assert hashlib.sha256(z.read(name)).hexdigest()==digest
    for item in media: assert hashlib.sha256(z.read(item['path'])).hexdigest()==item['sha256']
with zipfile.ZipFile(DEST/'NATIVE_EVIDENCE.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for item in entries: z.write(DEST/item['archive_path'],item['archive_path'])
with zipfile.ZipFile(DEST/'NATIVE_EVIDENCE.zip') as z:
    for item in entries:
        b=z.read(item['archive_path']); assert len(b)==item['bytes'] and hashlib.sha256(b).hexdigest()==item['sha256']
summary={'parent':PARENT,'construction_head':final['tested_sha'],'source_content_sha256':final['content_set_sha256'],
         'source_files':len(final['files']),'delta_files':len(delta),'final_unique_positive_scenes':len(adopted),
         'final_framework_receipts':sum(r['receipt_count'] is not None for r in adopted.values()),
         'final_framework_checks':sum(r['receipt_count'] or 0 for r in adopted.values()),
         'native_attempts':sum(len(r['rows']) for r in records),'preserved_failed_attempts':len(failures),
         'preserved_wrapper_rejections':len(wrapper_rejections),
         'status':'PASS','whole_resource_task_status':'NOT_RUN','whole_framework_status':'NOT_RUN',
         'apk_status':'NOT_RUN','device_status':'NOT_RUN','engine_version':final['engine_version'],
         'engine_console_sha256':final['engine_sha256'],'engine_child_sha256':sha(ROOT/'tools/godot-4.7/Godot_v4.7-stable_win64.exe'),
         'scope':'Returned origin-owned state loans reserve N*S resident storage for supported direct/child finite chains, while keeping original cumulative facts/receipts/child frontier unchanged. Invalid old-life states return one loan only to a live origin before accepted new-life work needs it; shared refresh roots and original source/credit remain held until terminal. Controlled real HP/life/refresh/clear and real Player windup/Root planner/late-life child API probes are separate evidence scopes. Periodic fact/death-child compiler remains closed. Full Task3-5/natural P6R3/framework/APK remain NOT_RUN.',
         'open':['fault supervisor safety before further destructive replay','GPU/device readability/audio','Task4 periodic child/state chains/A-B refresh/self-excitation/generated combinations','Task5 templates/generated combos/full P6R3','v97 original B MISSING','APK/Android delivery']}
for name in ('TESTED_SOURCE.zip','NATIVE_EVIDENCE.zip','INDEX_OBSERVED_BYTES.zip'): summary[name]={'bytes':(DEST/name).stat().st_size,'sha256':sha(DEST/name)}
write(DEST/'SCOPED_EVIDENCE.json',summary)
print(json.dumps(summary,ensure_ascii=True))
