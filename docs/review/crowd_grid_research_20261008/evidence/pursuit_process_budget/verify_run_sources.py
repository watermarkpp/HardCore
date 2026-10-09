from pathlib import Path
import hashlib
import json
import sys

root = Path('C:/Users/Administrator/.codex/worktrees/crowd-attack-frame-ab/HardCore')
out = Path('C:/Users/Administrator/Documents/HardCore/outputs/crowd_ai_frequency_ab_20261009')
stage = sys.argv[1]
assert '/' not in stage and '\\' not in stage
target = out / stage
assert not (target / 'POST_RUN.json').exists(), 'refuse overwrite source audit'
manifest = json.loads((target / 'INPUTS.json').read_text(encoding='utf-8'))
changed = []
for path, expected in manifest['source_sha256'].items():
    actual = hashlib.sha256((root / path).read_bytes()).hexdigest()
    if actual != expected:
        changed.append({'path': path, 'expected': expected, 'actual': actual})
result = {'status': 'PASS' if not changed else 'FAIL', 'producer_id': manifest['producer_id'],
          'scope': 'post-run equality of all preloaded source/import bindings; not gameplay or performance acceptance',
          'source_files': len(manifest['source_sha256']), 'changed': changed}
(target / 'POST_RUN.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result))
sys.exit(1 if changed else 0)
