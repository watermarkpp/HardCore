class_name CasterSkillRuntime
extends RefCounted

const SPECIAL_SKILLS := {
	"wizard.repulsion_ring": true,
	"wizard.temptation_light": true,
	"wizard.teleport": true,
	"wizard.magic_shield": true,
	"wizard.holy_word": true,
	"taoist.poison": true,
	"taoist.invisibility": true,
	"taoist.mass_invisibility": true,
	"taoist.magic_defense": true,
	"taoist.defense": true,
	"taoist.revelation": true,
	"taoist.entrapment": true,
	"taoist.summon_skeleton": true,
	"taoist.summon_divine_beast": true,
}

const DAMAGE_OPERATIONS := {
	"wizard.fireball": ["projectile_damage", "single"],
	"wizard.hellfire": ["line_damage", "line"],
	"wizard.lightning": ["target_damage", "single"],
	"wizard.great_fireball": ["projectile_damage", "single"],
	"wizard.exploding_flame": ["area_damage", "target_area"],
	"wizard.fire_wall": ["ground_dot", "five_cell_cross"],
	"wizard.laser": ["line_damage", "line"],
	"wizard.hell_lightning": ["area_damage", "self_area"],
	"wizard.ice_storm": ["area_damage", "target_area"],
	"taoist.soul_fire_talisman": ["projectile_damage", "single"],
}


static func resolve(skill_name_or_id: String, context: Dictionary) -> Dictionary:
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
	if not skill_id.begins_with("wizard.") and not skill_id.begins_with("taoist."):
		return {"skill_id": skill_id, "success": false, "failure_reason": "not_caster_skill"}
	var level := clampi(int(context.get("skill_level", 0)), 0, 3)
	var combat_profile := ProfessionRules.skill_combat_profile(skill_id, level)
	var visual_profile := CasterSkillVisualRegistry.profile(skill_id)
	var result := {
		"skill_id": skill_id,
		"display_name": ProfessionRules.skill_display_name(skill_id),
		"profession_id": "wizard" if skill_id.begins_with("wizard.") else "taoist",
		"skill_level": level,
		"success": true,
		"cast_type": str(combat_profile.get("cast_type", "")),
		"target_mode": str(combat_profile.get("target_mode", "single")),
		"range": float(combat_profile.get("range", 0.0)),
		"area_radius": float(combat_profile.get("area_radius", 0.0)),
		"windup_seconds": float(combat_profile.get("windup", 0.0)),
		"hit_frame": int(combat_profile.get("hit_frame", 0)),
		"cooldown_seconds": float(combat_profile.get("cooldown", 0.0)),
		"runtime_contract": "caster_skill_runtime.v1",
		"formula_source": "source.original_gameofmir.server_suite",
		"source_priority": {"lane": "server_rules", "tier": "primary", "order": 0, "weight": 100},
		"visual": visual_profile,
	}
	for resource_field: String in ["amulet_cost", "apply_delay_ms"]:
		if combat_profile.has(resource_field):
			result[resource_field] = combat_profile[resource_field]
	if SPECIAL_SKILLS.has(skill_id):
		result.merge(CasterSkillBehavior.resolve(skill_id, context), true)
		result["execution_shape"] = _shape_for_operation(str(result.get("operation", "")))
		return result
	match skill_id:
		"taoist.healing", "taoist.mass_healing":
			result.operation = "heal_area" if skill_id.ends_with("mass_healing") else "heal_target"
			result.execution_shape = "target_area" if skill_id.ends_with("mass_healing") else "single"
			result.healing = _taoist_healing(skill_id, level, context)
			result.apply_delay_seconds = 0.8
			if skill_id.ends_with("mass_healing"):
				result.area_radius_cells = 1
			return result
		"taoist.spiritual_warfare":
			result.operation = "passive_accuracy"
			result.execution_shape = "passive"
			result.castable = false
			return result
	if DAMAGE_OPERATIONS.has(skill_id):
		var operation_and_shape: Array = DAMAGE_OPERATIONS[skill_id]
		result.operation = operation_and_shape[0]
		result.execution_shape = operation_and_shape[1]
		result.damage = _damage(skill_id, level, context)
		if skill_id == "wizard.fire_wall":
			result.duration_seconds = WizardCombatMath.fire_wall_duration(level, int(context.get("magic_stat_roll", 0)))
			result.tick_interval_seconds = 3.0
			result.cell_size = int(context.get("cell_size", 48))
		elif skill_id == "wizard.exploding_flame" or skill_id == "wizard.ice_storm":
			result.area_radius_cells = 1
		elif skill_id == "wizard.hell_lightning":
			result.area_radius_cells = 2
		return result
	result.success = false
	result.failure_reason = "missing_runtime_operation"
	return result


