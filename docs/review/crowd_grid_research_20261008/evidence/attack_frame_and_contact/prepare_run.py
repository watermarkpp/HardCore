from pathlib import Path
import hashlib, json, subprocess, sys, uuid

main = Path('C:/Users/Administrator/Documents/HardCore')
root = Path('C:/Users/Administrator/.codex/worktrees/crowd-attack-frame-ab/HardCore')
out = main / 'outputs/crowd_attack_frame_ab_20261009'
stage, mode = sys.argv[1:3]
assert mode in ('immediate', 'queued')
target = out / stage
assert not target.exists(), 'refuse overwrite prior evidence'
prep = json.loads((out / 'BASELINE_SNAPSHOT.json').read_text(encoding='utf-8'))
paths = {item['path'] for item in prep['overlay']}
paths.update(item['path'] for item in prep['dependencies'])
imports = out / 'ASSET_IMPORT_METADATA.json'
if imports.is_file():
    paths.update(item['path'] for item in json.loads(imports.read_text(encoding='utf-8'))['paths'])
paths.update([
    'assets/data/equipment_granted_skills.source.json',
    'scripts/layers/runtime/execution/frame_budget.gd',
    'scripts/monster_ai_package/policy.gd', 'scripts/world_background.gd',
    'tests/crowd_attack_start_frame_ab_20261009.gd',
    'tests/crowd_attack_start_frame_ab_20261009.tscn',
    'tests/support/attack_start_frame_probe_20261009.gd',
    'tests/world_crowd_firewall_profile_test.gd', 'tools/run_godot_tests.ps1',
])
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
assert all((root / p).is_file() for p in paths), 'source dependency missing'
target.mkdir(parents=True)
hashes = {p: sha(root / p) for p in sorted(paths)}
for path in sorted(paths):
    dest = target / 'source_snapshot' / path
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes((root / path).read_bytes())
scene = 'tests/crowd_attack_start_frame_ab_20261009.tscn'
env = {
    'HARDCORE_AUDIT_LOG_ROOT': str(target / 'native_logs'),
    'HARDCORE_ATTACK_AB_EVIDENCE_ROOT': str(target),
    'HARDCORE_ATTACK_AB_MODE': mode,
    'HARDCORE_SCALING_ENGAGED': '30',
    'HARDCORE_GRID_COMPARISON_MODE': 'current',
    'HARDCORE_GRID_COMPARISON_RUN_ID': stage,
}
manifest = {
    'schema': 'hardcore.attack_start_frame_ab.inputs.v1',
    'producer_id': str(uuid.uuid4()), 'stage': stage, 'mode': mode,
    'baseline_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'main_head': prep['main_head'], 'source_sha256': hashes,
    'engine_path': str(root / 'tools/godot-4.7/Godot_v4.7-stable_win64.exe'),
    'engine_console_path': str(root / 'tools/godot-4.7/Godot_v4.7-stable_win64_console.exe'),
    'engine_sha256': sha(root / 'tools/godot-4.7/Godot_v4.7-stable_win64.exe'),
    'engine_console_sha256': sha(root / 'tools/godot-4.7/Godot_v4.7-stable_win64_console.exe'),
    'command': f'tools/run_godot_tests.ps1 -TestPaths {scene} -TimeoutSeconds 60',
    'environment': env,
    'scope': 'current accepted behavior source plus throwaway admission probe; policy comparison, not fixed107 equivalent-work acceptance or device FPS proof',
}
text = json.dumps(manifest, indent=2)
(target / 'INPUTS.json').write_text(text, encoding='utf-8')
current = root / 'outputs/crowd_attack_frame_ab_20261009/current_run_inputs.json'
current.parent.mkdir(parents=True, exist_ok=True)
current.write_text(text, encoding='utf-8')
print(json.dumps({'stage': stage, 'mode': mode, 'producer_id': manifest['producer_id'], 'source_files': len(hashes), 'enemy_sha256': hashes['scripts/enemy.gd']}))
