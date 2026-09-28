"""Collect only this repair's runner results and latest logs, never player saves."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
DEST = Path(__file__).parent / 'evidence'
LOGS = ROOT / 'outputs/test_logs'
DEST.mkdir(exist_ok=True)
latest, failed = {}, []
for path in sorted(LOGS.glob('runner_results_adhoc_20260929_*.json')):
    if path.name < 'runner_results_adhoc_20260929_073711':
        continue
    data = json.loads(path.read_text(encoding='utf-8-sig'))
    (DEST / path.name).write_bytes(path.read_bytes())
    for row in data['results']:
        latest[row['test_path']] = dict(row, runner=path.name)
        if row['result'] != 'PASS':
            failed.append(dict(row, runner=path.name))
for row in latest.values():
    for suffix in ['.stdout.log', '.stderr.log', '.godot.log']:
        path = LOGS / (row['test_name'] + suffix)
        if path.exists():
            content = path.read_bytes().rstrip(b'\r\n')
            (DEST / path.name).write_bytes(content + b'\n' if content else b'')
paths = ['scripts/layers/rules/equipment_enhancement_rules.gd', 'scripts/shop_panel.gd',
         'tests/forge_persistence_roundtrip_test.gd', 'tests/new_item_icon_surfaces_test.gd',
         'tools/run_godot_tests.ps1']
summary = {
    'source_base': '353347ffc5891f1000d86b4ab804ee1e7bd72fd9',
    'head_at_collection': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT).decode().strip(),
    'source_identity': 'LF-normalized hashes below; pre-commit runners identify baseline HEAD',
    'latest_test_count': len(latest),
    'latest_failures': [r for r in latest.values() if r['result'] != 'PASS'],
    'latest_results': list(latest.values()), 'historical_failures': failed,
    'source_hashes_lf': {p: hashlib.sha256((ROOT / p).read_bytes().replace(b'\r\n', b'\n')).hexdigest() for p in paths},
    'device_test': 'NOT_RUN',
}
(DEST / 'matrix.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'tests': len(latest), 'failures': len(summary['latest_failures']), 'prior_failed_runs': len(failed)}))