static func create_visual(plan: Dictionary, position: Vector2, direction := Vector2.DOWN, target: Node2D = null) -> CasterSkillVisualEffect:
	var effect := CasterSkillVisualEffect.new()
	var radius := float(plan.get("area_radius", 72.0))
	if plan.has("area_radius_cells"):
		radius = maxf(radius, float(plan.area_radius_cells) * float(plan.get("cell_size", 48)))
	effect.setup(position, str(plan.get("skill_id", "")), radius, float(plan.get("visual_duration", 0.8)), direction, target)
	return effect


static func create_projectile(plan: Dictionary, origin: Vector2, direction: Vector2, color := Color.WHITE) -> SkillProjectile:
	if str(plan.get("operation", "")) != "projectile_damage":
		return null
	var projectile := SkillProjectile.new()
	projectile.setup(
		origin + direction.normalized() * 24.0,
		direction,
		int(plan.get("damage", 0)),
		float(plan.get("range", 360.0)),
		color,
		"damage",
		0,
		0.0,
		str(plan.get("skill_id", ""))
	)
	return projectile


static func create_ground_effects(plan: Dictionary, center: Vector2, color := Color.WHITE) -> Array[GroundSkillEffect]:
	var effects: Array[GroundSkillEffect] = []
	if str(plan.get("operation", "")) != "ground_dot":
		return effects
	var cell_size := int(plan.get("cell_size", 48))
	var radius := maxf(20.0, float(cell_size) * 0.46)
	for effect_position: Vector2 in fire_wall_positions(center, cell_size):
		var effect := GroundSkillEffect.new()
		effect.setup(
			effect_position,
			int(plan.get("damage", 0)),
			radius,
			float(plan.get("duration_seconds", 0.1)),
			color,
			str(plan.get("skill_id", "")),
			float(plan.get("tick_interval_seconds", 0.8))
		)
		effects.append(effect)
	return effects


static func create_summon_actor(
	plan: Dictionary,
	owner: PlayerCharacter,
	spiritual_power: int,
	owner_level: int,
	position: Vector2
) -> SummonActor:
	if str(plan.get("operation", "")) != "summon" or owner == null or not bool(plan.get("success", false)):
		return null
	var summon := SummonActor.new()
	summon.global_position = position
	summon.setup(
		owner,
		str(plan.get("display_name", "")),
		maxi(1, spiritual_power),
		int(plan.get("skill_level", 0)),
		str(plan.get("skill_id", "")),
		maxi(1, owner_level)
	)
	return summon


static func create_cast_nodes(
	plan: Dictionary,
	origin: Vector2,
	target_position: Vector2,
	direction := Vector2.DOWN,
	color := Color.WHITE,
	target: Node2D = null,
	owner: PlayerCharacter = null,
	spiritual_power := 1,
	owner_level := 1
) -> Array[Node2D]:
	var nodes: Array[Node2D] = []
	if not bool(plan.get("success", false)) or str(plan.get("operation", "")) == "passive_accuracy":
		return nodes
	match str(plan.get("operation", "")):
		"projectile_damage":
			var projectile := create_projectile(plan, origin, direction, color)
			if projectile != null:
				nodes.append(projectile)
		"ground_dot":
			for effect: GroundSkillEffect in create_ground_effects(plan, target_position, color):
				nodes.append(effect)
		"summon":
			var summon := create_summon_actor(plan, owner, spiritual_power, owner_level, origin)
			if summon != null:
				nodes.append(summon)
		_:
			if str(plan.get("visual", {}).get("status", "")) == "formal_primary_client_pixel":
				nodes.append(create_visual(plan, target_position, direction, target))
	return nodes


