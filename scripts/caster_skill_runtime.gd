class_name CasterSkillRuntime
extends RefCounted

const CombatResolutionRules := preload("res://scripts/combat_resolution_rules.gd")
const CasterSpellGeometryScript := preload(
	"res://scripts/skills/caster_spell_geometry.gd"
)
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const SkillSpatialProjectionContractScript := preload(
	"res://scripts/skills/skill_spatial_projection_contract.gd"
)
const WorldSpatialRules := preload("res://scripts/world_spatial_rules.gd")
const SkillDataLoaderScript := preload(
	"res://scripts/skills/skill_data_loader.gd"
)
const CombatUnitLegacyAdapterScript := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)

const RUNTIME_CONTRACT_ID := "caster_skill_runtime.ground_units.v2"
const EXECUTION_SNAPSHOT_GATE_CONTRACT_ID := (
	"caster_skill_execution.spatial_snapshot_gate.v1"
)
const NON_PRODUCTION_SPATIAL_ADAPTER_ID := (
	"caster_skill_execution.non_production_spatial_test_adapter.v1"
)
const FIRE_WALL_CELL_SPACING_GU := 1.0
const FIRE_WALL_EFFECT_RADIUS_GU := 0.5
const FIRE_WALL_VISUAL_RADIUS_PX := 22.08

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
	"wizard.fire_wall": ["ground_dot", "square_2x2"],
	"wizard.laser": ["line_damage", "line"],
	"wizard.hell_lightning": ["area_damage", "self_area"],
	"wizard.ice_storm": ["area_damage", "target_area"],
	"taoist.soul_fire_talisman": ["projectile_damage", "single"],
}
const TARGET_FOOTPRINT_SKILL_IDS := {
	"wizard.temptation_light": true,
	"wizard.lightning": true,
	"wizard.holy_word": true,
	"taoist.healing": true,
	"taoist.poison": true,
	"taoist.revelation": true,
}
const TARGET_FOOTPRINT_RELEASE_CONTRACT_ID := (
	"skills.caster.target_single.release_footprint_snapshot.v1"
)
const GROUND_EXACT_SKILL_IDS := {
	"wizard.repulsion_ring": true,
	"wizard.exploding_flame": true,
	"wizard.fire_wall": true,
	"wizard.hell_lightning": true,
	"wizard.ice_storm": true,
	"taoist.mass_invisibility": true,
	"taoist.magic_defense": true,
	"taoist.defense": true,
	"taoist.entrapment": true,
	"taoist.mass_healing": true,
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
		"maximum_range_gu": float(combat_profile.get("maximum_range_gu", 0.0)),
		"search_range_gu": float(combat_profile.get("search_range_gu", 0.0)),
		"area_radius_gu": float(combat_profile.get("area_radius_gu", 0.0)),
		"visual_radius_px": float(combat_profile.get("visual_radius_px", 0.0)),
		"windup_seconds": float(combat_profile.get("windup", 0.0)),
		"hit_frame": int(combat_profile.get("hit_frame", 0)),
		"cooldown_seconds": float(combat_profile.get("cooldown", 0.0)),
		"runtime_contract": RUNTIME_CONTRACT_ID,
		"formula_source": "source.original_gameofmir.server_suite",
		"source_priority": {"lane": "server_rules", "tier": "primary", "order": 0, "weight": 100},
		"evasion_channel": "anti_poison" if skill_id == "taoist.poison" else ("anti_magic" if CombatResolutionRules.anti_magic_eligible(skill_id) else "none"),
		"anti_magic_eligible": CombatResolutionRules.anti_magic_eligible(skill_id),
		"anti_magic_checked": false,
		"magic_evaded": false,
		"visual": visual_profile,
		"visual_duration": CasterSkillVisualRegistry.animation_duration(skill_id),
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
				result.area_radius_grid_steps = 1.0
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
		result.damage_before_evasion = int(result.damage)
		if bool(result.anti_magic_eligible) and context.has("anti_magic_roll"):
			var evasion := CombatResolutionRules.resolve_magic_damage(
				skill_id,
				int(result.damage),
				CombatResolutionRules.anti_magic_points_from_context(context),
				int(context.anti_magic_roll)
			)
			result.merge(evasion, true)
			result.damage = int(evasion.damage_after_evasion)
		else:
			result.enters_magic_defense_stage = int(result.damage) > 0
		if skill_id == "wizard.fire_wall":
			result.duration_seconds = WizardCombatMath.fire_wall_duration(level, int(context.get("magic_stat_roll", 0)))
			result.tick_interval_seconds = 1.0
			result.cell_spacing_gu = FIRE_WALL_CELL_SPACING_GU
			result.ground_effect_radius_gu = FIRE_WALL_EFFECT_RADIUS_GU
			result.visual_radius_px = FIRE_WALL_VISUAL_RADIUS_PX
		elif skill_id == "wizard.exploding_flame" or skill_id == "wizard.ice_storm":
			result.area_radius_grid_steps = 1.0
		elif skill_id == "wizard.hell_lightning":
			result.area_radius_grid_steps = 2.0
		return result
	result.success = false
	result.failure_reason = "missing_runtime_operation"
	return result


static func create_visual(
	plan: Dictionary,
	position: Vector2,
	direction := Vector2.DOWN,
	follow_node: Node2D = null,
	phase_id := ""
) -> CasterSkillVisualEffect:
	var skill_id := str(plan.get("skill_id", ""))
	if not CasterSkillVisualRegistry.is_runtime_ready(skill_id):
		return null
	var profile := CasterSkillVisualRegistry.profile(skill_id)
	var visual_profile := CasterSkillVisualRegistry.visual_profile(skill_id)
	for key: String in visual_profile:
		if not profile.has(key) and key != "animation":
			profile[key] = visual_profile[key]
	var role := str(plan.get("visual", {}).get("role", ""))
	if role in [
		CasterSkillVisualRegistry.ROLE_PROJECTILE,
		CasterSkillVisualRegistry.ROLE_GROUND_EFFECT,
		CasterSkillVisualRegistry.ROLE_SUMMON_ACTOR,
	]:
		return null
	var effect := CasterSkillVisualFactory.create(profile)
	var visual_geometry_context := CasterSpellGeometryScript.visual_context_from_plan(
		skill_id,
		plan,
		position
	)
	var visual_radius_px := maxf(0.0, float(plan.get("visual_radius_px", 0.0)))
	if role == CasterSkillVisualRegistry.ROLE_LINE_EFFECT:
		var geometry_offsets: Array = visual_geometry_context.get(
			"geometry_screen_offsets_px", []
		)
		# A canonical line may be truncated to zero GU by terrain.  Its explicit
		# empty point list is authoritative and must not fall through to the full
		# 5/8-GU definition radius: that produced a full visible line while the
		# shared damage strip contained no area and therefore could hit nothing.
		var canonical_geometry_was_supplied := (
			CasterSpellGeometryScript.canonical_geometry_contract_is_supported(
				str(plan.get("canonical_geometry_contract", ""))
			)
			and plan.has("geometry_screen_points_px")
		)
		if canonical_geometry_was_supplied and geometry_offsets.is_empty():
			return null
		if not geometry_offsets.is_empty():
			visual_radius_px = 0.0
			for raw_offset: Variant in geometry_offsets:
				if raw_offset is Vector2:
					var geometry_offset: Vector2 = raw_offset
					visual_radius_px = maxf(
						visual_radius_px,
						geometry_offset.length()
					)
		else:
			var geometry: Dictionary = SkillDataLoaderScript.skill(
				skill_id
			).get("geometry", {})
			var effect_length_gu := float(geometry.get("effect_length_gu", 0.0))
			var direction_ground_gu := (
				GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
					direction
				).normalized()
			)
			if effect_length_gu > 0.0:
				visual_radius_px = (
					GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
						direction_ground_gu * effect_length_gu
					).length()
				)
			else:
				visual_radius_px = maxf(
					visual_radius_px,
					GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
						direction_ground_gu
						* float(plan.get("maximum_range_gu", 0.0))
					).length()
				)
	elif plan.has("area_radius_grid_steps"):
		visual_radius_px = maxf(
			visual_radius_px,
			float(plan.area_radius_grid_steps)
			* CombatUnitLegacyAdapterScript.ISO_AREA_EQUIVALENT_PX_PER_GU
		)
	effect.setup(
		position,
		skill_id,
		visual_radius_px,
		float(plan.get("visual_duration", 0.8)),
		direction,
		follow_node,
		phase_id,
		visual_geometry_context
	)
	return effect


