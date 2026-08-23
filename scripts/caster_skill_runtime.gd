class_name CasterSkillRuntime
extends RefCounted

const CasterSpellGeometryScript := preload(
	"res://scripts/skills/caster_spell_geometry.gd"
)
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const SkillDataLoaderScript := preload(
	"res://scripts/skills/skill_data_loader.gd"
)
const CombatUnitLegacyAdapterScript := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)

const FIRE_WALL_CELL_SPACING_GU := 1.0
const FIRE_WALL_EFFECT_RADIUS_GU := 0.5
const FIRE_WALL_VISUAL_RADIUS_PX := 22.08
## FREEZE-P0.1: fail-closed projection rejection diagnostics (canonical adapter).
static var missing_projection_rejection_count := 0
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
	# Inject the presentation profile so SkyStrike/Beam can consume
	# anchor.type, animation.scale_mode, geometry_binding etc.
	if not visual_profile.is_empty():
		visual_geometry_context["visual_profile"] = visual_profile.duplicate(true)
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
		str(plan.get("release_id", "")),
		(
			plan.get("skill_footprint_snapshot", {})
			if plan.get("skill_footprint_snapshot", {}) is Dictionary
			else {}
		)
	)
	var coordinate_context: Variant = plan.get(
		"snapshot_coordinate_context", {}
	)
	if coordinate_context is Dictionary and not (
		coordinate_context as Dictionary
	).is_empty():
		var mapped_context := int(
			(coordinate_context as Dictionary).get("runtime_map_id", -1)
		)
		var context_screen_to_ground: Callable = (
			(coordinate_context as Dictionary).get(
				"screen_to_ground_position_px",
				Callable()
			) as Callable
		)
		if mapped_context >= 0 and not context_screen_to_ground.is_valid():
			# FREEZE-P0.1: refuse to create a mapped projectile without a
			# declared projection; never re-plan, just reject the node.
			missing_projection_rejection_count += 1
			projectile.free()
			return null
		projectile.configure_runtime_map_projection(
			mapped_context,
			(coordinate_context as Dictionary).get(
				"ground_position_gu_to_screen_position_px",
				Callable()
			),
			(coordinate_context as Dictionary).get(
				"screen_to_ground_position_px",
				Callable()
			)
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
	var coordinate_context: Dictionary = (
		plan.get("snapshot_coordinate_context", {})
		if plan.get("snapshot_coordinate_context", {}) is Dictionary
		else {}
	)
	if coordinate_context.is_empty():
		# Q1-B: without an explicit runtime map projection the factory must not
		# fall back to a V1 snapshot. The caller supplies the coordinate context.
		return effects
	var effect_positions := fire_wall_positions_ground_gu(
		center,
		cell_spacing_gu
	)
	if not _snapshot_strict_ok(
		release_snapshot,
		coordinate_context
	):
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
				inferred_cells_grid_steps,
				coordinate_context
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
			release_snapshot,
			_expected_validation_context(
				coordinate_context
			)
		)
		effect.configure_runtime_source(source_actor)
		effects.append(effect)
	return effects


