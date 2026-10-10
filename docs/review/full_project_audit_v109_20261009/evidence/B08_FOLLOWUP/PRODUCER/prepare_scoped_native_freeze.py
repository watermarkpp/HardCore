"""Private-index runtime freeze; explicit spec, no main-index mutation."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path.cwd()
out = root / 'outputs/wake_drop_v108_review_followup_20261009'
spec = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
name = spec['name']
assert name.replace('_', '').isalnum()
main_index = root / '.git/index'
index_before = hashlib.sha256(main_index.read_bytes()).hexdigest()
assert index_before == 'ddacea4eed570faed0a6003c87352552e74e902874b5dee61d8863a2316e29d7'
parent = subprocess.check_output(['git', 'rev-parse', 'refs/heads/codex/v108-runtime-bug-review-20261009']).decode().strip()
env = os.environ.copy()
env['GIT_INDEX_FILE'] = str(out / (name + '.index'))
subprocess.check_call(['git', 'read-tree', parent], env=env)
paths = spec['changed_paths']
for path in paths:
    assert not Path(path).is_absolute() and '..' not in Path(path).parts
    data = (root / path).read_bytes().replace(b'\r\n', b'\n')
    blob = subprocess.check_output(['git', 'hash-object', '-w', '--no-filters', '--stdin'], input=data).decode().strip()
    subprocess.check_call(['git', 'update-index', '--add', '--cacheinfo', '100644,' + blob + ',' + path], env=env)
tree = subprocess.check_output(['git', 'write-tree'], env=env).decode().strip()
prior = json.loads((out / 'B07A_INTEGRATION_NATIVE_FREEZE_52.json').read_text(encoding='utf-8-sig'))
files = {item['path'] for item in prior['files']}
files.update(paths)
files.update(spec['additional_inputs'])
engine = prior['engine']
assert hashlib.sha256(Path(engine['path']).read_bytes()).hexdigest() == engine['sha256']
record = {
    'parent': parent, 'candidate_tree': tree, 'private_index': env['GIT_INDEX_FILE'],
    'changed_paths': paths, 'scenes': spec['scenes'], 'engine': engine,
    'fingerprint_scope': spec['fingerprint_scope'], 'rerun_reason': spec['rerun_reason'],
    'files': [], 'main_index_sha256': index_before,
}
for path in sorted(files):
    data = (root / path).read_bytes()
    record['files'].append({'path': path, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)})
payload = (json.dumps(record, indent=2, ensure_ascii=False) + '\n').encode('utf-8')
(out / (name + '.json')).write_bytes(payload)
assert hashlib.sha256(main_index.read_bytes()).hexdigest() == index_before
print(json.dumps({'tree': tree, 'fingerprint': hashlib.sha256(payload).hexdigest(),
                 'index': env['GIT_INDEX_FILE'], 'files': len(files), 'scenes': spec['scenes']}, indent=2))