static func create_projectile(plan: Dictionary, origin: Vector2, direction: Vector2, color := Color.WHITE) -> SkillProjectile:
	if (
		str(plan.get("operation", "")) != "projectile_damage"
		or str(plan.get("visual", {}).get("role", ""))
			!= CasterSkillVisualRegistry.ROLE_PROJECTILE
		or not CasterSkillVisualRegistry.is_runtime_ready(str(plan.get("skill_id", "")))
	):
		return null
	var projectile := SkillProjectile.new()
	var direction_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(direction)
		.normalized()
	)
	var formal_geometry: Dictionary = SkillDataLoaderScript.skill(
		str(plan.get("skill_id", ""))
	).get("geometry", {})
	projectile.setup_ground_unit_projectile(
		origin,
		direction_ground_gu,
		float(formal_geometry.get("maximum_range_gu", 0.0)),
		int(plan.get("damage_before_evasion", plan.get("damage", 0))),
		CombatUnitLegacyAdapterScript.PROJECTILE_SPEED_GU_PER_SEC,
		CombatUnitLegacyAdapterScript.PROJECTILE_RADIUS_GU,
		direction.normalized() * 24.0,
		color,
		"damage",
		0,
		0.0,
		str(plan.get("skill_id", "")),
		str(plan.get("release_id", ""))
	)
	return projectile


