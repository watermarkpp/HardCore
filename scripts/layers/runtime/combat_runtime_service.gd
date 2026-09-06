extends Node

const CombatResolutionRulesScript := preload("res://scripts/combat_resolution_rules.gd")

var _direct_spell_stats_scratch: Dictionary = {}

func face_target_screen_px(actor: Node2D, target: Node2D) -> Vector2:
	if not is_instance_valid(actor) or not is_instance_valid(target):
		return Vector2.ZERO
	# This vector only selects the actor's eight-direction presentation row.
	# Gameplay range and hit geometry are resolved independently in ground GU.
	var direction_screen_px := actor.global_position.direction_to(target.global_position)
	if direction_screen_px.length_squared() > 0.01:
		if actor.has_method("set_combat_facing"):
			actor.call("set_combat_facing", direction_screen_px)
		else:
			actor.set("facing", direction_screen_px)
	return direction_screen_px


func apply_damage(target: Node, amount: int) -> bool:
	if (
		not is_instance_valid(target)
		or not target.has_method("take_damage")
		or _target_rejects_damage(target)
	):
		return false
	var damage_started_usec := RuntimeDiagnostics.timing_start()
	target.take_damage(maxi(1, amount))
	RuntimeDiagnostics.record_timing_usec(&"take_damage_usec", damage_started_usec)
	return true


func apply_enemy_physical_damage(
	target: Node,
	amount: int,
	source_actor: Node2D = null,
	damage_context: Dictionary = {},
) -> bool:
	if (
		not is_instance_valid(target)
		or not target.has_method("take_damage")
		or _target_rejects_damage(target)
	):
		return false
	var damage_started_usec := RuntimeDiagnostics.timing_start()
	if damage_context.is_empty():
		target.call("take_damage", maxi(1, amount), source_actor)
	else:
		# Only callers with a proven semantic source opt into the third argument.
		target.call("take_damage", maxi(1, amount), source_actor, damage_context)
	RuntimeDiagnostics.record_timing_usec(&"take_damage_usec", damage_started_usec)
	return true


func apply_enemy_direct_spell_damage(
	target: Node,
	stable_skill_id: String,
	raw_damage: int,
	source_actor: Node2D,
	rng: RandomNumberGenerator = null,
	magic_defense_adapter := Callable(),
	anti_magic_roll := -1,
	target_stats_scratch: Dictionary = {},
) -> Dictionary:
	if (
		not is_instance_valid(target)
		or not target.has_method("take_damage")
		or _target_rejects_damage(target)
	):
		return {
			"success": false,
			"failure_reason": "target_missing_damage_pipeline",
			"final_damage": 0,
		}
	RuntimeDiagnostics.increment_performance_counter(&"direct_spell_resolution_count")
	var resolution_started_usec := RuntimeDiagnostics.timing_start()
	var target_stats: Dictionary = (
		target_stats_scratch
		if target_stats_scratch != null
		else _direct_spell_stats_scratch
	)
	if not _target_stats_with_runtime_buffs_into(target, target_stats):
		RuntimeDiagnostics.record_timing_usec(
			&"direct_spell_resolution_usec",
			resolution_started_usec,
		)
		return {
			"success": false,
			"failure_reason": "target_direct_spell_stats_invalid",
			"final_damage": 0,
		}
	var checked_anti_magic_roll := anti_magic_roll
	if checked_anti_magic_roll < 0:
		if rng != null:
			checked_anti_magic_roll = rng.randi_range(
				0,
				CombatResolutionRulesScript.ANTI_MAGIC_ROLL_SIDES - 1,
			)
		else:
			checked_anti_magic_roll = randi_range(
				0,
				CombatResolutionRulesScript.ANTI_MAGIC_ROLL_SIDES - 1,
			)
	var resolution := CombatResolutionRulesScript.resolve_direct_spell_damage(
		stable_skill_id,
		maxi(0, raw_damage),
		target_stats,
		checked_anti_magic_roll,
		magic_defense_adapter
	)
	var final_damage := int(resolution.get("final_damage", 0))
	if final_damage > 0:
		var damage_started_usec := RuntimeDiagnostics.timing_start()
		target.call("take_damage", final_damage, source_actor)
		RuntimeDiagnostics.record_timing_usec(&"take_damage_usec", damage_started_usec)
	RuntimeDiagnostics.record_timing_usec(
		&"direct_spell_resolution_usec",
		resolution_started_usec,
	)
	var result: Dictionary = resolution
	result["success"] = final_damage > 0
	return result


func _target_rejects_damage(target: Node) -> bool:
	return (
		target.has_method("can_receive_damage")
		and not bool(target.call("can_receive_damage"))
	)


func _target_stats_with_runtime_buffs(target: Node) -> Dictionary:
	var result: Dictionary = {}
	_target_stats_with_runtime_buffs_into(target, result)
	return result


func _target_stats_with_runtime_buffs_into(
	target: Node,
	output: Dictionary,
) -> bool:
	output.clear()
	if target.has_method("direct_spell_runtime_stats_into"):
		var raw_result: Variant = target.call(
			"direct_spell_runtime_stats_into",
			output,
		)
		if not raw_result is bool or not bool(raw_result):
			return false
		return true
	return _legacy_target_stats_with_runtime_buffs_into(target, output)


func _legacy_target_stats_with_runtime_buffs_into(
	target: Node,
	output: Dictionary,
) -> bool:
	RuntimeDiagnostics.increment_performance_counter(&"direct_spell_stats_snapshot_count")
	var raw_stats: Variant = target.get("monster_data")
	if raw_stats is Dictionary:
		RuntimeDiagnostics.increment_performance_counter(&"direct_spell_full_monster_data_duplicates")
	if raw_stats is Dictionary:
		output.merge(raw_stats as Dictionary, true)
	var red_poison: Variant = target.get_meta("canonical_red_poison", {})
	if not red_poison is Dictionary:
		return true
	if Time.get_ticks_msec() >= int(red_poison.get("expires_at_ms", 0)):
		target.remove_meta("canonical_red_poison")
		return true
	var reduction := 0
	if red_poison.has("flat_mac_reduction"):
		reduction = maxi(0, int(red_poison.get("flat_mac_reduction", 0)))
	elif bool(red_poison.get("legacy_metadata_fallback", false)):
		reduction = maxi(0, int(red_poison.get("flat_reduction", 0)))
	for field: String in ["magic_defense_min", "magic_defense_max", "mdefMin", "mdefMax", "MinMAC", "MaxMAC"]:
		if output.has(field):
			output[field] = maxi(0, int(output[field]) - reduction)
	output["runtime_buff_contract"] = str(
		red_poison.get("contract_id", "buff.taoist.red_poison.v1")
	)
	return true


func apply_player_direct_spell_damage(
	target: Node,
	stable_skill_id: String,
	raw_damage: int,
	anti_magic_roll := -1,
	magic_defense_roll := -1
) -> Dictionary:
	if not is_instance_valid(target) or not target.has_method("take_direct_spell_damage"):
		return {
			"success": false,
			"failure_reason": "target_missing_direct_spell_pipeline",
			"final_damage": 0,
		}
	var resolution: Variant = target.call(
		"take_direct_spell_damage",
		stable_skill_id,
		maxi(0, raw_damage),
		anti_magic_roll,
		magic_defense_roll
	)
	if not resolution is Dictionary:
		return {
			"success": false,
			"failure_reason": "invalid_direct_spell_resolution",
			"final_damage": 0,
		}
	var result := (resolution as Dictionary).duplicate(true)
	result["success"] = true
	return result
