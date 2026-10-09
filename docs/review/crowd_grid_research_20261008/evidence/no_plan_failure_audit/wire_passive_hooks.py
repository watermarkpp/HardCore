from pathlib import Path
import hashlib,json,subprocess

root=Path('C:/Users/Administrator/.codex/worktrees/crowd-v107-comparison/HardCore')
out=Path('C:/Users/Administrator/Documents/HardCore/outputs/crowd_no_plan_failure_audit_20261009')
p=root/'scripts/enemy.gd'
original=p.read_bytes()
stock=subprocess.check_output(['git','show','HEAD:scripts/enemy.gd'],cwd=root)
assert original.replace(b'\r\n',b'\n')==stock.replace(b'\r\n',b'\n'), 'not restored stock107'
(out/'stock_enemy.gd').write_bytes(original)
s=original.decode('utf-8').replace('\r\n','\n')
def replace(a,b,n=1):
    global s
    assert s.count(a)==n,(a[:110],s.count(a),n)
    s=s.replace(a,b)
def section(name,next_name,edits):
    global s
    start=s.index('func '+name+'(')
    end=s.index('func '+next_name+'(',start)
    part=s[start:end]
    for a,b,n in edits:
        assert part.count(a)==n,(name,a[:80],part.count(a),n)
        part=part.replace(a,b)
    s=s[:start]+part+s[end:]