static func create_ground_effects(
	plan: Dictionary,
	center: Vector2,
	color := Color.WHITE,
	source_actor: Node2D = null
) -> Array[GroundSkillEffect]:
	var effects: Array[GroundSkillEffect] = []
	if (
		str(plan.get("operation", "")) != "ground_dot"
		or str(plan.get("visual", {}).get("role", ""))
			!= CasterSkillVisualRegistry.ROLE_GROUND_EFFECT
		or not CasterSkillVisualRegistry.is_runtime_ready(str(plan.get("skill_id", "")))
	):
		return effects
	var cell_spacing_gu := maxf(
		0.0,
		float(plan.get("cell_spacing_gu", FIRE_WALL_CELL_SPACING_GU))
	)
	var radius_gu := maxf(
		0.0,
		float(plan.get("ground_effect_radius_gu", FIRE_WALL_EFFECT_RADIUS_GU))
	)
	var visual_radius_px := maxf(
		1.0,
		float(plan.get("visual_radius_px", FIRE_WALL_VISUAL_RADIUS_PX))
	)
	var release_id := str(plan.get("release_id", ""))
	if release_id.is_empty():
		release_id = "%s:ground:%d" % [
			str(plan.get("skill_id", "wizard.fire_wall")),
			Time.get_ticks_usec(),
		]
	var release_snapshot: Dictionary = plan.get(
		"skill_footprint_snapshot", {}
	)
	var effect_positions := fire_wall_positions_ground_gu(
		center,
		cell_spacing_gu
	)
	if not SkillFootprintSnapshotScript.is_valid(release_snapshot):
		var inferred_cells_grid_steps: Array[Vector2i] = []
		for effect_position: Vector2 in effect_positions:
			inferred_cells_grid_steps.append(Vector2i(
				GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
					effect_position
				).round()
			))
		release_snapshot = (
			CasterSpellGeometryScript.create_exact_cell_union_release_snapshot(
				str(plan.get("skill_id", "wizard.fire_wall")),
				release_id,
				GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(center),
				inferred_cells_grid_steps
			)
		)
	for effect_position: Vector2 in effect_positions:
		var effect := GroundSkillEffect.new()
		effect.setup_ground_unit_effect(
			effect_position,
			int(plan.get("damage", 0)),
			radius_gu,
			float(plan.get("duration_seconds", 0.1)),
			color,
			str(plan.get("skill_id", "")),
			float(plan.get("tick_interval_seconds", 0.8)),
			visual_radius_px,
			release_id,
			release_snapshot
		)
		effect.configure_runtime_source(source_actor)
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
	summon.configure_spawn_release_footprint(str(plan.get("release_id", "")))
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
	var operation := str(plan.get("operation", ""))
	if operation == "passive_accuracy":
		return nodes
	var effect_succeeded := bool(plan.get("success", false))
	match operation:
		"projectile_damage":
			if effect_succeeded:
				var projectile := create_projectile(plan, origin, direction, color)
				if projectile != null:
					nodes.append(projectile)
		"ground_dot":
			if effect_succeeded:
				for effect: GroundSkillEffect in create_ground_effects(
					plan, target_position, color, owner
				):
					nodes.append(effect)
		"summon":
			var summon := create_summon_actor(plan, owner, spiritual_power, owner_level, origin)
			if summon != null:
				nodes.append(summon)
		_:
			if (
				str(plan.get("visual", {}).get("status", ""))
					== "formal_primary_client_animation"
				and CasterSkillVisualRegistry.is_runtime_ready(
					str(plan.get("skill_id", ""))
				)
			):
				var role := str(plan.get("visual", {}).get("role", ""))
				var attachment := str(
					CasterSkillVisualRegistry.render_policy(
						str(plan.get("skill_id", ""))
					).get("attachment_policy", "world_anchor")
				)
				var visual_position := target_position
				var follow_node: Node2D = null
				match attachment:
					"target_actor":
						follow_node = target
						visual_position = (
							target.global_position
							if is_instance_valid(target)
							else target_position
						)
					"caster_actor":
						follow_node = owner
						visual_position = (
							owner.global_position
							if is_instance_valid(owner)
							else origin
						)
					"world_anchor":
						visual_position = (
							origin
							if role in [
								CasterSkillVisualRegistry.ROLE_SELF_EFFECT,
								CasterSkillVisualRegistry.ROLE_SELF_AREA,
								CasterSkillVisualRegistry.ROLE_LINE_EFFECT,
							]
							else target_position
						)
				var visual := create_visual(
					plan, visual_position, direction, follow_node
				)
				if visual != null:
					nodes.append(visual)
				if (
					str(plan.get("skill_id", "")) == "wizard.teleport"
					and bool(plan.get("teleport_arrival_ready", false))
				):
					var arrival := create_visual(
						plan, target_position, direction, owner, "arrival"
					)
					if arrival != null:
						nodes.append(arrival)
	return nodes


