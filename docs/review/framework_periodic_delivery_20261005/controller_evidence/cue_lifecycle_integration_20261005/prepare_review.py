"""Archive explicitly owned evidence and prepare a review-only Git index."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, os, shutil, subprocess, zipfile

ROOT = Path.cwd()
assert ROOT == Path('C:/Users/Administrator/.codex/worktrees/pluggable-framework-v2/HardCore')
OWN = ROOT / 'outputs/framework_v2/cue_lifecycle_integration_20261005'
DEST = ROOT / 'docs/review/framework_periodic_delivery_20261005'
BASE = ROOT / 'outputs/r3_takeover/20260930/validation'
PARENT = '2c58552d2d905eea1f5c13d38685f66c489b092c'
BRANCH = 'refs/heads/codex/framework-layered-critical-20261003'
FINAL = ['periodic_cue_final_world_013906_604728',
         'periodic_cue_final_mixed_service_014147_190573',
         'periodic_cue_final_related_014327_801663']
PREFIXES = ('periodic_dispatch_', 'accepted_binding_', 'cue_integration_', 'periodic_cue_final_')
TRUE_INDEX = Path('C:/Users/Administrator/Documents/HardCore/.git/worktrees/HardCore/index')
INDEX_SHA = 'df5a01dd0d87c14620e0021d70c25a830eb2cc37aa7b012eeb14ee1f2c58c5fb'
env = os.environ.copy()
env['GIT_OPTIONAL_LOCKS'] = '0'
env['GIT_INDEX_FILE'] = str(OWN / 'publication.index')

def sha(raw): return hashlib.sha256(raw).hexdigest()
def load(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
def git(*args, data=None, cwd=ROOT, alternate=True):
    run_env = env.copy()
    if not alternate: run_env.pop('GIT_INDEX_FILE', None)
    return subprocess.check_output(['git', *args], input=data, cwd=cwd, env=run_env)
def protected_state(path):
    index = Path(git('rev-parse', '--git-path', 'index', cwd=path, alternate=False).decode().strip())
    if not index.is_absolute(): index = path / index
    status = git('status', '--short', cwd=path, alternate=False)
    return {'head': git('rev-parse', 'HEAD', cwd=path, alternate=False).decode().strip(),
            'branch': git('branch', '--show-current', cwd=path, alternate=False).decode().strip(),
            'index_sha256': sha(index.read_bytes()), 'status_sha256': sha(status),
            'dirty_count': len(status.splitlines())}

assert sha(TRUE_INDEX.read_bytes()) == INDEX_SHA
assert git('rev-parse', BRANCH).decode().strip() == PARENT
assert not DEST.exists(), 'Never overwrite a previously archived review'
checkpoint = load(OWN / 'FINAL_ASSOCIATIONS.json')
assert checkpoint['status'] == 'PASS' and checkpoint['scene_count'] == 39 and checkpoint['complete_checks'] == 2138
source = load(BASE / FINAL[0] / 'before.json')
assert source['content_set_sha256'] == checkpoint['source_content_sha256']
assert len(source['files']) == 3785
for path, expected in source['files'].items(): assert sha((ROOT / path).read_bytes()) == expected, path
self_review = load(ROOT / 'outputs/framework_v2/periodic_dispatch_20261004/SELF_REVIEW_INPUT.json')
assert self_review['base'] == PARENT and self_review['diff_check'] == 'PASS'
owned_paths = [row['path'] for row in self_review['paths']]
assert len(owned_paths) == 52
for row in self_review['paths']: assert sha((ROOT / row['path']).read_bytes()) == row['sha256'], row['path']
git('read-tree', PARENT)
git('add', '--', *owned_paths)
git('diff', '--cached', '--check', PARENT)

names = sorted(source['files'])
raw_git = git('cat-file', '--batch', data=''.join(':' + p + '\n' for p in names).encode())
offset, mapping = 0, []
for path in names:
    end = raw_git.index(b'\n', offset)
    header = raw_git[offset:end].split()
    assert len(header) == 3 and header[1] == b'blob', ('missing source in review tree', path, header)
    size = int(header[2]); raw = raw_git[end+1:end+1+size]; offset = end+size+2
    tested = (ROOT / path).read_bytes()
    mode = 'exact' if raw == tested else 'CRLF-only' if raw.replace(b'\r\n', b'\n') == tested.replace(b'\r\n', b'\n') else 'MISMATCH'
    assert mode != 'MISMATCH', ('unowned runtime difference', path)
    mapping.append({'path': path, 'tested_sha256': sha(tested), 'git_blob_sha256': sha(raw), 'match': mode})

prior = json.loads(git('show', PARENT + ':docs/review/framework_state_loans_20261004/SOURCE_MANIFEST.json'))
assert not set(prior['files']) - set(source['files'])
delta = [{'path': path, 'before_sha256': prior['files'].get(path), 'after_sha256': digest}
         for path, digest in source['files'].items() if digest != prior['files'].get(path)]
assert all(row['path'] in owned_paths for row in delta), ('unowned source delta', delta)
DEST.mkdir(parents=True)
write(DEST / 'SOURCE_MANIFEST.json', source)
write(DEST / 'SOURCE_DELTA.json', {'parent': PARENT, 'source_content_sha256': source['content_set_sha256'], 'delta': delta})
write(DEST / 'GIT_TESTED_SOURCE_MAP.json', {'source_content_sha256': source['content_set_sha256'],
      'files': mapping, 'exact': sum(row['match'] == 'exact' for row in mapping),
      'crlf_only': sum(row['match'] == 'CRLF-only' for row in mapping), 'mismatch': 0})

records, native_files, failures, rejected = [], [], [], []
def archive_file(original, target):
    assert original.is_file()
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(original, target)
    native_files.append({'original_path': original.relative_to(ROOT).as_posix(),
                         'archive_path': target.relative_to(DEST).as_posix(),
                         'bytes': target.stat().st_size, 'sha256': sha(target.read_bytes())})

for batch in sorted(path for path in BASE.iterdir() if path.is_dir() and path.name.startswith(PREFIXES)):
    if not (batch / 'validation.json').is_file():
        rejected.append({'batch': batch.name, 'status': 'MISSING', 'reason': 'No terminal validation record; not adopted.'})
        continue
    before, after, validation = [load(batch / name) for name in ('before.json', 'after.json', 'validation.json')]
    files = [batch / name for name in ('before.json', 'after.json', 'validation.json', 'runner.log')]
    rows = []
    if (batch / 'runner_results.json').is_file():
        report = load(batch / 'runner_results.json')
        files.append(batch / 'runner_results.json')
        for native in report['results']:
            scene = native['test_name']
            receipt_path = batch / 'framework' / (scene + '.result.json')
            receipt = load(receipt_path) if receipt_path.is_file() else None
            matches = bool(receipt and receipt.get('run_id') == native.get('framework_run_id')
                           and receipt.get('invocation_id') == report['invocation_id']
                           and receipt.get('source_content_sha256') == before['content_set_sha256'])
            if matches:
                assert receipt['count'] == len(receipt['checks']) == receipt['passed'] + receipt['failed']
                assert sum(not item['passed'] for item in receipt['checks']) == receipt['failed']
                files.append(receipt_path)
            item = {'batch': batch.name, 'test_path': native['test_path'], 'scene': scene,
                    'run_id': native.get('framework_run_id'), 'invocation_id': report['invocation_id'],
                    'source_content_sha256': before['content_set_sha256'], 'result': native['result'],
                    'native_exit': native['effective_exit_code'], 'timeout': native['timeout'],
                    'process_exited': native['process_exited'], 'reason': native.get('reason', ''),
                    'receipt_matches_invocation': matches, 'checks': receipt['count'] if matches else None,
                    'failed_checks': receipt['failed'] if matches else None,
                    'adopted_final': batch.name in FINAL}
            if native['result'] != 'PASS': failures.append(item)
            rows.append(item)
            for folder in ('raw', 'native_logs'):
                files.extend(path for path in (batch / folder).glob(scene + '.*.log') if path.is_file())
        files.extend(path for path in (batch / 'framework').glob('*.json') if path.is_file())
    else:
        assert validation['status'] == 'FAIL'
        rejected.append({'batch': batch.name, 'status': 'FAIL', 'reason': 'Wrapper rejected before runner results.',
                         'exit_code': validation['exit_code'], 'native_scenes_started': 0})
    files.extend(path for path in batch.glob('*.json') if path.name not in {'before.json', 'after.json', 'validation.json', 'runner_results.json'})
    for original in sorted(set(files)):
        if original.is_file(): archive_file(original, DEST / 'native' / batch.name / original.relative_to(batch))
    records.append({'batch': batch.name, 'status': validation['status'], 'command': validation['command'],
                    'timeout_seconds': validation['timeout_seconds'],
                    'source_content_sha256': before['content_set_sha256'],
                    'source_stable_during_run': validation['source_stable_during_run'], 'rows': rows})

adopted = [row for record in records for row in record['rows'] if row['adopted_final']]
assert len(adopted) == 39 and sum(row['checks'] for row in adopted) == 2138
assert all(row['result'] == 'PASS' and row['native_exit'] == 0 and not row['timeout'] for row in adopted)
write(DEST / 'RUN_INDEX.json', {'runs': records, 'final_adopted_rows': adopted,
      'preserved_failed_rows': failures, 'wrapper_or_terminal_rejections': rejected,
      'scope': 'All explicitly named periodic/acceptance/Cue batches are retained. Only the final three same-source batches are final evidence; wrapper-copied historical traces are excluded.'})
write(DEST / 'NATIVE_MANIFEST.json', {'files': native_files})

metadata_dirs = ['outputs/framework_v2/periodic_dispatch_20261004', 'outputs/framework_v2/feature_templates_20261004',
                 'outputs/framework_v2/mixed_delivery_20261004', 'outputs/framework_v2/cue_lifecycle_integration_20261005']
metadata = []
for directory in metadata_dirs:
    for original in sorted((ROOT / directory).rglob('*')):
        if not original.is_file() or original.suffix.lower() not in {'.json','.md','.py','.log','.gd','.tscn','.txt','.diff','.stat','.check','.status'}:
            continue
        if original.suffix.lower() == '.json' and original.stat().st_size > 2_000_000: continue
        target = DEST / 'controller_evidence' / original.relative_to(ROOT / 'outputs/framework_v2')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original, target)
        metadata.append({'archive_path': target.relative_to(DEST).as_posix(), 'bytes': target.stat().st_size,
                         'sha256': sha(target.read_bytes())})
write(DEST / 'CONTROLLER_EVIDENCE_MANIFEST.json', {'files': metadata})
for label, filename in [('source_review.diff', 'owned_source.diff'), ('source_review.stat','owned_source.stat'),
                        ('source_review_check.log', 'owned_source.check')]:
    shutil.copyfile(ROOT / 'outputs/framework_v2/periodic_dispatch_20261004' / filename, DEST / label)

prior_protection = load(ROOT / 'outputs/framework_v2/resource_consumption_20261004/BEFORE.json')['protected']
protection = {'read_utc': datetime.now(timezone.utc).isoformat()}
for name, path in [('main', Path('C:/Users/Administrator/Documents/HardCore')),
                   ('second', Path('C:/Users/Administrator/Documents/HardCore-worktrees/glm53-r1-20260929')),
                   ('third', ROOT)]:
    current = protected_state(path)
    assert current['head'] == prior_protection[name]['head'] and current['branch'] == prior_protection[name]['branch']
    if name != 'third':
        assert current['index_sha256'] == prior_protection[name]['index_sha256']
        assert current['status_sha256'] == prior_protection[name]['status_sha256']
    else: assert current['index_sha256'] == INDEX_SHA
    protection[name] = current
protection['frozen_streaming_sha256'] = sha((ROOT / 'scripts/monster_visual_streaming_coordinator.gd').read_bytes())
assert protection['frozen_streaming_sha256'] == '757da0597ab78aded642a98cf1e7433b9da06a6be5fb0684923ca6686282809d'
write(DEST / 'PROTECTION.json', protection)
write(DEST / 'INDEX_CONTINUITY_BOUNDARY.json', load(ROOT / 'outputs/framework_v2/resource_consumption_20261004/LIVE_INDEX_CHECK.json'))

media = []
for path in ['assets/art/items/service/inventory/client.classic_raw_complete/Items_00014.png',
             'assets/audio/sfx/client/137__M26-3.wav', 'assets/audio/sfx/client/10332__M33-3.wav']:
    raw = (ROOT / path).read_bytes()
    assert raw == git('show', PARENT + ':' + path)
    media.append({'path': path, 'bytes': len(raw), 'sha256': sha(raw)})
write(DEST / 'PRIMARY_RESOURCES.json', {'resources': media})
rfc = ROOT / 'docs/architecture/pluggable_framework/RFC_V2_USER_SOURCE_20260930.md'
assert sha(rfc.read_bytes()) == '4d4ddfac6b52e705ec91fb42dfc78f3cbec6a438b169a0a1932510b560664781'

with zipfile.ZipFile(DEST / 'TESTED_SOURCE.zip', 'x', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for path in source['files']: archive.write(ROOT / path, path)
    archive.write(rfc, rfc.relative_to(ROOT).as_posix())
    for row in media: archive.write(ROOT / row['path'], row['path'])
with zipfile.ZipFile(DEST / 'TESTED_SOURCE.zip') as archive:
    assert archive.testzip() is None
    for path, expected in source['files'].items(): assert sha(archive.read(path)) == expected
    for row in media: assert sha(archive.read(row['path'])) == row['sha256']
with zipfile.ZipFile(DEST / 'NATIVE_EVIDENCE.zip', 'x', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for row in native_files: archive.write(DEST / row['archive_path'], row['archive_path'])
with zipfile.ZipFile(DEST / 'NATIVE_EVIDENCE.zip') as archive:
    assert archive.testzip() is None
    for row in native_files:
        raw = archive.read(row['archive_path'])
        assert len(raw) == row['bytes'] and sha(raw) == row['sha256']

summary = {'status': 'PASS', 'parent': PARENT, 'construction_head': source['tested_sha'],
           'source_content_sha256': source['content_set_sha256'], 'source_files': len(source['files']),
           'source_delta_files': len(delta), 'explicit_owned_paths': len(owned_paths),
           'native_attempts': sum(len(record['rows']) for record in records), 'failed_native_attempts': len(failures),
           'wrapper_or_terminal_rejections': len(rejected), 'final_unique_scenes': 39, 'final_checks': 2138,
           'final_framework_receipts': 39, 'engine_version': source['engine_version'],
           'engine_console_sha256': source['engine_sha256'],
           'whole_framework_status': 'NOT_RUN', 'apk_status': 'NOT_RUN', 'device_status': 'NOT_RUN',
           'open': ['Production-reachable cumulative work and worst atomic quantum', 'Actual pool-reuse old callbacks and replacement Cue',
                    'Sustained natural P6/R3 and comparable full-combat performance', 'Formal map respawn policy FAIL',
                    'Original v97 B input MISSING', 'Exit resource diagnostics', 'Full power-loss/device/GPU/Android acceptance']}
for name in ('TESTED_SOURCE.zip', 'NATIVE_EVIDENCE.zip'):
    path = DEST / name
    assert path.stat().st_size < 95_000_000
    summary[name] = {'bytes': path.stat().st_size, 'sha256': sha(path.read_bytes())}
write(DEST / 'SCOPED_EVIDENCE.json', summary)
write(OWN / 'PREPARED_REVIEW.json', {'destination': DEST.relative_to(ROOT).as_posix(), 'parent': PARENT,
      'owned_paths': owned_paths, 'source_content_sha256': source['content_set_sha256'], 'summary': summary,
      'review_index': str(OWN / 'publication.index'), 'true_index_sha256': INDEX_SHA})
print(json.dumps(summary))
