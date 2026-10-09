from pathlib import Path
import hashlib,json,uuid,subprocess,sys
root=Path('C:/Users/Administrator/.codex/worktrees/crowd-v107-comparison/HardCore')
out=Path('C:/Users/Administrator/Documents/HardCore/outputs/crowd_no_plan_failure_audit_20261009')
stage=sys.argv[1]
target=out/stage
assert not target.exists(),'refuse overwrite evidence'
target.mkdir(parents=True)
sources=['scripts/enemy.gd','scripts/runtime_diagnostics.gd','scripts/game_root.gd','scripts/runtime_combat_spatial_index.gd','scripts/world_background.gd','scripts/monster_ai_package/policy.gd','tools/run_godot_tests.ps1','project.godot','tests/crowd_no_plan_failure_audit_20261009.gd','tests/crowd_no_plan_failure_audit_20261009.tscn','tests/support/no_plan_failure_audit_20261009.gd','tests/crowd_formal_grid_comparison_20261008.gd','tests/crowd_engagement_scaling_20261008.gd','tests/phone_crowd_baseline_20261008.gd']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
frozen={p:sha(root/p) for p in sources}
for p in sources:
    dest=target/'source_snapshot'/p
    dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_bytes((root/p).read_bytes())
scene='tests/crowd_no_plan_failure_audit_20261009.tscn'
manifest={'schema':'hardcore.no_plan_failure_audit.inputs.v1','baseline':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'producer_id':str(uuid.uuid4()),'stage':stage,'source_sha256':frozen,'engine_sha256':sha(root/'tools/godot-4.7/Godot_v4.7-stable_win64.exe'),'engine_console_sha256':sha(root/'tools/godot-4.7/Godot_v4.7-stable_win64_console.exe'),'command':f'tools/run_godot_tests.ps1 -TestPaths {scene} -TimeoutSeconds 60','environment':{'HARDCORE_AUDIT_EVIDENCE_ROOT':str(target),'HARDCORE_SCALING_ENGAGED':'30','HARDCORE_GRID_COMPARISON_MODE':'current','HARDCORE_GRID_COMPARISON_RUN_ID':'no_plan_failure_'+stage},'scope':'passive diagnosis only; all original algorithm and counters active; NOT performance acceptance'}
text=json.dumps(manifest,indent=2)
(target/'INPUTS.json').write_text(text,encoding='utf-8')
current=root/'outputs/crowd_no_plan_failure_audit_20261009/current_run_inputs.json'
current.parent.mkdir(parents=True,exist_ok=True)
current.write_text(text,encoding='utf-8')
print(json.dumps({'stage':stage,'producer_id':manifest['producer_id'],'source_files':len(sources),'enemy_sha256':frozen['scripts/enemy.gd']}))