static func execute_cast(plan: Dictionary, context: Dictionary) -> Dictionary:
	var release_id := _release_id(plan, context)
	var skill_id := str(plan.get("skill_id", ""))
	var spatial_relationship := (
		SkillSpatialProjectionContractScript.relationship_type(skill_id)
	)
	var result := {
		"skill_id": skill_id,
		"success": bool(plan.get("success", false)),
		"operation": str(plan.get("operation", "")),
		"applied_count": 0,
		"spawned_count": 0,
		"nodes": [],
		"adapter_required": "",
		"runtime_contract": "caster_skill_execution.v1",
		"release_id": release_id,
		"skill_footprint_snapshot": {},
		"spatial_relationship": spatial_relationship,
		"spatial_snapshot_gate_contract": (
			EXECUTION_SNAPSHOT_GATE_CONTRACT_ID
		),
		"spatial_snapshot_gate": "not_applicable",
		"compatibility_adapter_used": false,
		"compatibility_adapter_id": "",
		"child_movement_snapshots": [],
	}
	if not result.success:
		return result
	var operation := str(plan.get("operation", ""))
	var operation_adapter := _runtime_adapter(context, operation)
	var magic_defense_adapter := _callable_context_field(context, "magic_defense_adapter")
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
	var raw_plan_snapshot: Variant = plan.get("skill_footprint_snapshot", {})
	if (
		raw_plan_snapshot is Dictionary
		and _snapshot_matches_release(
			raw_plan_snapshot as Dictionary, skill_id, release_id
		)
	):
		result.skill_footprint_snapshot = raw_plan_snapshot
	var targeted_release_actor: Node2D = primary_target
	if (
		targeted_release_actor == null
		and str(plan.get("skill_id", "")) == "taoist.healing"
	):
		targeted_release_actor = caster
	if (
		targeted_release_actor != null
		and TARGET_FOOTPRINT_SKILL_IDS.has(skill_id)
	):
		result.skill_footprint_snapshot = (
			_create_target_footprint_snapshot(
				skill_id,
				release_id,
				targeted_release_actor
			)
		)
	var origin := context.get("origin", caster.global_position if caster != null else Vector2.ZERO) as Vector2
	var geometry_cells_grid_steps := _geometry_cells_grid_steps(plan)
	if (
		GROUND_EXACT_SKILL_IDS.has(skill_id)
		and not geometry_cells_grid_steps.is_empty()
	):
		result.skill_footprint_snapshot = (
			CasterSpellGeometryScript.create_exact_cell_union_release_snapshot(
				skill_id,
				release_id,
				GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(origin),
				geometry_cells_grid_steps
			)
		)
	var direction := context.get("direction", Vector2.DOWN) as Vector2
	var fallback_direction_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(direction)
		.normalized()
	)
	var fallback_target_position_screen_px := (
		origin
		+ GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			fallback_direction_ground_gu
			* float(plan.get("maximum_range_gu", 0.0))
		)
	)
	var target_position := context.get(
		"target_position",
		context.get(
			"teleport_destination",
			primary_target.global_position
			if primary_target != null
			else fallback_target_position_screen_px
		)
	) as Vector2
	if (
		skill_id == "wizard.teleport"
		and context.has("teleport_destination")
		and caster != null
	):
		result.skill_footprint_snapshot = (
			SkillFootprintSnapshotScript.create_target_footprint(
				skill_id,
				release_id,
				GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
					target_position
				),
				_target_combat_radius_gu(caster),
				caster.get_instance_id()
			)
		)
	var deferred_snapshot_operation := operation in [
		"projectile_damage", "ground_dot", "summon",
	]
	if (
		SkillSpatialProjectionContractScript.requires_release_snapshot(skill_id)
		and not deferred_snapshot_operation
		and not _snapshot_matches_release(
			result.skill_footprint_snapshot, skill_id, release_id
		)
	):
		if not _use_non_production_spatial_adapter(context, result):
			result.adapter_required = "skill_footprint_snapshot"
			result.spatial_snapshot_gate = "blocked_missing_release_snapshot"
			return result
	var node_plan := plan.duplicate(true)
	node_plan["release_id"] = release_id
	node_plan["skill_footprint_snapshot"] = result.skill_footprint_snapshot
	node_plan["teleport_arrival_ready"] = (
		str(plan.get("operation", "")) == "random_home_map_move"
		and context.has("teleport_destination")
	)
	var nodes := create_cast_nodes(
		node_plan,
		origin,
		target_position,
		direction,
		context.get("color", Color.WHITE) as Color,
		primary_target,
		caster,
		int(context.get("spiritual_power", 1)),
		int(context.get("owner_level", 1))
	)
	for node: Node2D in nodes:
		var node_snapshot := _node_release_snapshot(node)
		if (
			result.skill_footprint_snapshot.is_empty()
			and _snapshot_matches_release(
				node_snapshot, skill_id, release_id
			)
		):
			result.skill_footprint_snapshot = node_snapshot
	if (
		SkillSpatialProjectionContractScript.requires_release_snapshot(skill_id)
		and not _snapshot_matches_release(
			result.skill_footprint_snapshot, skill_id, release_id
		)
		and not bool(result.compatibility_adapter_used)
	):
		for node: Node2D in nodes:
			node.free()
		result.adapter_required = "skill_footprint_snapshot"
		result.spatial_snapshot_gate = "blocked_missing_runtime_node_snapshot"
		return result
	result.spatial_snapshot_gate = (
		"explicit_non_production_adapter"
		if bool(result.compatibility_adapter_used)
		else (
			"validated_release_snapshot"
			if SkillSpatialProjectionContractScript.requires_release_snapshot(
				skill_id
			)
			else "not_applicable"
		)
	)
	var parent := context.get("parent") as Node
	for node: Node2D in nodes:
		if node is SkillProjectile:
			node.configure_runtime_resolution(
				caster,
				magic_defense_adapter,
				int(context.get("anti_magic_roll", -1)),
				int(context.get("anti_poison_random", -1))
			)
		if parent != null:
			parent.add_child(node)
	result.nodes = nodes
	result.spawned_count = nodes.size()
	result["target_resolutions"] = []
	result["evaded_count"] = 0
	var targets := _runtime_targets(context, primary_target, "affected_targets")
	var allies := _runtime_targets(context, caster, "affected_allies")
	match operation:
		"target_damage":
			for target: Node2D in targets:
				if (
					target is EnemyActor
					and target == primary_target
					and (
						bool(result.compatibility_adapter_used)
						or _target_matches_release_snapshot(
							result.skill_footprint_snapshot,
							target
						)
					)
				):
					_apply_direct_spell_damage(
						plan,
						context,
						result,
						target,
						caster,
						magic_defense_adapter
					)
		"line_damage", "area_damage":
			for target: Node2D in targets:
				if (
					target is EnemyActor
					and (
						bool(result.compatibility_adapter_used)
						or _target_intersects_release_snapshot(
							result.skill_footprint_snapshot, target
						)
					)
				):
					_apply_direct_spell_damage(
						plan,
						context,
						result,
						target,
						caster,
						magic_defense_adapter
					)
		"heal_target":
			for ally: Node2D in allies:
				if (
					ally is PlayerCharacter
					and ally == targeted_release_actor
					and (
						bool(result.compatibility_adapter_used)
						or _target_matches_release_snapshot(
							result.skill_footprint_snapshot,
							ally
						)
					)
				):
					ally.restore_health(int(plan.get("healing", 0)))
					result.applied_count += 1
		"heal_area":
			for ally: Node2D in allies:
				if (
					ally is PlayerCharacter
					and (
						bool(result.compatibility_adapter_used)
						or _target_intersects_release_snapshot(
							result.skill_footprint_snapshot, ally
						)
					)
				):
					ally.restore_health(int(plan.get("healing", 0)))
					result.applied_count += 1
		"knockback":
			for target: Node2D in targets:
				if (
					not bool(result.compatibility_adapter_used)
					and not _target_intersects_release_snapshot(
						result.skill_footprint_snapshot, target
					)
				):
					continue
				var target_delta_ground_gu := (
					GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
						target.global_position - origin
					)
				)
				var knockback_fallback_direction_ground_gu := (
					GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(direction)
				)
				var push_direction_ground_gu := (
					GroundUnitSpaceScript.normalized_ground_direction(
						Vector2.ZERO,
						target_delta_ground_gu,
						knockback_fallback_direction_ground_gu
					)
				)
				var push_delta_ground_gu := (
					push_direction_ground_gu
					* maxf(0.0, float(plan.get("push_distance_gu", 0.0)))
				)
				var target_start_ground_gu := (
					GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
						target.global_position
					)
				)
				var movement_index: int = result.child_movement_snapshots.size()
				result.child_movement_snapshots.append(
					SkillFootprintSnapshotScript.create_swept_capsule_path(
						skill_id,
						"%s:movement:%d" % [release_id, movement_index],
						target_start_ground_gu,
						target_start_ground_gu + push_delta_ground_gu,
						_target_combat_radius_gu(target),
						SkillFootprintSnapshotScript.DEFAULT_CURVE_SEGMENTS / 2,
						str(result.skill_footprint_snapshot.get(
							"snapshot_id", ""
						)),
						movement_index
					)
				)
				target.global_position += (
					GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
						push_delta_ground_gu
					)
				)
				result.applied_count += 1
		"tame_monster":
			if (
				primary_target is EnemyActor
				and _target_matches_release_snapshot(
					result.skill_footprint_snapshot, primary_target
				)
			):
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
			if (
				primary_target is EnemyActor
				and _target_matches_release_snapshot(
					result.skill_footprint_snapshot, primary_target
				)
			):
				primary_target.take_damage(primary_target.current_hp, caster)
				result.applied_count = 1
		"poison_health":
			if (
				primary_target is EnemyActor
				and _target_matches_release_snapshot(
					result.skill_footprint_snapshot, primary_target
				)
			):
				primary_target.apply_poison(
					maxi(1, int(plan.get("power", 1))),
					float(plan.get("duration_seconds", 0.0))
				)
				result.applied_count = 1
		"stealth":
			for ally: Node2D in allies:
				if ally is PlayerCharacter:
					ally.apply_stealth(float(plan.get("duration_seconds", 0.0)))
					result.applied_count += 1
		"stealth_area":
			for ally: Node2D in allies:
				if (
					ally is PlayerCharacter
					and (
						bool(result.compatibility_adapter_used)
						or _target_intersects_release_snapshot(
							result.skill_footprint_snapshot, ally
						)
					)
				):
					ally.apply_stealth(float(plan.get("duration_seconds", 0.0)))
					result.applied_count += 1
		"magic_defense_buff", "physical_defense_buff":
			for ally: Node2D in allies:
				if (
					ally is PlayerCharacter
					and (
						bool(result.compatibility_adapter_used)
						or _target_intersects_release_snapshot(
							result.skill_footprint_snapshot, ally
						)
					)
				):
					ally.apply_defense_buff(
						float(plan.get("duration_seconds", 0.0)),
						int(context.defense_bonus)
					)
					result.applied_count += 1
		"root_ring":
			for target: Node2D in targets:
				if (
					target is EnemyActor
					and (
						bool(result.compatibility_adapter_used)
						or _target_intersects_release_snapshot(
							result.skill_footprint_snapshot, target
						)
					)
				):
					target.apply_control(float(plan.get("duration_seconds", 0.0)))
					result.applied_count += 1
		"show_target_health":
			if (
				primary_target is EnemyActor
				and _target_matches_release_snapshot(
					result.skill_footprint_snapshot, primary_target
				)
			):
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
			if (
				primary_target is EnemyActor
				and _target_matches_release_snapshot(
					result.skill_footprint_snapshot, primary_target
				)
			):
				operation_adapter.call(plan, context)
				result.applied_count = 1
	return result


