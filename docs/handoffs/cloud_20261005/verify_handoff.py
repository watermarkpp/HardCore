"""Verify the handed-off raw source and evidence bytes without editing files."""
from pathlib import Path
import hashlib, json, zipfile, sys
root=Path(__file__).resolve().parents[3]
folder=Path(__file__).resolve().parent
source=json.loads((folder/'TESTED_SOURCE_MANIFEST.json').read_text(encoding='utf-8'))
fail=[]
for rel,expected in source['files'].items():
    p=root/rel
    if not p.is_file(): fail.append((rel,'MISSING')); continue
    actual=hashlib.sha256(p.read_bytes()).hexdigest()
    if actual!=expected: fail.append((rel,'SHA256_MISMATCH'))
evidence=json.loads((folder/'EVIDENCE_MANIFEST.json').read_text(encoding='utf-8'))
archive=folder/'LOCAL_EVIDENCE.zip'
if hashlib.sha256(archive.read_bytes()).hexdigest()!=evidence['zip_sha256']: fail.append(('LOCAL_EVIDENCE.zip','SHA256_MISMATCH'))
with zipfile.ZipFile(archive) as z:
    if set(z.namelist())!={x['path'] for x in evidence['members']}: fail.append(('ZIP_MEMBER_SET','FAIL'))
    for row in evidence['members']:
        b=z.read(row['path'])
        if len(b)!=row['size'] or hashlib.sha256(b).hexdigest()!=row['sha256']: fail.append((row['path'],'EVIDENCE_MISMATCH'))
print(json.dumps({'status':'FAIL' if fail else 'PASS','source_files':len(source['files']),'source_content_sha256':source['source_content_sha256'],'evidence_members':len(evidence['members']),'failures':fail},ensure_ascii=False,indent=2))
sys.exit(bool(fail))
