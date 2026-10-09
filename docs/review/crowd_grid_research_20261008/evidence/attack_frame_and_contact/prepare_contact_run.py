from pathlib import Path
import hashlib, json, subprocess, sys, uuid

main = Path('C:/Users/Administrator/Documents/HardCore')
root = Path('C:/Users/Administrator/.codex/worktrees/crowd-attack-frame-ab/HardCore')
out = main / 'outputs/crowd_attack_frame_ab_20261009'
stage = sys.argv[1]
assert stage.startswith('contact_diagnostic_') and '/' not in stage and '\\' not in stage
target = out / stage
assert not target.exists(), 'refuse overwrite prior evidence'
previous = json.loads((out / 'immediate_06/INPUTS.json').read_text(encoding='utf-8'))
paths = set(previous['source_sha256'])
paths.update(['tests/crowd_attack_contact_diagnostic_20261009.gd',
              'tests/crowd_attack_contact_diagnostic_20261009.tscn'])

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

assert all((root / p).is_file() for p in paths)
target.mkdir()
hashes = {p: sha(root / p) for p in sorted(paths)}
for p in sorted(paths):
    dest = target / 'source_snapshot' / p
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes((root / p).read_bytes())
scene = 'tests/crowd_attack_contact_diagnostic_20261009.tscn'
manifest = {key: previous[key] for key in ['baseline_head', 'main_head', 'engine_path',
    'engine_console_path', 'engine_sha256', 'engine_console_sha256']}
assert sha(Path(manifest['engine_path'])) == manifest['engine_sha256']
assert sha(Path(manifest['engine_console_path'])) == manifest['engine_console_sha256']
manifest.update({
    'schema': 'hardcore.contact_check_diagnostic.inputs.v1',
    'producer_id': str(uuid.uuid4()), 'stage': stage, 'mode': 'immediate',
    'source_sha256': hashes,
    'command': f'tools/run_godot_tests.ps1 -TestPaths {scene} -TimeoutSeconds 60',
    'environment': {
        'HARDCORE_AUDIT_LOG_ROOT': str(target / 'native_logs'),
        'HARDCORE_ATTACK_AB_EVIDENCE_ROOT': str(target),
        'HARDCORE_ATTACK_AB_MODE': 'immediate',
        'HARDCORE_SCALING_ENGAGED': '30',
        'HARDCORE_GRID_COMPARISON_MODE': 'current',
        'HARDCORE_GRID_COMPARISON_RUN_ID': stage,
    },
    'scope': 'new pure contact-check diagnostic, no algorithm or AI cadence changes; nested timings not additive; not performance acceptance or device FPS',
    'run_reason': 'MISSING call/result/cooldown cost attribution for eligibility and passive-contact hypothesis; prior attack-admission comparison does not measure these checks',
})
data = json.dumps(manifest, indent=2)
(target / 'INPUTS.json').write_text(data, encoding='utf-8')
(root / 'outputs/crowd_attack_frame_ab_20261009/current_run_inputs.json').write_text(data, encoding='utf-8')
print(json.dumps({'stage': stage, 'producer_id': manifest['producer_id'],
    'source_files': len(hashes), 'enemy_sha256': hashes['scripts/enemy.gd']}))