## Q3-A / HC-P1-009: read-only adapter that creates cast nodes from a frozen
## canonical skill execution plan. It consumes ONLY:
##   release_id, skill_id, runtime_map_id, canonical_snapshot,
##   projectile/ground/summon descriptors and presentation_actions.
## It never re-selects targets, never re-quotes resources, never commits
## cooldowns, never rebuilds the release snapshot and never regenerates a
## release id. The plan is never mutated.
static func create_cast_nodes_from_canonical_plan(
	plan: Dictionary,
	origin: Vector2,
	direction := Vector2.DOWN,
	color := Color.WHITE,
	target: Node2D = null,
	owner: PlayerCharacter = null,
	spiritual_power := 1,
	owner_level := 1,
	summon_sink := Callable(),
	runtime_context: Dictionary = {}
) -> Array[Node2D]:
	var nodes: Array[Node2D] = []
	var skill_id := str(plan.get("skill_id", ""))
	var release_id := str(plan.get("release_id", ""))
	var snapshot: Dictionary = plan.get("canonical_snapshot", {})
	var coordinate_context := _coordinate_context_from_snapshot(snapshot)
	if not coordinate_context.is_empty():
		var screen_to_ground_from_context: Callable = runtime_context.get(
			"screen_to_ground_position_px", Callable()
		)
		if screen_to_ground_from_context.is_valid():
			coordinate_context["screen_to_ground_position_px"] = (
				screen_to_ground_from_context
			)
		var ground_to_screen_from_context: Callable = runtime_context.get(
			"ground_gu_to_screen_position_px", Callable()
		)
		if ground_to_screen_from_context.is_valid():
			coordinate_context["ground_position_gu_to_screen_position_px"] = (
				ground_to_screen_from_context
			)
	for raw_descriptor: Variant in plan.get("projectile_descriptors", []):
		if not raw_descriptor is Dictionary:
			continue
		var descriptor: Dictionary = raw_descriptor
		var node_plan := {
			"operation": str(
				descriptor.get("operation", "projectile_damage")
			),
			"success": true,
			"skill_id": skill_id,
			"release_id": release_id,
			"damage": int(descriptor.get("raw_power", 0)),
			"visual": {"role": CasterSkillVisualRegistry.ROLE_PROJECTILE},
			"snapshot_coordinate_context": coordinate_context,
			"skill_footprint_snapshot": snapshot,
		}
		var projectile := create_projectile(
			node_plan,
			origin,
			direction,
			color
		)
		if projectile != null:
			_configure_projectile_runtime(projectile, runtime_context)
			nodes.append(projectile)
	for raw_descriptor: Variant in plan.get("ground_effect_descriptors", []):
		if not raw_descriptor is Dictionary:
			continue
		var descriptor: Dictionary = raw_descriptor
		var node_plan := {
			"operation": str(descriptor.get("operation", "ground_dot")),
			"success": true,
			"skill_id": skill_id,
			"release_id": release_id,
			"damage": int(descriptor.get("raw_power", 0)),
			"duration_seconds": float(
				descriptor.get("duration_seconds", 1.0)
			),
			"tick_interval_seconds": float(
				descriptor.get("tick_interval_ms", 1000)
			) / 1000.0,
			"ground_effect_radius_gu": float(
				descriptor.get("radius_gu", 0.5)
			),
			"visual": {"role": CasterSkillVisualRegistry.ROLE_GROUND_EFFECT},
			"snapshot_coordinate_context": coordinate_context,
			"skill_footprint_snapshot": snapshot,
		}
		for effect: GroundSkillEffect in create_ground_effects(
			node_plan,
			origin,
			color,
			owner
		):
			_configure_ground_runtime(effect, runtime_context)
			nodes.append(effect)
	for raw_descriptor: Variant in plan.get("summon_descriptors", []):
		if not raw_descriptor is Dictionary:
			continue
		var descriptor: Dictionary = raw_descriptor
		if summon_sink.is_valid():
			# The caller owns summon lifecycle (e.g. GameRoot's main pet); the
			# adapter hands the frozen descriptor over without creating a node.
			summon_sink.call(descriptor, plan)
			continue
		if str(descriptor.get("operation", "")) == "recall_existing_main_pet":
			# Recall requires the lifecycle owner; a node-only fallback must never
			# reinterpret it as a fresh summon.
			continue
		var summon := create_summon_actor(
			{
				"operation": "summon",
				"success": bool(descriptor.get("spawned", true)),
				"skill_id": skill_id,
				"release_id": release_id,
				"display_name": str(descriptor.get("template_id", "")),
				"skill_level": int(
					descriptor.get("initial_pet_level", 0)
				),
				"max_pet_level": int(
					descriptor.get("max_pet_level", -1)
				),
				"template_id": str(descriptor.get("template_id", "")),
				"spawn_footprint_snapshot": descriptor.get(
					"spawn_footprint_snapshot", {}
				),
			},
			owner,
			spiritual_power,
			owner_level,
			origin
		)
		if summon != null:
			nodes.append(summon)
	for raw_action: Variant in plan.get("presentation_actions", []):
		if not raw_action is Dictionary:
			continue
		var action: Dictionary = raw_action
		if str(action.get("type", "")) != "visual":
			continue
		var role := str(action.get("role", ""))
		if role in [
			CasterSkillVisualRegistry.ROLE_PROJECTILE,
			CasterSkillVisualRegistry.ROLE_GROUND_EFFECT,
			CasterSkillVisualRegistry.ROLE_SUMMON_ACTOR,
		]:
			continue
		var presentation_plan := {
			"operation": "canonical_visual_only",
			"success": true,
			"skill_id": skill_id,
			"release_id": release_id,
			"visual": {"role": role},
			"visual_duration": action.get(
				"visual_duration",
				CasterSkillVisualRegistry.animation_duration(skill_id)
			),
			"visual_radius_px": float(
				action.get("visual_radius_px", 0.0)
			),
			"snapshot_validation_policy": (
				SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
			),
			"snapshot_validation_context": action.get(
				"snapshot_validation_context", {}
			),
			"canonical_geometry_contract": action.get(
				"canonical_geometry_contract",
				CasterSpellGeometryScript.CONTRACT_ID
			),
			"geometry_origin_screen_px": action.get(
				"geometry_origin_screen_px", Vector2.ZERO
			),
			"geometry_grid_cells": action.get("geometry_grid_cells", []),
			"geometry_screen_points_px": action.get(
				"geometry_screen_points_px", []
			),
			"ground_gu_to_screen_position_px": action.get(
				"ground_gu_to_screen_position_px", Callable()
			),
			"snapshot_coordinate_context": coordinate_context,
			"skill_footprint_snapshot": snapshot,
		}
		# Q3-B: the canonical presentation consumer resolves the visual
		# attachment exactly like the legacy create_cast_nodes entry (same
		# registry attachment policy), so self/caster visuals keep following
		# the caster instead of the (possibly null) cast target.
		var attachment := str(
			CasterSkillVisualRegistry.render_policy(skill_id).get(
				"attachment_policy",
				"world_anchor"
			)
		)
		var visual_position := origin
		var follow_node: Node2D = null
		match attachment:
			"target_actor":
				follow_node = target
				visual_position = (
					target.global_position
					if is_instance_valid(target)
					else origin
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
					else (
						action.get(
							"target_position_screen_px",
							origin
						)
						if action.get(
							"target_position_screen_px", Vector2.ZERO
						) is Vector2
						and (action.get(
							"target_position_screen_px", Vector2.ZERO
						) as Vector2) != Vector2.ZERO
						else (
							target.global_position
							if is_instance_valid(target)
							else origin
						)
					)
				)
		var visual := create_visual(
			presentation_plan,
			visual_position,
			direction,
			follow_node,
			""
		)
		if visual != null:
			nodes.append(visual)
	return nodes


