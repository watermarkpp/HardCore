extends RefCounted

const CasterSpellGeometryScript = preload(
	"res://scripts/skills/caster_spell_geometry.gd"
)
const GroundUnitSpaceScript = preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript = preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const SkillDataLoaderScript = preload(
	"res://scripts/skills/skill_data_loader.gd"
)
const CombatUnitLegacyAdapterScript = preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)

const FIRE_WALL_CELL_SPACING_GU = 1.0
const FIRE_WALL_EFFECT_RADIUS_GU = 0.5
const FIRE_WALL_VISUAL_RADIUS_PX = 22.08
## FREEZE-P0.1: fail-closed projection rejection diagnostics (canonical adapter).
var missing_projection_rejection_count = 0

const ProjectileModel := preload("res://scripts/gameplay/world/world_skill_projectile_model.gd")
const GroundModel := preload("res://scripts/gameplay/world/world_skill_ground_model.gd")
const FireWallModel := preload("res://scripts/gameplay/world/world_skill_fire_wall_model.gd")
const GroundManager := preload("res://scripts/gameplay/world/world_skill_ground_manager.gd")
const SummonState = preload("res://scripts/gameplay/actors/summon_actor_model.gd").SummonState
var _bindings: Dictionary
var _world: RefCounted
var _actors: RefCounted
var _visual: RefCounted
var _presentation: RefCounted
var _clock: RefCounted
var _rules: RefCounted

func configure(bindings: Dictionary) -> bool:
	for key: String in ["world","actors","visual","presentation","clock","rules"]:
		if not bindings.get(key) is RefCounted or bindings[key] is Resource: return false
	for method: String in ["allocate_cast_model","discard_cast_birth","create_summon_model","fault"]:
		if not bindings.world.has_method(method): return false
	_bindings = bindings
	_world = bindings.world
	_actors = bindings.actors
	_visual = bindings.visual
	_presentation = bindings.presentation
	_clock = bindings.clock
	_rules = bindings.rules
	return true

func _birth(model: RefCounted, kind: StringName) -> Object:
	if not model.configure_effect(_bindings):
		_world.fault("world_skill_cast_configuration", {"kind":kind})
		return null
	var record: Object = _world.allocate_cast_model(model, kind)
	if record == null or not model.bind_runtime_actor_id(record.get_instance_id()):
		_world.fault("world_skill_cast_allocation", {"kind":kind})
		return null
	if model.has_method("_apply_hit"):
		model.set("_combat_runtime", _bindings.combat)
	return model

func create_projectile_model() -> Object:
	return _birth(ProjectileModel.new(), &"projectile")

func create_ground_model() -> Object:
	return _birth(GroundModel.new(), &"field")

func create_fire_wall_model() -> Object:
	return _birth(FireWallModel.new(), &"field")

func create_summon_model(stable_skill_id: String) -> Object:
	return _world.create_summon_model(stable_skill_id)

func setup_summon_model(summon: Object, owner: Object, display_name: String, power: int,
	learned_level := -1, source_skill_id := "", owner_level_value := -1, maximum_pet_level_value := -1) -> void:
	var owner_link: RefCounted = _actors.capture(owner)
	if owner_link == null:
		_world.fault("world_skill_summon_owner_missing", {})
		return
	summon.setup(owner_link, display_name, power, learned_level, source_skill_id, owner_level_value, maximum_pet_level_value)

func configure_summon_spatial_index(summon: Object, index: RefCounted) -> void:
	var spatial: Object = summon.get("spatial")
	if spatial == null or not spatial.has_method("configure_shared_index"):
		_world.fault("world_skill_summon_spatial_port_missing", {})
		return
	spatial.configure_shared_index(index)

func create_ground_manager(spatial: RefCounted, combat: RefCounted) -> RefCounted:
	return GroundManager.new(spatial, combat, _actors)

func bind_field_retirement(field: Object, callback: Callable) -> void:
	field.retired.connect(callback)

