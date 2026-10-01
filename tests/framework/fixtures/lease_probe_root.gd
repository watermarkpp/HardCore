extends "res://tests/framework/fixtures/legacy_baseline_root.gd"

var observed_configuration: RefCounted
var observed_target_context: Dictionary = {}
var observed_execution: Dictionary = {}
var observed_releases := 0

func _execute_canonical_skill(skill_name: String, origin: Vector2, direction: Vector2,
	client_damage: int, extra_target_context: Dictionary = {}, apply_effects := true,
	authoritative_cast_target := false, configuration: RefCounted = null) -> Dictionary:
	var result := super._execute_canonical_skill(skill_name, origin, direction, client_damage,
		extra_target_context, apply_effects, authoritative_cast_target, configuration)
	if configuration != null:
		observed_configuration = configuration
		observed_execution = result
		observed_releases += 1
	return result

func _canonical_target_context(definition: Dictionary, origin: Vector2, direction: Vector2,
	allow_auto_target := true, release_id := "", context_overrides: Dictionary = {},
	configuration: RefCounted = null) -> Dictionary:
	var result := super._canonical_target_context(definition, origin, direction,
		allow_auto_target, release_id, context_overrides, configuration)
	if configuration != null:
		observed_target_context = result
	return result
