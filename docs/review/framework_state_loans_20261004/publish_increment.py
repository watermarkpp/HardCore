from pathlib import Path
import hashlib,json,os,subprocess,datetime,re

ROOT=Path.cwd()
assert ROOT==Path(r'C:/Users/Administrator/.codex/worktrees/pluggable-framework-v2/HardCore')
OWNED=ROOT/'outputs/framework_v2/state_loan_20261004'
DEST=ROOT/'docs/review/framework_state_loans_20261004'
PARENT='800cca3cdb7cf21bc0802ae2650d982ec6cc0c9e'
BRANCH='refs/heads/codex/framework-layered-critical-20261003'
env=os.environ.copy();env['GIT_OPTIONAL_LOCKS']='0';env['GIT_INDEX_FILE']=str(OWNED/'review.index')
def git(*args,input=None,alternate=True):
    e=env.copy()
    if not alternate:e.pop('GIT_INDEX_FILE',None)
    return subprocess.check_output(['git',*args],cwd=ROOT,env=e,input=input)
def sha(b):return hashlib.sha256(b).hexdigest()
def write(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

assert git('rev-parse',BRANCH).decode().strip()==PARENT
source=json.loads((DEST/'SOURCE_MANIFEST.json').read_text(encoding='utf-8'))
for path,digest in source['files'].items():assert sha((ROOT/path).read_bytes())==digest,path
native=json.loads((DEST/'NATIVE_MANIFEST.json').read_text(encoding='utf-8'))
for item in native['files']:
    p=DEST/item['archive_path'];assert p.stat().st_size==item['bytes'] and sha(p.read_bytes())==item['sha256'],str(p)
scoped=json.loads((DEST/'SCOPED_EVIDENCE.json').read_text(encoding='utf-8'))
for path in ('TESTED_SOURCE.zip','NATIVE_EVIDENCE.zip'):
    p=DEST/path;assert p.stat().st_size==scoped[path]['bytes'] and sha(p.read_bytes())==scoped[path]['sha256']
boundary=json.loads((DEST/'INDEX_CONTINUITY_BOUNDARY.json').read_text(encoding='utf-8'))
assert sha(Path(boundary['index']).read_bytes())==boundary['actual_sha256']
assert sha(git('ls-files','--stage',alternate=False))==boundary['staged_entries_sha256']

names=sorted(source['files'])
proc=subprocess.run(['git','cat-file','--batch'],cwd=ROOT,env=env,input=b''.join((':'+p+'\n').encode() for p in names),capture_output=True,check=True)
data=proc.stdout;offset=0;mapping=[]
for path in names:
    end=data.index(b'\n',offset);header=data[offset:end].split();assert len(header)==3 and header[1]==b'blob',path
    size=int(header[2]);raw=data[end+1:end+1+size];offset=end+size+2
    tested=(ROOT/path).read_bytes()
    mode='exact' if raw==tested else 'CRLF-only' if raw.replace(b'\r\n',b'\n')==tested.replace(b'\r\n',b'\n') else 'MISMATCH'
    assert mode!='MISMATCH',path
    mapping.append({'path':path,'tested_sha256':sha(tested),'git_blob_sha256':sha(raw),'match':mode})
write(DEST/'GIT_TESTED_SOURCE_MAP.json',{'source_content_sha256':source['content_set_sha256'],'files':mapping,'exact':sum(x['match']=='exact' for x in mapping),'crlf_only':sum(x['match']=='CRLF-only' for x in mapping),'mismatch':0})
for name in ('source_review.diff','source_review.stat','source_review_check.log'):
    (DEST/name).write_bytes((OWNED/name).read_bytes())

owned_docs=[ROOT/'docs/source176_r3/CHILD_CHAIN_PLAN_20261004.md',ROOT/'docs/source176_r3/STATE_LOAN_WORKLOG_20261004.md',ROOT/'docs/source176_r3/FRAMEWORK_PUBLICATION_CLOSURE_PLAN.md',ROOT/'docs/source176_r3/PERIODIC_CHILD_CHAIN_PLAN_20261004.md']
index_lines=[]
for p in sorted([p for p in DEST.rglob('*') if p.is_file()]+owned_docs):
    relative=p.relative_to(ROOT).as_posix()
    blob=git('hash-object','-w','--stdin',input=p.read_bytes()).decode().strip()
    index_lines.append(('100644 '+blob+'\t'+relative+'\n').encode())
git('update-index','--index-info',input=b''.join(index_lines))
check=subprocess.run(['git','diff','--cached','--check',PARENT],cwd=ROOT,env=env,capture_output=True)
(OWNED/'full_review_check.log').write_bytes(check.stdout+check.stderr)
crlf_check=subprocess.run(['git','-c','core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol','diff','--cached','--check',PARENT],cwd=ROOT,env=env,capture_output=True)
(OWNED/'full_review_check_crlf.log').write_bytes(crlf_check.stdout+crlf_check.stderr)
warning_paths=set(re.findall(r'^(.+?):\d+: ',crlf_check.stdout.decode('utf-8'),re.M))
raw_allowed={str(DEST.relative_to(ROOT)).replace('\\','/')+'/'+p for p in ['audit_parent_800cca3c/PRO_REPORT.md','audit_parent_800cca3c/DOT_REPORT.md','source_review.diff','BOOTSTRAP_CONTINUE.txt']}
raw_allowed.update(DEST.relative_to(ROOT).as_posix()+'/'+item['archive_path'] for item in native['files'] if item['archive_path'].endswith('.log'))
assert not warning_paths-raw_allowed,sorted(warning_paths-raw_allowed)
source_check=subprocess.run(['git','diff','--cached','--check',PARENT,'--','scripts','tests','assets/data'],cwd=ROOT,env=env,capture_output=True)
assert source_check.returncode==0,source_check.stdout.decode()
write(DEST/'DIFF_CHECK_BOUNDARY.json',{'default_full_check_exit':check.returncode,'crlf_aware_full_check_exit':crlf_check.returncode,'source_check_exit':0,'raw_evidence_warning_paths':sorted(warning_paths),'handling':'Preserve original audit whitespace, truncated failed-engine stdout and literal patch context. These are reviewed original evidence bytes, not source whitespace. Full check FAIL remains recorded; source gate PASS.'})
boundary_doc=DEST/'DIFF_CHECK_BOUNDARY.json';relative=boundary_doc.relative_to(ROOT).as_posix()
blob=git('hash-object','-w','--stdin',input=boundary_doc.read_bytes()).decode().strip()
git('update-index','--add','--cacheinfo','100644,'+blob+','+relative)
changed=git('diff','--cached','--name-only',PARENT).decode().splitlines()
allowed=set(json.loads((OWNED/'source_delta_paths.json').read_text()))|{p.relative_to(ROOT).as_posix() for p in owned_docs}
assert all(p in allowed or p.startswith(DEST.relative_to(ROOT).as_posix()+'/') for p in changed)
(OWNED/'full_review.stat').write_bytes(git('diff','--cached','--stat',PARENT))
write(OWNED/'PUBLICATION_PREFLIGHT.json',{'time_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'paths':changed,'source_checks':'PASS','full_diff_check_exit':check.returncode,'real_index_sha256':sha(Path(boundary['index']).read_bytes()),'source_map_exact':sum(x['match']=='exact' for x in mapping),'source_map_crlf_only':sum(x['match']=='CRLF-only' for x in mapping)})
tree=git('write-tree').decode().strip()
commit=git('commit-tree',tree,'-p',PARENT,input=b'Return origin state loans across finite child-chain lifetimes\n\nReserve resident state storage separately from cumulative work, preserve shared root and historical credit ownership, and retain old-life/clear native counterexamples. Periodic child production and complete framework/APK remain open.\n').decode().strip()
git('update-ref',BRANCH,commit,PARENT)
assert sha(Path(boundary['index']).read_bytes())==boundary['actual_sha256']
write(OWNED/'PUBLICATION.json',{'commit':commit,'parent':PARENT,'tree':tree,'source_content_sha256':source['content_set_sha256'],'scope':'Returned origin-owned state loans reserve N*S resident storage for supported direct/child finite chains, while keeping original cumulative facts/receipts/child frontier unchanged. Invalid old-life states return one loan only to a live origin before accepted new-life work needs it; shared refresh roots and original source/credit remain held until terminal. Controlled real HP/life/refresh/clear and real Player windup/Root planner/late-life child API probes are separate evidence scopes. Periodic fact/death-child compiler remains closed. Full Task3-5/natural P6R3/framework/APK remain NOT_RUN.'})
print(json.dumps({'status':'PASS','commit':commit,'tree':tree,'paths':len(changed),'source_map_files':len(mapping)}))