static func _release_id(plan: Dictionary, context: Dictionary) -> String:
	for source: Dictionary in [context, plan]:
		var candidate := str(source.get("release_id", ""))
		if not candidate.is_empty():
			return candidate
	var raw_snapshot: Variant = plan.get("skill_footprint_snapshot", {})
	if (
		raw_snapshot is Dictionary
		and SkillFootprintSnapshotScript.is_valid(raw_snapshot as Dictionary)
	):
		var snapshot_release_id := str(
			(raw_snapshot as Dictionary).get("release_id", "")
		)
		if not snapshot_release_id.is_empty():
			return snapshot_release_id
	return "%s:cast:%d" % [
		str(plan.get("skill_id", "unbound.caster")),
		Time.get_ticks_usec(),
	]


static func _geometry_cells_grid_steps(plan: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var raw_cells: Variant = plan.get("geometry_cells", [])
	if raw_cells is Array:
		for raw_cell: Variant in raw_cells:
			if raw_cell is Vector2i:
				result.append(raw_cell)
	return result


static func _target_intersects_release_snapshot(
	skill_footprint_snapshot: Dictionary,
	target: Node2D
) -> bool:
	if not SkillFootprintSnapshotScript.is_valid(skill_footprint_snapshot):
		return false
	return SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
		skill_footprint_snapshot,
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			target.global_position
		),
		_target_combat_radius_gu(target)
	)


