extends "res://tests/framework/fixtures/lease_probe_root.gd"

# Explicit one-shot test fault at the real batch factory boundary. No production
# fail flag, replacement planner, resource refund or damage implementation.
var failed_batch_attempts := 0
var planner_entries := 0
func _begin_feature_damage_batch(_skill_id: String, _release_id: String, _configuration: RefCounted = null) -> RefCounted:
	failed_batch_attempts += 1
	return null
func _execute_canonical_skill_plan(skill_name: String, origin: Vector2, direction: Vector2, client_damage: int,
	extra_target_context: Dictionary, apply_effects: bool, authoritative_cast_target: bool,
	configuration: RefCounted, feature_batch: RefCounted) -> Dictionary:
	planner_entries += 1
	return super._execute_canonical_skill_plan(skill_name,origin,direction,client_damage,extra_target_context,apply_effects,authoritative_cast_target,configuration,feature_batch)