static func _configure_projectile_runtime(
	projectile: SkillProjectile,
	runtime_context: Dictionary
) -> void:
	var spatial_index: Variant = runtime_context.get("combat_spatial_index")
	if spatial_index != null:
		projectile.configure_spatial_index(spatial_index)
	var ground_to_screen: Callable = runtime_context.get(
		"ground_gu_to_screen_position_px", Callable()
	)
	var screen_to_ground: Callable = runtime_context.get(
		"screen_to_ground_position_px", Callable()
	)
	var map_id := int(runtime_context.get("runtime_map_id", -1))
	if map_id >= 0 and ground_to_screen.is_valid():
		projectile.configure_runtime_map_projection(
			map_id,
			ground_to_screen,
			screen_to_ground
		)
	var magic_defense_adapter: Callable = runtime_context.get(
		"magic_defense_adapter", Callable()
	)
	var caster: Node2D = runtime_context.get("caster")
	if magic_defense_adapter.is_valid() and caster != null:
		projectile.configure_runtime_resolution(caster, magic_defense_adapter)


static func _configure_ground_runtime(
	effect: GroundSkillEffect,
	runtime_context: Dictionary
) -> void:
	# Ground effects read their runtime projection from the snapshot context
	# already; nothing else is required for the canonical adapter path.
	pass


static func _coordinate_context_from_snapshot(
	snapshot: Dictionary
) -> Dictionary:
	if snapshot.is_empty():
		return {}
	return {
		"coordinate_space": str(snapshot.get("coordinate_space", "")),
		"runtime_map_id": int(snapshot.get("runtime_map_id", -1)),
		"origin_ground_gu": snapshot.get("origin_ground_gu", Vector2.ZERO),
		"projection_origin_ground_gu": snapshot.get(
			"projection_origin_ground_gu", Vector2.ZERO
		),
		"ground_position_gu_to_screen_position_px": snapshot.get(
			"ground_position_gu_to_screen_position_px", Callable()
		),
	}


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
		maxi(1, owner_level),
		int(plan.get("max_pet_level", -1))
	)
	var coordinate_context: Variant = plan.get(
		"snapshot_coordinate_context", {}
	)
	if coordinate_context is Dictionary and not (
		coordinate_context as Dictionary
	).is_empty():
		var mapped_context := int(
			(coordinate_context as Dictionary).get("runtime_map_id", -1)
		)
		var context_screen_to_ground: Callable = (
			(coordinate_context as Dictionary).get(
				"screen_to_ground_position_px",
				Callable()
			) as Callable
		)
		if mapped_context >= 0 and not context_screen_to_ground.is_valid():
			missing_projection_rejection_count += 1
			summon.free()
			return null
		summon.configure_runtime_map_projection(
			mapped_context,
			(coordinate_context as Dictionary).get(
				"ground_position_gu_to_screen_position_px",
				Callable()
			),
			(coordinate_context as Dictionary).get(
				"screen_to_ground_position_px",
				Callable()
			)
		)
	summon.configure_spawn_release_footprint(str(plan.get("release_id", "")))
	return summon


static func _expected_validation_context(
	coordinate_context: Dictionary
) -> Dictionary:
	var expected_context := coordinate_context.duplicate(true)
	if expected_context.is_empty():
		return expected_context
	expected_context["expected_runtime_map_id"] = (
		expected_context.get("runtime_map_id", -1)
	)
	return expected_context


static func _snapshot_strict_ok(
	snapshot: Dictionary,
	coordinate_context: Dictionary
) -> bool:
	return bool(SkillFootprintSnapshotScript.validate_for_consumer(
		snapshot,
		_expected_validation_context(coordinate_context),
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	).get("valid", false))


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