static func _snapshot_matches_release(
	skill_footprint_snapshot: Dictionary,
	skill_id: String,
	release_id: String
) -> bool:
	return (
		SkillFootprintSnapshotScript.is_valid(skill_footprint_snapshot)
		and str(skill_footprint_snapshot.get("skill_id", "")) == skill_id
		and str(skill_footprint_snapshot.get("release_id", "")) == release_id
	)


static func _node_release_snapshot(node: Node2D) -> Dictionary:
	if node is SkillProjectile:
		return node.skill_footprint_snapshot
	if node is GroundSkillEffect:
		return node.skill_footprint_snapshot
	if node is SummonActor:
		return node.summon_spawn_footprint_snapshot
	return {}


static func _use_non_production_spatial_adapter(
	context: Dictionary,
	result: Dictionary
) -> bool:
	if str(context.get("spatial_test_adapter_id", "")) != (
		NON_PRODUCTION_SPATIAL_ADAPTER_ID
	):
		return false
	result.compatibility_adapter_used = true
	result.compatibility_adapter_id = NON_PRODUCTION_SPATIAL_ADAPTER_ID
	return true


static func _create_target_footprint_snapshot(
	skill_id: String,
	release_id: String,
	target: Node2D
) -> Dictionary:
	var center_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			target.global_position
		)
	)
	return SkillFootprintSnapshotScript.create_target_footprint(
		skill_id,
		release_id,
		center_ground_gu,
		_target_combat_radius_gu(target),
		target.get_instance_id()
	)


