from pathlib import Path
import hashlib
import json
import sys
import uuid

main = Path('C:/Users/Administrator/Documents/HardCore')
root = Path('C:/Users/Administrator/.codex/worktrees/crowd-attack-frame-ab/HardCore')
out = main / 'outputs/crowd_ai_frequency_ab_20261009'
stage, mode = sys.argv[1:3]
assert mode in ('immediate', 'budgeted')
assert stage.startswith(mode + '_') and '/' not in stage and '\\' not in stage
target = out / stage
assert not target.exists(), 'refuse overwrite prior evidence'
previous = json.loads((main / 'outputs/crowd_attack_frame_ab_20261009/immediate_06/INPUTS.json').read_text(encoding='utf-8'))
paths = set(previous['source_sha256'])
paths.update(['scripts/monster_ai_package/decision_budget.gd',
              'scripts/layers/runtime/execution/frame_budget.gd',
              'tests/crowd_pursuit_process_budget_ab_20261009.gd',
              'tests/crowd_pursuit_process_budget_ab_20261009.tscn'])

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

assert all((root / p).is_file() for p in paths)
hashes = {p: sha(root / p) for p in sorted(paths)}
manifest = {key: previous[key] for key in ('baseline_head', 'main_head', 'engine_path',
    'engine_console_path', 'engine_sha256', 'engine_console_sha256')}
assert sha(Path(manifest['engine_path'])) == manifest['engine_sha256']
assert sha(Path(manifest['engine_console_path'])) == manifest['engine_console_sha256']
scene = 'tests/crowd_pursuit_process_budget_ab_20261009.tscn'
manifest.update({
    'schema': 'hardcore.pursuit_process_budget.inputs.v1',
    'producer_id': str(uuid.uuid4()), 'stage': stage, 'mode': 'immediate',
    'pursuit_mode': mode, 'source_sha256': hashes,
    'command': f'tools/run_godot_tests.ps1 -TestPaths {scene} -TimeoutSeconds 60',
    'environment': {
        'HARDCORE_AUDIT_LOG_ROOT': str(target / 'native_logs'),
        'HARDCORE_ATTACK_AB_EVIDENCE_ROOT': str(target),
        'HARDCORE_ATTACK_AB_MODE': 'immediate',
        'HARDCORE_PURSUIT_PROCESS_BUDGET_MODE': mode,
        'HARDCORE_SCALING_ENGAGED': '30',
        'HARDCORE_GRID_COMPARISON_MODE': 'current',
        'HARDCORE_GRID_COMPARISON_RUN_ID': stage,
    },
    'scope': 'Paired policy test of due observation and new pursuit-step planning. Existing actual motion, collisions, committed attack and struck continue. Changed AI service can alter trajectories and attack output: record that tradeoff separately from CPU.',
    'run_reason': 'First native same-source comparison for this narrower planning gate; earlier attack admission and passive diagnostic do not answer this policy question.',
})
target.mkdir()
for p in sorted(paths):
    dest = target / 'source_snapshot' / p
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes((root / p).read_bytes())
data = json.dumps(manifest, indent=2)
(target / 'INPUTS.json').write_text(data, encoding='utf-8')
binding = root / 'outputs/crowd_attack_frame_ab_20261009/current_run_inputs.json'
binding.parent.mkdir(parents=True, exist_ok=True)
binding.write_text(data, encoding='utf-8')
print(json.dumps({'stage': stage, 'producer_id': manifest['producer_id'],
    'source_files': len(hashes), 'enemy_sha256': hashes['scripts/enemy.gd']}))