func create_visual(
	plan: Dictionary,
	position: Vector2,
	direction = Vector2.DOWN,
	follow_node: Object = null,
	phase_id = "",
	definition: Dictionary = {}
) -> Object:
	var skill_id = str(plan.get("skill_id", ""))
	if not _visual.is_runtime_ready(skill_id):
		return null
	var profile = _visual.profile(skill_id)
	var visual_profile = _visual.visual_profile(skill_id)
	for key: String in visual_profile:
		if not profile.has(key) and key != "animation":
			profile[key] = visual_profile[key]
	var role = str(plan.get("visual", {}).get("role", ""))
	if role in [
		_visual.ROLE_PROJECTILE,
		_visual.ROLE_GROUND_EFFECT,
		_visual.ROLE_SUMMON_ACTOR,
	]:
		return null
	var visual_geometry_context = CasterSpellGeometryScript.visual_context_from_plan(
		skill_id,
		plan,
		position
	)
	# Inject the presentation profile so SkyStrike/Beam can consume
	# anchor.type, animation.scale_mode, geometry_binding etc.
	if not visual_profile.is_empty():
		visual_geometry_context["visual_profile"] = visual_profile.duplicate(true)
	var visual_radius_px = maxf(0.0, float(plan.get("visual_radius_px", 0.0)))
	if role == _visual.ROLE_LINE_EFFECT:
		var geometry_offsets: Array = visual_geometry_context.get(
			"geometry_screen_offsets_px", []
		)
		# A canonical line may be truncated to zero GU by terrain.  Its explicit
		# empty point list is authoritative and must not fall through to the full
		# 5/8-GU definition radius: that produced a full visible line while the
		# shared damage strip contained no area and therefore could hit nothing.
		var canonical_geometry_was_supplied = (
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
			var geometry: Dictionary = (SkillDataLoaderScript.skill(skill_id) if definition.is_empty() else definition).get("geometry", {})
			var effect_length_gu = float(geometry.get("effect_length_gu", 0.0))
			var direction_ground_gu = (
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
	# Allocate only after geometry admission: an explicit empty canonical line
	# must not leave an unparented visual behind when it is rejected above.
	var effect = _presentation.create_visual_model(profile)
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

func create_projectile(plan: Dictionary, origin: Vector2, direction: Vector2, color = Color.WHITE, definition: Dictionary = {}) -> Object:
	if (
		str(plan.get("operation", "")) != "projectile_damage"
		or str(plan.get("visual", {}).get("role", ""))
			!= _visual.ROLE_PROJECTILE
		or not _visual.is_runtime_ready(str(plan.get("skill_id", "")))
	):
		return null
	var projectile = create_projectile_model()
	var direction_ground_gu = (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(direction)
		.normalized()
	)
	var formal_geometry: Dictionary = (SkillDataLoaderScript.skill(str(plan.get("skill_id", ""))) if definition.is_empty() else definition).get("geometry", {})
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
		var mapped_context = int(
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
			_world.discard_cast_birth(projectile)
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

func create_ground_effects(
	plan: Dictionary,
	center: Vector2,
	color = Color.WHITE,
	source_actor: Object = null
) -> Array[Object]:
	var effects: Array[Object] = []
	if (
		str(plan.get("operation", "")) != "ground_dot"
		or str(plan.get("visual", {}).get("role", ""))
			!= _visual.ROLE_GROUND_EFFECT
		or not _visual.is_runtime_ready(str(plan.get("skill_id", "")))
	):
		return effects
	var cell_spacing_gu = maxf(
		0.0,
		float(plan.get("cell_spacing_gu", FIRE_WALL_CELL_SPACING_GU))
	)
	var radius_gu = maxf(
		0.0,
		float(plan.get("ground_effect_radius_gu", FIRE_WALL_EFFECT_RADIUS_GU))
	)
	var visual_radius_px = maxf(
		1.0,
		float(plan.get("visual_radius_px", FIRE_WALL_VISUAL_RADIUS_PX))
	)
	var release_id = str(plan.get("release_id", ""))
	if release_id.is_empty():
		release_id = "%s:ground:%d" % [
			str(plan.get("skill_id", "wizard.fire_wall")),
			_clock.now_usec(),
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
	var effect_positions = fire_wall_positions_ground_gu(
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
		var effect = create_ground_model()
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

func create_cast_models_from_canonical_plan(
	plan: Dictionary,
	origin: Vector2,
	direction = Vector2.DOWN,
	color = Color.WHITE,
	target: Object = null,
	owner: Object = null,
	spiritual_power = 1,
	owner_level = 1,
	summon_sink = Callable(),
	runtime_context: Dictionary = {}
) -> Array[Object]:
	var nodes: Array[Object] = []
	var skill_id = str(plan.get("skill_id", ""))
	var release_id = str(plan.get("release_id", ""))
	var snapshot: Dictionary = plan.get("canonical_snapshot", {})
	var coordinate_context = _coordinate_context_from_snapshot(snapshot)
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
		var node_plan = {
			"operation": str(
				descriptor.get("operation", "projectile_damage")
			),
			"success": true,
			"skill_id": skill_id,
			"release_id": release_id,
			"damage": int(descriptor.get("raw_power", 0)),
			"visual": {"role": _visual.ROLE_PROJECTILE},
			"snapshot_coordinate_context": coordinate_context,
			"skill_footprint_snapshot": snapshot,
		}
		var projectile = create_projectile(
			node_plan,
			origin,
			direction,
			color,
			runtime_context.get("action_definition", {})
		)
		if projectile != null:
			_configure_projectile_runtime(projectile, runtime_context)
			nodes.append(projectile)
	for raw_descriptor: Variant in plan.get("ground_effect_descriptors", []):
		if not raw_descriptor is Dictionary:
			continue
		var descriptor: Dictionary = raw_descriptor
		var node_plan = {
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
			"visual": {"role": _visual.ROLE_GROUND_EFFECT},
			"snapshot_coordinate_context": coordinate_context,
			"skill_footprint_snapshot": snapshot,
		}
		for effect: Object in create_ground_effects(
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
		var summon = create_summon_actor(
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
		var role = str(action.get("role", ""))
		if role in [
			_visual.ROLE_PROJECTILE,
			_visual.ROLE_GROUND_EFFECT,
			_visual.ROLE_SUMMON_ACTOR,
		]:
			continue
		var presentation_plan = {
			"operation": "canonical_visual_only",
			"success": true,
			"skill_id": skill_id,
			"release_id": release_id,
			"visual": {"role": role},
			"visual_duration": action.get(
				"visual_duration",
				_visual.animation_duration(skill_id)
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
		var attachment = str(
			_visual.render_policy(skill_id).get(
				"attachment_policy",
				"world_anchor"
			)
		)
		var visual_position = origin
		var follow_node: Object = null
		match attachment:
			"target_actor":
				follow_node = target
				visual_position = (
					_actors.position_screen_px(target)
					if _actors.is_runtime_present(target)
					else origin
				)
			"caster_actor":
				follow_node = owner
				visual_position = (
					_actors.position_screen_px(owner)
					if _actors.is_runtime_present(owner)
					else origin
				)
			"world_anchor":
				visual_position = (
					origin
					if role in [
						_visual.ROLE_SELF_EFFECT,
						_visual.ROLE_SELF_AREA,
						_visual.ROLE_LINE_EFFECT,
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
							_actors.position_screen_px(target)
							if _actors.is_runtime_present(target)
							else origin
						)
					)
				)
		var visual = create_visual(
			presentation_plan,
			visual_position,
			direction,
			follow_node,
			"",
			runtime_context.get("action_definition", {})
		)
		if visual != null:
			nodes.append(visual)
	return nodes

func _configure_projectile_runtime(
	projectile: Object,
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
	var map_id = int(runtime_context.get("runtime_map_id", -1))
	if map_id >= 0 and ground_to_screen.is_valid():
		projectile.configure_runtime_map_projection(
			map_id,
			ground_to_screen,
			screen_to_ground
		)
	var magic_defense_adapter: Callable = runtime_context.get(
		"magic_defense_adapter", Callable()
	)
	var caster: Object = runtime_context.get("caster")
	if magic_defense_adapter.is_valid() and caster != null:
		projectile.configure_runtime_resolution(caster, magic_defense_adapter)

func _configure_ground_runtime(
	effect: Object,
	runtime_context: Dictionary
) -> void:
	# Ground effects read their runtime projection from the snapshot context
	# already; nothing else is required for the canonical adapter path.
	pass

func _coordinate_context_from_snapshot(
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

func create_summon_actor(
	plan: Dictionary,
	owner: Object,
	spiritual_power: int,
	owner_level: int,
	position: Vector2
) -> Object:
	if str(plan.get("operation", "")) != "summon" or owner == null or not bool(plan.get("success", false)):
		return null
	var summon = create_summon_model(str(plan.get("skill_id", "")))
	_actors.set_position_screen_px(summon, position)
	setup_summon_model(summon, 
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
		var mapped_context = int(
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
			_world.discard_cast_birth(summon)
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

func _expected_validation_context(
	coordinate_context: Dictionary
) -> Dictionary:
	var expected_context = coordinate_context.duplicate(true)
	if expected_context.is_empty():
		return expected_context
	expected_context["expected_runtime_map_id"] = (
		expected_context.get("runtime_map_id", -1)
	)
	return expected_context

func _snapshot_strict_ok(
	snapshot: Dictionary,
	coordinate_context: Dictionary
) -> bool:
	return bool(SkillFootprintSnapshotScript.validate_for_consumer(
		snapshot,
		_expected_validation_context(coordinate_context),
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	).get("valid", false))

func fire_wall_positions_ground_gu(
	center_screen_px: Vector2,
	cell_spacing_gu = FIRE_WALL_CELL_SPACING_GU
) -> Array[Vector2]:
	var safe_spacing_gu = maxf(0.0, cell_spacing_gu)
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