replace('func _hc_neighbor(current: Vector2, hit_target: Node2D, direct: Vector2i) -> Vector2i:', '''# Passive diagnostic only; configured solely by the isolated audit fixture.
var _hc_no_plan_failure_audit: RefCounted

func configure_no_plan_failure_audit(sink: RefCounted) -> void:
\t_hc_no_plan_failure_audit = sink

func _hc_no_plan_event(kind: StringName, values: Array = []) -> void:
\tif _hc_no_plan_failure_audit != null:
\t\t_hc_no_plan_failure_audit.call(&"event", kind, values)

func _hc_neighbor(current: Vector2, hit_target: Node2D, direct: Vector2i) -> Vector2i:''')
replace('''\tvar _hc_diag_started_usec := RuntimeDiagnostics.begin_timed_segment(&"enemy_neighbor_calls")
\tvar _hc_diag_result: Vector2i = _hc_neighbor_internal(current, hit_target, direct)
\tRuntimeDiagnostics.end_timed_segment(&"enemy_neighbor_usec", _hc_diag_started_usec)
\treturn _hc_diag_result''','''\tvar _hc_diag_started_usec := RuntimeDiagnostics.begin_timed_segment(&"enemy_neighbor_calls")
\tif _hc_no_plan_failure_audit != null:
\t\t_hc_no_plan_failure_audit.call(&"begin_call", get_instance_id(), current, _hc_blocked_wait_target_id, _hc_blocked_wait_self, _hc_blocked_wait_target, _hc_known_ground)
\tvar _hc_diag_result: Vector2i = _hc_neighbor_internal(current, hit_target, direct)
\tvar _hc_diag_elapsed := RuntimeDiagnostics.end_timed_segment(&"enemy_neighbor_usec", _hc_diag_started_usec)
\tif _hc_no_plan_failure_audit != null:
\t\t_hc_no_plan_failure_audit.call(&"end_call", _hc_diag_result, _hc_diag_elapsed)
\treturn _hc_diag_result''')
section('_hc_neighbor_internal','_hc_direct_source_route_clear',[
('''\t\tif (
\t\t\tTime.get_ticks_msec() < _hc_next_side_retry_ms''','''\t\tvar audit_wait_now := Time.get_ticks_msec()
\t\tif (
\t\t\taudit_wait_now < _hc_next_side_retry_ms''',1),
('''\t\t):
\t\t\treturn Vector2i.ZERO
\t_hc_blocked_wait_target_id = 0''','''\t\t):
\t\t\t_hc_no_plan_event(&"wait_entry", [audit_wait_now, _hc_next_side_retry_ms, target_ground])
\t\t\treturn Vector2i.ZERO
\t\t_hc_no_plan_event(&"wait_guard_miss", [audit_wait_now, _hc_next_side_retry_ms, current.is_equal_approx(_hc_blocked_wait_self), target_ground.is_equal_approx(_hc_blocked_wait_target), target_ground, _hc_blocked_wait_target, _hc_known_ground])
\t\tif audit_wait_now < _hc_next_side_retry_ms and current.is_equal_approx(_hc_blocked_wait_self) and not target_ground.is_equal_approx(_hc_blocked_wait_target):
\t\t\t_hc_no_plan_event(&"target_only_invalidation", [target_ground, _hc_blocked_wait_target])
\t\tif not target_ground.is_equal_approx(_hc_known_ground):
\t\t\t_hc_no_plan_event(&"known_live_difference", [target_ground, _hc_known_ground])
\telse:
\t\t_hc_no_plan_event(&"wait_identity_miss", [_hc_blocked_wait_target_id])
\t_hc_blocked_wait_target_id = 0''',1),
('''\t\t_hc_last_reason = "CONTEXT_UNAVAILABLE"
\t\treturn''','''\t\t_hc_last_reason = "CONTEXT_UNAVAILABLE"
\t\t_hc_no_plan_event(&"context_unavailable")
\t\treturn''',1),
('''\tvar cell := MonsterNeighborStepPolicyScript.temporary_cell(current)''','''\t_hc_no_plan_event(&"local_context", [anchor, victim_anchor, far_approach, runtime_map_id])
\tvar cell := MonsterNeighborStepPolicyScript.temporary_cell(current)''',1),
('''\t\tvar r6_motion_clear := _hc_motion_clear(current, intended)''','''\t\tvar r6_motion_clear := _hc_motion_clear(current, intended)
\t\t_hc_no_plan_event(&"direct_motion_result", [current, intended, r6_motion_clear])''',1),
('''\t\t\tif Time.get_ticks_msec() < _hc_next_side_retry_ms:
\t\t\t\treturn Vector2i.ZERO''','''\t\t\tif Time.get_ticks_msec() < _hc_next_side_retry_ms:
\t\t\t\t_hc_no_plan_event(&"postretry_wait")
\t\t\t\treturn Vector2i.ZERO''',1),
('''\t\t\t\t\t_hc_last_reason = "DECISION_BUDGET_WAIT"
\t\t\t\t\treturn''','''\t\t\t\t\t_hc_last_reason = "DECISION_BUDGET_WAIT"
\t\t\t\t\t_hc_no_plan_event(&"budget_denied")
\t\t\t\t\treturn''',1),
('''\tif _hc_path_pending:
\t\treturn''','''\tif _hc_path_pending:
\t\t_hc_no_plan_event(&"path_pending")
\t\treturn''',1),
])
section('_hc_choose_blocked_neighbor','_hc_frontline_candidates',[
('''\t_hc_next_side_retry_ms = Time.get_ticks_msec() + HC_BLOCKED_SIDE_RETRY_MS''','''\t_hc_next_side_retry_ms = Time.get_ticks_msec() + HC_BLOCKED_SIDE_RETRY_MS
\t_hc_no_plan_event(&"chooser_enter", [current, anchor, victim_anchor, cell, far_approach])''',1),
('''\t\tvar approach := _hc_far_approach_waypoint(current, anchor, cell, preferred_sign)''','''\t\tvar approach := _hc_far_approach_waypoint(current, anchor, cell, preferred_sign)
\t\t_hc_no_plan_event(&"far_approach_result", [approach])''',1),
('''\t\t\t_hc_step_override = _hc_flank_leg_endpoint(current, approach)
\t\t\treturn''','''\t\t\t_hc_step_override = _hc_flank_leg_endpoint(current, approach)
\t\t\t_hc_no_plan_event(&"chooser_success", ["far", _hc_step_override])
\t\t\treturn''',1),
('''\t\tvar relief := _hc_contact_flank(current, anchor, victim_anchor, hit_target, cell, preferred_sign)''','''\t\tvar relief := _hc_contact_flank(current, anchor, victim_anchor, hit_target, cell, preferred_sign)
\t\t_hc_no_plan_event(&"far_contact_result", [relief])''',1),
('''\t\t\t_hc_step_override = relief
\t\t\treturn''','''\t\t\t_hc_step_override = relief
\t\t\t_hc_no_plan_event(&"chooser_success", ["far_contact", relief])
\t\t\treturn''',1),
('''\t\t_hc_blocked_wait_target = victim_anchor
\t\treturn Vector2i.ZERO''','''\t\t_hc_blocked_wait_target = victim_anchor
\t\t_hc_no_plan_event(&"complete_failure", ["far", "UNPROVEN_certificate"])
\t\treturn Vector2i.ZERO''',1),
('''\tvar batched := _hc_prepare_flank_batch(current, victim_anchor, cell)''','''\tvar batched := _hc_prepare_flank_batch(current, victim_anchor, cell)
\t_hc_no_plan_event(&"near_batch", [batched, _hc_flank_starts.size(), _hc_flank_option_offsets.size()])''',1),
('''\t\tvar query_offset := _hc_flank_option_offsets[option_index] if batched else -1''','''\t\tvar query_offset := _hc_flank_option_offsets[option_index] if batched else -1
\t\t_hc_no_plan_event(&"near_candidate", [option_index, endpoint, committed_endpoint, query_offset])''',1),
('''\t\tif not motion_clear:
\t\t\tcontinue''','''\t\tif not motion_clear:
\t\t\t_hc_no_plan_event(&"near_motion_reject", [option_index, current, committed_endpoint])
\t\t\tcontinue''',1),
('''\t\tif not destination_clear:
\t\t\tcontinue''','''\t\tif not destination_clear:
\t\t\t_hc_no_plan_event(&"near_destination_reject", [option_index, endpoint])
\t\t\tcontinue''',1),
('''\t\tvar contact_waypoint := _hc_contact_flank(current, anchor, victim_anchor, hit_target, cell, preferred_sign)''','''\t\tvar contact_waypoint := _hc_contact_flank(current, anchor, victim_anchor, hit_target, cell, preferred_sign)
\t\t_hc_no_plan_event(&"near_contact_result", [contact_waypoint])''',1),
('''\t\t\t_hc_flank_anchor = anchor
\t\t\treturn MonsterNeighborStepPolicyScript.neighbor_for_desired_ground_direction(contact_waypoint - current)''','''\t\t\t_hc_flank_anchor = anchor
\t\t\t_hc_no_plan_event(&"chooser_success", ["near_contact", contact_waypoint])
\t\t\treturn MonsterNeighborStepPolicyScript.neighbor_for_desired_ground_direction(contact_waypoint - current)''',1),
('''\tif best != Vector2i.ZERO:
\t\t_hc_step_override''','''\tif best != Vector2i.ZERO:
\t\t_hc_no_plan_event(&"chooser_success", ["near", best])
\t\t_hc_step_override''',1),
('''\t\t_hc_blocked_wait_target = _screen_position_px_to_ground_position_gu(hit_target.global_position)
\treturn best''','''\t\t_hc_blocked_wait_target = _screen_position_px_to_ground_position_gu(hit_target.global_position)
\t\t_hc_no_plan_event(&"complete_failure", ["near", "UNPROVEN_certificate"])
\treturn best''',1),
])
section('_hc_motion_candidates','_hc_flank_destination_clear',[
('''\t\tif HCPolicy.core_crossed(a, b, c, combat_radius_gu, other.combat_radius_gu):
\t\t\treturn false''','''\t\tif HCPolicy.core_crossed(a, b, c, combat_radius_gu, other.combat_radius_gu):
\t\t\t_hc_no_plan_event(&"motion_hard_reject", [a, b, c, radius])
\t\t\treturn false''',1),
])
section('_hc_contact_flank','_hc_flank_leg_endpoint',[
('''\t\tvar point := CrowdAttackPosition.contact_leg_with_snapshot(self, hit_target, current, direction, contact_snapshot)''','''\t\tvar point := CrowdAttackPosition.contact_leg_with_snapshot(self, hit_target, current, direction, contact_snapshot)
\t\t_hc_no_plan_event(&"contact_candidate", [option, current, point])''',1),
])
section('_hc_far_approach_waypoint','_hc_contact_flank',[
('''\t\tvar leg := _hc_flank_leg_endpoint(current, point)''','''\t\tvar leg := _hc_flank_leg_endpoint(current, point)
\t\t_hc_no_plan_event(&"far_candidate", [side, current, point, leg])''',1),
])
p.write_bytes(s.replace('\n','\r\n').encode('utf-8'))
(out/'HOOK_BINDING.json').write_text(json.dumps({'baseline':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'stock_sha256':hashlib.sha256(original).hexdigest(),'diagnostic_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'diagnostic_only':True},indent=2),encoding='utf-8')
print('passive hooks wired')
