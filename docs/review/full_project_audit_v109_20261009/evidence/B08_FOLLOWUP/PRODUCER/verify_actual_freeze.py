import hashlib
import json
from pathlib import Path
import sys

freeze_path = Path(sys.argv[1])
record = json.loads(freeze_path.read_text(encoding='utf-8-sig'))
changed = []
for item in record['files']:
    path = Path(item['path'])
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
        changed.append(item['path'])
engine = record['engine']
engine_valid = hashlib.sha256(Path(engine['path']).read_bytes()).hexdigest() == engine['sha256']
index = hashlib.sha256(Path('.git/index').read_bytes()).hexdigest()
result = {'status': 'PASS' if not changed and engine_valid and index == record['main_index_sha256'] else 'FAIL',
          'freeze': str(freeze_path), 'freeze_sha256': hashlib.sha256(freeze_path.read_bytes()).hexdigest(),
          'files': len(record['files']), 'changed_inputs': changed, 'engine_unchanged': engine_valid,
          'main_index_sha256': index, 'scope': 'Actual bytes unchanged before/after native execution; not business-test acceptance'}
output = freeze_path.with_name(freeze_path.stem + '_POSTVERIFY.json')
output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
assert result['status'] == 'PASS'