static func _target_combat_radius_gu(target: Node2D) -> float:
	for property: Dictionary in target.get_property_list():
		if str(property.get("name", "")) == "combat_radius_gu":
			return maxf(0.0, float(target.get("combat_radius_gu")))
	if target is PlayerCharacter:
		return WorldSpatialRules.actor_combat_radius_gu_from_screen_radius_px(
			ArtSpec.PLAYER_COLLISION_RADIUS_PX
		)
	return 0.0


static func _target_matches_release_snapshot(
	skill_footprint_snapshot: Dictionary,
	target: Node2D
) -> bool:
	if not SkillFootprintSnapshotScript.is_valid(skill_footprint_snapshot):
		return false
	if int(skill_footprint_snapshot.get("target_instance_id", 0)) != target.get_instance_id():
		return false
	return SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
		skill_footprint_snapshot,
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			target.global_position
		),
		_target_combat_radius_gu(target)
	)


static func _apply_direct_spell_damage(
	plan: Dictionary,
	context: Dictionary,
	result: Dictionary,
	target: EnemyActor,
	caster: PlayerCharacter,
	magic_defense_adapter: Callable
) -> void:
	var raw_damage := int(plan.get(
		"damage_before_evasion", plan.get("damage", 0)
	))
	if CombatResolutionRules.anti_magic_eligible(str(plan.get("skill_id", ""))):
		var anti_magic_roll := int(context.get(
			"anti_magic_roll",
			randi_range(0, CombatResolutionRules.ANTI_MAGIC_ROLL_SIDES - 1)
		))
		var resolution := CombatResolutionRules.resolve_direct_spell_damage(
			str(plan.get("skill_id", "")),
			raw_damage,
			target.monster_data,
			anti_magic_roll,
			magic_defense_adapter
		)
		result.target_resolutions.append(resolution)
		if bool(resolution.magic_evaded):
			result.evaded_count += 1
			return
		raw_damage = int(resolution.final_damage)
	if raw_damage > 0:
		target.take_damage(raw_damage, caster)
		result.applied_count += 1


static func fire_wall_positions_ground_gu(
	center_screen_px: Vector2,
	cell_spacing_gu := FIRE_WALL_CELL_SPACING_GU
) -> Array[Vector2]:
	var safe_spacing_gu := maxf(0.0, cell_spacing_gu)
	return [
		center_screen_px,
		center_screen_px + GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			Vector2(safe_spacing_gu, 0.0)
		),
		center_screen_px + GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			Vector2(0.0, safe_spacing_gu)
		),
		center_screen_px + GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			Vector2(safe_spacing_gu, safe_spacing_gu)
		),
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


static func _callable_context_field(context: Dictionary, field: String) -> Callable:
	var candidate: Variant = context.get(field)
	return candidate if candidate is Callable else Callable()


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