static func execute_cast(plan: Dictionary, context: Dictionary) -> Dictionary:
	var result := {
		"skill_id": str(plan.get("skill_id", "")),
		"success": bool(plan.get("success", false)),
		"operation": str(plan.get("operation", "")),
		"applied_count": 0,
		"spawned_count": 0,
		"nodes": [],
		"adapter_required": "",
		"runtime_contract": "caster_skill_execution.v1",
	}
	if not result.success:
		return result
	var operation := str(plan.get("operation", ""))
	var operation_adapter := _runtime_adapter(context, operation)
	if operation in ["magic_defense_buff", "physical_defense_buff"] and not context.has("defense_bonus"):
		result.adapter_required = "defense_bonus"
		return result
	if operation == "random_home_map_move" and not context.has("teleport_destination") and not operation_adapter.is_valid():
		result.adapter_required = "validated_home_map_destination"
		return result
	if operation == "poison_armor" and not operation_adapter.is_valid():
		result.adapter_required = "target_armor_poison"
		return result
	var caster := context.get("caster") as PlayerCharacter
	var primary_target := context.get("primary_target") as Node2D
	var origin := context.get("origin", caster.global_position if caster != null else Vector2.ZERO) as Vector2
	var direction := context.get("direction", Vector2.DOWN) as Vector2
	var target_position := context.get(
		"target_position",
		primary_target.global_position if primary_target != null else origin + direction * float(plan.get("range", 0.0))
	) as Vector2
	var nodes := create_cast_nodes(
		plan,
		origin,
		target_position,
		direction,
		context.get("color", Color.WHITE) as Color,
		primary_target,
		caster,
		int(context.get("spiritual_power", 1)),
		int(context.get("owner_level", 1))
	)
	var parent := context.get("parent") as Node
	for node: Node2D in nodes:
		if parent != null:
			parent.add_child(node)
	result.nodes = nodes
	result.spawned_count = nodes.size()
	var targets := _runtime_targets(context, primary_target, "affected_targets")
	var allies := _runtime_targets(context, caster, "affected_allies")
	match operation:
		"target_damage", "line_damage", "area_damage":
			for target: Node2D in targets:
				if target is EnemyActor:
					target.take_damage(int(plan.get("damage", 0)), caster)
					result.applied_count += 1
		"heal_target", "heal_area":
			for ally: Node2D in allies:
				if ally is PlayerCharacter:
					ally.restore_health(int(plan.get("healing", 0)))
					result.applied_count += 1
		"knockback":
			for target: Node2D in targets:
				var push_direction := (target.global_position - origin).normalized()
				if push_direction.length_squared() <= 0.0:
					push_direction = direction.normalized()
				target.global_position += push_direction * float(plan.get("push_distance", 0.0))
				result.applied_count += 1
		"tame_monster":
			if primary_target is EnemyActor:
				primary_target.apply_charm(float(plan.get("duration_seconds", 0.0)))
				result.applied_count = 1
		"magic_shield":
			if caster != null:
				caster.apply_magic_shield(
					float(plan.get("duration_seconds", 0.0)),
					float(plan.get("damage_reduction", 0.0))
				)
				result.applied_count = 1
		"execute_undead":
			if primary_target is EnemyActor:
				primary_target.take_damage(primary_target.current_hp, caster)
				result.applied_count = 1
		"poison_health":
			if primary_target is EnemyActor:
				primary_target.apply_poison(
					maxi(1, int(plan.get("power", 1))),
					float(plan.get("duration_seconds", 0.0))
				)
				result.applied_count = 1
		"stealth", "stealth_area":
			for ally: Node2D in allies:
				if ally is PlayerCharacter:
					ally.apply_stealth(float(plan.get("duration_seconds", 0.0)))
					result.applied_count += 1
		"magic_defense_buff", "physical_defense_buff":
			for ally: Node2D in allies:
				if ally is PlayerCharacter:
					ally.apply_defense_buff(
						float(plan.get("duration_seconds", 0.0)),
						int(context.defense_bonus)
					)
					result.applied_count += 1
		"root_ring":
			for target: Node2D in targets:
				if target is EnemyActor:
					target.apply_control(float(plan.get("duration_seconds", 0.0)))
					result.applied_count += 1
		"show_target_health":
			if primary_target is EnemyActor:
				result.inspected_target = {
					"display_name": primary_target.display_name,
					"current_hp": primary_target.current_hp,
					"max_hp": primary_target.max_hp,
					"duration_seconds": float(plan.get("duration_seconds", 0.0)),
				}
				result.applied_count = 1
		"random_home_map_move":
			if context.has("teleport_destination") and caster != null:
				caster.global_position = context.teleport_destination
				result.applied_count = 1
			else:
				operation_adapter.call(plan, context)
				result.applied_count = 1
		"poison_armor":
			operation_adapter.call(plan, context)
			result.applied_count = 1
	return result


