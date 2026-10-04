from pathlib import Path
import datetime, hashlib, json, os, subprocess

root=Path.cwd()
assert root==Path('C:/Users/Administrator/.codex/worktrees/pluggable-framework-v2/HardCore')
owned=root/'outputs/framework_v2/periodic_dispatch_20261004'
true_index=Path('C:/Users/Administrator/Documents/HardCore/.git/worktrees/HardCore/index')
expected_index='df5a01dd0d87c14620e0021d70c25a830eb2cc37aa7b012eeb14ee1f2c58c5fb'
assert hashlib.sha256(true_index.read_bytes()).hexdigest()==expected_index
paths=[
'scripts/features/contracts/effect_reservation.gd',
'scripts/features/contracts/child_action_lease.gd',
'scripts/features/handlers/death_burst_handler.gd',
'scripts/features/runtime/damage_batch.gd',
'scripts/features/runtime/effect_runtime.gd',
'scripts/features/compilation/feature_compiler.gd',
'scripts/features/compilation/child_capacity_proof.gd',
'scripts/features/presentation/presentation_port.gd',
'tests/framework/feature_cue_actor_retirement_test.gd',
'tests/framework/feature_cue_actor_retirement_test.tscn',
'tests/framework/feature_cue_actor_retirement_reentry_test.tscn',
'docs/source176_r3/CUE_LIFECYCLE_INTEGRATION_WORKLOG_20261005.md',
'tests/framework/feature_chain_commit_test.gd',
'tests/framework/feature_death_child_command_test.gd',
'tests/framework/feature_periodic_child_chain_test.gd',
'tests/framework/periodic_producer_identity_test.gd',
'tests/framework/periodic_producer_identity_test.tscn',
'tests/framework/periodic_refresh_horizon_test.gd',
'tests/framework/periodic_refresh_horizon_test.tscn',
'tests/framework/periodic_child_root_test.gd',
'tests/framework/periodic_child_root_test.tscn',
'tests/framework/periodic_child_g2_root_test.tscn',
'tests/framework/periodic_dispatch_lifecycle_test.gd',
'tests/framework/periodic_dispatch_lifecycle_test.tscn',
'assets/data/features/validation/periodic_chain.json',
'assets/data/features/validation/periodic_chain_registry.json',
'assets/data/features/validation/periodic_chain_g2.json',
'assets/data/features/validation/periodic_chain_g2_registry.json',
 'tests/framework/periodic_refresh_period_boundary_test.gd',
 'tests/framework/periodic_refresh_period_boundary_test.tscn',
 'tests/framework/feature_delivery_templates_test.gd',
 'tests/framework/feature_delivery_templates_test.tscn',
 'assets/data/features/templates/numeric_skills.json',
 'assets/data/features/templates/direct_ignite.json',
 'assets/data/features/templates/finite_chain.json',
 'assets/data/features/templates/template_registry.json',
 'docs/features/NEW_MODULE_DELIVERY_TEMPLATE.md',
 'docs/source176_r3/PERIODIC_DISPATCH_WORKLOG_20261004.md',
 'docs/source176_r3/PARALLEL_CUE_HANDOFF_20261004.md',
 'docs/source176_r3/FRAMEWORK_PUBLICATION_CLOSURE_PLAN.md',
 'assets/data/features/validation/mixed_delivery_chain.json',
 'assets/data/features/validation/mixed_delivery_registry.json',
 'tests/framework/feature_mixed_delivery_test.gd',
 'tests/framework/feature_mixed_delivery_test.tscn',
 'tests/framework/feature_mixed_child_resource_test.tscn',
 'docs/source176_r3/MIXED_DELIVERY_WORKLOG_20261004.md',
 'tests/framework/periodic_refresh_service_boundary_test.gd',
 'tests/framework/periodic_refresh_service_boundary_test.tscn',
 'docs/source176_r3/PERIODIC_SERVICE_BOUNDARY_WORKLOG_20261004.md',
 'tests/framework/accepted_binding_snapshot_test.gd',
 'tests/framework/accepted_binding_snapshot_test.tscn',
 'docs/source176_r3/ACCEPTED_BINDING_SNAPSHOT_WORKLOG_20261005.md']
assert all((root/p).is_file() for p in paths)
env=os.environ.copy(); env['GIT_INDEX_FILE']=str(owned/'check.index')
base='2c58552d2d905eea1f5c13d38685f66c489b092c'
subprocess.run(['git','read-tree',base],env=env,check=True)
subprocess.run(['git','add','--',*paths],env=env,check=True,capture_output=True)
for label,arguments in [('owned_source.stat',['diff','--cached','--stat',base]),('owned_source.diff',['diff','--cached',base]),('owned_source.check',['diff','--cached','--check',base]),('owned_source.status',['status','--short','--',*paths])]:
    result=subprocess.run(['git',*arguments],env=env,capture_output=True)
    (owned/label).write_bytes(result.stdout+result.stderr)
    if label.endswith('.check'): assert result.returncode==0
rows=[dict(path=p,sha256=hashlib.sha256((root/p).read_bytes()).hexdigest(),bytes=(root/p).stat().st_size) for p in paths]
protections=dict(true_index_sha256=hashlib.sha256(true_index.read_bytes()).hexdigest(),frozen_streaming_sha256=hashlib.sha256((root/'scripts/monster_visual_streaming_coordinator.gd').read_bytes()).hexdigest())
assert protections['true_index_sha256']==expected_index
assert protections['frozen_streaming_sha256']=='757da0597ab78aded642a98cf1e7433b9da06a6be5fb0684923ca6686282809d'
result=dict(read_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),base=base,scope=f'{len(paths)} explicitly owned source/test/default-off authoring/documentation paths only; no real staging; presentation_port and three tests transferred from the frozen peer handoff; ignite_cue remains unchanged',paths=rows,protections=protections,diff_check='PASS')
(owned/'SELF_REVIEW_INPUT.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print((owned/'owned_source.stat').read_text(encoding='utf-8'))
print(json.dumps(protections))
