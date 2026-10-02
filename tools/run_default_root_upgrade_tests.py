"""Seed owned user data before native autoload, then execute live/cold tests."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, uuid

root = Path(__file__).resolve().parents[1]
fixture = root/'tests/framework/fixtures/default_root_upgrade_seed.json'
source = json.loads(fixture.read_text(encoding='utf-8-sig'))
assert source['schema_version'] == 1
parser = argparse.ArgumentParser()
parser.add_argument('--archived',action='store_true')
args = parser.parse_args()
reference = root/'outputs/framework_v2/mobile_v90_reference'
archive_path = Path('D:/HardCoreAudit/hardcore_save_backup_v90_20260922.tar')
if args.archived:
    source = json.loads((root/'outputs/framework_v2/mobile_v90_reference.json').read_text(encoding='utf-8-sig'))
    assert hashlib.sha256(archive_path.read_bytes()).hexdigest() == source['archive_sha256']
case = root/'.godot/runtime_appdata'/('default_root_existing_'+uuid.uuid4().hex)
case.mkdir(exist_ok=False)
user = case/'Godot/app_userdata/HardCore'
user.mkdir(parents=True)
originals = {}
for relative,document in source['files'].items():
    target = (user/relative).resolve()
    assert target.is_relative_to(user.resolve()) and not target.exists()
    target.parent.mkdir(parents=True,exist_ok=True)
    if args.archived:
        original = (reference/relative).resolve()
        assert original.is_relative_to(reference.resolve())
        raw = original.read_bytes()
        assert hashlib.sha256(raw).hexdigest() == document
    else:
        raw = (json.dumps(document,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    target.write_bytes(raw)
    originals[relative] = hashlib.sha256(raw).hexdigest()
fingerprint = {'fixture_sha256':hashlib.sha256(fixture.read_bytes()).hexdigest(),'files':originals}
if args.archived:
    fingerprint['archive_sha256'] = source['archive_sha256']
(user/'default_root_upgrade_seed_fingerprint.json').write_text(json.dumps(fingerprint,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
env = os.environ.copy()
env['HARDCORE_AUDIT_RUNTIME_APPDATA'] = str(case)
print(json.dumps({'isolated_appdata':str(case),'files':originals,'fixture_sha256':fingerprint['fixture_sha256']},ensure_ascii=False),flush=True)
kind = 'archived' if args.archived else 'existing'
result = subprocess.run(['py','-3.12','-X','utf8','tools/source176_r3_validation.py','default_root_'+kind+'_prelaunch',
    '--tests','tests/framework/default_root_upgrade_'+kind+'_test.tscn','tests/framework/default_root_upgrade_'+kind+'_cold_test.tscn','--timeout','30'],cwd=root,env=env)
if args.archived:
    assert hashlib.sha256(archive_path.read_bytes()).hexdigest() == source['archive_sha256']
    for relative,digest in source['files'].items(): assert hashlib.sha256((reference/relative).read_bytes()).hexdigest() == digest
    print('ORIGINAL_ARCHIVE_AND_13_REFERENCE_FILES_UNCHANGED',flush=True)
raise SystemExit(result.returncode)