static func fire_wall_positions(center: Vector2, cell_size := 48) -> Array[Vector2]:
	return [
		center,
		center + Vector2(cell_size, 0),
		center + Vector2(-cell_size, 0),
		center + Vector2(0, cell_size),
		center + Vector2(0, -cell_size),
	]


static func _runtime_targets(context: Dictionary, fallback: Node2D, field: String) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var candidates: Variant = context.get(field, [])
	if candidates is Array:
		for candidate: Variant in candidates:
			if candidate is Node2D and is_instance_valid(candidate):
				result.append(candidate)
	if result.is_empty() and fallback != null and is_instance_valid(fallback):
		result.append(fallback)
	return result


static func _runtime_adapter(context: Dictionary, operation: String) -> Callable:
	var adapters: Variant = context.get("operation_adapters", {})
	if adapters is Dictionary:
		var candidate: Variant = adapters.get(operation)
		if candidate is Callable:
			return candidate
	return Callable()


static func _damage(skill_id: String, level: int, context: Dictionary) -> int:
	if skill_id.begins_with("wizard."):
		if context.has("magic_power_roll") and context.has("def_power_roll"):
			return WizardCombatMath.damage_with_rolls(
				skill_id,
				int(context.get("magic_stat_roll", 0)),
				level,
				int(context.magic_power_roll),
				int(context.def_power_roll),
				bool(context.get("target_is_undead", false))
			)
		return WizardCombatMath.damage(skill_id, int(context.get("magic_stat_roll", 0)), level)
	if context.has("magic_power_roll") and context.has("def_power_roll"):
		return TaoistCombatMath.damage_with_rolls(
			skill_id,
			int(context.get("spiritual_stat_roll", 0)),
			level,
			int(context.magic_power_roll),
			int(context.def_power_roll)
		)
	return TaoistCombatMath.damage(skill_id, int(context.get("spiritual_stat_roll", 0)), level)


static func _taoist_healing(skill_id: String, level: int, context: Dictionary) -> int:
	if context.has("magic_power_roll") and context.has("def_power_roll"):
		return TaoistCombatMath.healing_with_rolls(
			skill_id,
			int(context.get("spiritual_stat_roll", 0)),
			level,
			int(context.magic_power_roll),
			int(context.def_power_roll)
		)
	return TaoistCombatMath.healing(skill_id, int(context.get("spiritual_stat_roll", 0)), level)


static func _shape_for_operation(operation: String) -> String:
	match operation:
		"knockback", "magic_shield", "stealth": return "self_area"
		"stealth_area", "magic_defense_buff", "physical_defense_buff": return "ally_area"
		"root_ring": return "target_area"
		"tame_monster", "execute_undead", "poison_health", "poison_armor", "show_target_health": return "single"
		"random_home_map_move": return "map_move"
		"summon": return "owner_spawn"
	return "single"
