"""Freeze bounded, local v95 repair evidence without copying player saves."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[2]
logs = root / 'outputs/test_logs'
dest = Path(__file__).parent / 'evidence'
dest.mkdir(exist_ok=True)
latest, failures = {}, []
for path in sorted(logs.glob('runner_results_adhoc_20260929_*.json')):
    data = json.loads(path.read_text(encoding='utf-8-sig'))
    shutil.copyfile(path, dest / path.name)
    for row in data['results']:
        latest[row['test_path']] = dict(row, runner=path.name)
        if row['result'] != 'PASS': failures.append(dict(row, runner=path.name))
for row in latest.values():
    for suffix in ['.stdout.log', '.stderr.log', '.godot.log']:
        path = logs / (row['test_name'] + suffix)
        if path.exists(): shutil.copyfile(path, dest / path.name)
shutil.copyfile(logs / 'skill_descriptions_verified.json', dest / 'skill_descriptions_verified.json')
source_paths = subprocess.check_output(['git', 'diff', 'HEAD', '--name-only'], cwd=root).decode().splitlines()
source_paths += ['scripts/skills/skill_player_description.gd']
source_hashes = {}
for name in sorted(set(source_paths)):
    if name in ['AGENTS.md', 'tests/cangyue_area_test.gd']: continue
    source_hashes[name] = hashlib.sha256((root / name).read_bytes().replace(b'\r\n', b'\n')).hexdigest()
summary = {'source_base': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root).decode().strip(),
           'evidence_identity': 'working files, LF-normalized SHA256 below; runner HEAD is pre-commit baseline',
           'latest_test_count': len(latest), 'latest_failures': [r for r in latest.values() if r['result'] != 'PASS'],
           'latest_results': list(latest.values()), 'historical_failed_runs': failures,
           'source_hashes_lf': source_hashes, 'device_test_new_apk': 'NOT_RUN'}
(dest / 'matrix.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'tests': len(latest), 'latest_failures': summary['latest_failures'], 'historical_failures': len(failures)}))
