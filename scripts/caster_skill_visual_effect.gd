class_name CasterSkillVisualEffect
extends Node2D

const AnimationPlayerScript := preload("res://scripts/caster_skill_animation_player.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)

const COMPLETION_GRACE_SECONDS := 0.05
const MAGIC_SHIELD_SKILL_ID := "wizard.magic_shield"
const MAGIC_SHIELD_VISUAL_GROUP := "wizard_magic_shield_persistent_visual"
const MAGIC_SHIELD_VISUAL_CONTRACT_ID := (
	"skills.wizard.magic_shield.primary_actor_footpoint_centered_behind_body.v1"
)
const ACTOR_VISIBILITY_RENDER_CONTRACT_ID := (
	"skills.caster.effect.actor_visibility_negative_one_render_lane.v1"
)
const ACTOR_VISIBILITY_Z_INDEX := -1
const ATTACHMENT_DRAW_ORDER_BEHIND_ACTOR := "behind_attached_actor_same_footpoint"
const SINGLE_ACTIVE_LASER_VISUAL_GROUP := "wizard_laser_single_active_visual"
const SINGLE_ACTIVE_LASER_VISUAL_CONTRACT_ID := (
	"skills.wizard.laser.single_active_visual_per_caster.v1"
)
const FORMAL_LINE_VISUAL_CORE_CONTRACT_ID := (
	"skills.caster.line_visual.projected_footprint_core.v1"
)
const FORMAL_SNAPSHOT_VISUAL_CORE_CONTRACT_ID := (
	"skills.caster.snapshot_visual.projected_core.v1"
)
const DEBUG_SKILL_VISUAL_GEOMETRY_CONTRACT_ID := (
	"skills.visual_geometry.debug_overlay.opt_in.v1"
)
const LASER_DECORATION_ALPHA := 0.46
const HELLFIRE_DECORATION_ALPHA := 1.0

var skill_id := ""
var phase_id := ""
var visual_role := ""
var radius := 72.0
var lifetime := 0.8
var direction := Vector2.DOWN
var target_node: Node2D
var visual_loaded := false
var rejection_reason := ""
var _skip_legacy_laser_single_active := false
var _elapsed := 0.0
var _completion_elapsed := 0.0
var _sprites: Array[Sprite2D] = []
var _playback_strategy := "frame_sequence"
var _attachment_policy := "world_anchor"
var _attachment_draw_order := ""
var _hellfire_records: Array[Dictionary] = []
var _hellfire_tick_elapsed := 0.0
var _hellfire_emissions := 0
var _hellfire_total_emissions := 0
var _hellfire_frame_count := 0
var _hellfire_finished := false
var _hellfire_step_seconds := 0.05
var _hellfire_step_distance := 25.0
var _geometry_screen_offsets_px: Array[Vector2] = []
var _hellfire_emission_offsets: Array[Vector2] = []
var _desired_sprite_extent_px := 0.0
var _desired_sprite_footprint_px := Vector2.ZERO
var _desired_sprite_axis_extent_px := 0.0
var _desired_sprite_cross_axis_extent_px := 0.0
var _visual_axis_screen_px := Vector2.ZERO
var _skill_footprint_snapshot: Dictionary = {}
var _formal_core_polygon_screen_offset_px := PackedVector2Array()
var _formal_core_polygons_screen_offset_px: Array[PackedVector2Array] = []
var _formal_core_axis_screen_offset_px := Vector2.ZERO
var _formal_core_polygon: Polygon2D
var _formal_core_polygons: Array[Polygon2D] = []
var _formal_core_glow_layers: Array[Polygon2D] = []
var _snapshot_shape_type := ""
var _snapshot_anchor_policy := ""
var _snapshot_anchor_screen_px := Vector2.ZERO
var _snapshot_visual_core_policy := ""
var _snapshot_visual_projection_contract_id := ""
var _decoration_sprite_transform_policy := ""
var _snapshot_validation_context: Dictionary = {}
var _snapshot_validation_policy: StringName = (
	SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
)
var debug_skill_visual_geometry := false
var _debug_geometry_overlay: Node2D
var _debug_geometry_lines: Array[Line2D] = []
var _debug_geometry_metadata: Dictionary = {}


func setup(
	position_value: Vector2,
	source_skill_id: String,
	radius_value := 72.0,
	lifetime_value := 0.8,
	direction_value := Vector2.DOWN,
	target: Node2D = null,
	requested_phase_id := "",
	visual_geometry_context: Dictionary = {}
) -> void:
	global_position = position_value.round()
	skill_id = ProfessionRules.skill_id(source_skill_id)
	phase_id = requested_phase_id
	radius = maxf(20.0, radius_value)
	lifetime = maxf(0.1, lifetime_value)
	direction = direction_value.normalized() if direction_value.length_squared() > 0.0 else Vector2.DOWN
	target_node = target
	_desired_sprite_extent_px = maxf(
		0.0,
		float(visual_geometry_context.get("desired_sprite_extent_px", 0.0))
	)
	_desired_sprite_footprint_px = visual_geometry_context.get(
		"desired_sprite_footprint_px", Vector2.ZERO
	)
	_desired_sprite_axis_extent_px = maxf(
		0.0,
		float(visual_geometry_context.get("desired_sprite_axis_extent_px", 0.0))
	)
	_desired_sprite_cross_axis_extent_px = maxf(
		0.0,
		float(visual_geometry_context.get(
			"desired_sprite_cross_axis_extent_px", 0.0
		))
	)
	_visual_axis_screen_px = visual_geometry_context.get(
		"visual_axis_screen_px", Vector2.ZERO
	)
	var raw_snapshot: Variant = visual_geometry_context.get(
		"skill_footprint_snapshot", {}
	)
	_snapshot_validation_context = (
		visual_geometry_context.get("snapshot_validation_context", {})
		if visual_geometry_context.get(
			"snapshot_validation_context", {}
		) is Dictionary
		else {}
	)
	var raw_policy: Variant = visual_geometry_context.get(
		"snapshot_validation_policy",
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	)
	_snapshot_validation_policy = (
		raw_policy
		if raw_policy is StringName
		else SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	)
	if raw_snapshot is Dictionary and _snapshot_ok(raw_snapshot):
		_skill_footprint_snapshot = raw_snapshot
	_snapshot_shape_type = str(visual_geometry_context.get(
		"snapshot_shape_type", ""
	))
	_snapshot_anchor_policy = str(visual_geometry_context.get(
		"snapshot_anchor_policy", ""
	))
	_snapshot_anchor_screen_px = visual_geometry_context.get(
		"snapshot_anchor_screen_px", global_position
	)
	_snapshot_visual_core_policy = str(visual_geometry_context.get(
		"snapshot_visual_core_policy", ""
	))
	_snapshot_visual_projection_contract_id = str(
		visual_geometry_context.get(
			"snapshot_visual_projection_contract_id", ""
		)
	)
	_decoration_sprite_transform_policy = str(visual_geometry_context.get(
		"decoration_sprite_transform_policy", ""
	))
	var centered_snapshot_anchor := _snapshot_shape_type in [
		SkillFootprintSnapshotScript.SHAPE_TARGET_FOOTPRINT,
		SkillFootprintSnapshotScript.SHAPE_CIRCLE,
		SkillFootprintSnapshotScript.SHAPE_SECTOR_ARC,
	]
	var snapshot_polygon_field := (
		"snapshot_projected_polygons_screen_offset_px"
		if centered_snapshot_anchor
		else "snapshot_projected_polygons_local_to_effect_px"
	)
	var raw_snapshot_polygons: Variant = visual_geometry_context.get(
		snapshot_polygon_field, []
	)
	if raw_snapshot_polygons is Array:
		for raw_snapshot_polygon: Variant in raw_snapshot_polygons:
			if raw_snapshot_polygon is PackedVector2Array:
				_formal_core_polygons_screen_offset_px.append(
					(raw_snapshot_polygon as PackedVector2Array).duplicate()
				)
	if (
		centered_snapshot_anchor
		and not _snapshot_visual_projection_contract_id.is_empty()
	):
		# Target/self-centered effects consume the snapshot's exact ground anchor.
		# Decoration pixels keep their source transform and are never used to infer
		# this position or the damage extent.
		global_position = _snapshot_anchor_screen_px
	var raw_core_polygon: Variant = visual_geometry_context.get(
		"formal_core_polygon_screen_offset_px", PackedVector2Array()
	)
	if raw_core_polygon is PackedVector2Array:
		_formal_core_polygon_screen_offset_px = raw_core_polygon.duplicate()
		if (
			not _formal_core_polygon_screen_offset_px.is_empty()
			and _formal_core_polygons_screen_offset_px.is_empty()
		):
			_formal_core_polygons_screen_offset_px.append(
				_formal_core_polygon_screen_offset_px.duplicate()
			)
	if (
		_formal_core_polygon_screen_offset_px.is_empty()
		and not _formal_core_polygons_screen_offset_px.is_empty()
	):
		_formal_core_polygon_screen_offset_px = (
			_formal_core_polygons_screen_offset_px[0].duplicate()
		)
	_formal_core_axis_screen_offset_px = visual_geometry_context.get(
		"formal_core_axis_screen_offset_px", Vector2.ZERO
	)
	debug_skill_visual_geometry = bool(visual_geometry_context.get(
		"debug_skill_visual_geometry", false
	))
	for raw_offset: Variant in visual_geometry_context.get("geometry_screen_offsets_px", []):
		if raw_offset is Vector2:
			_geometry_screen_offsets_px.append(raw_offset)


func _ready() -> void:
	add_to_group("zone_content")
	if skill_id == "wizard.laser" and is_instance_valid(target_node) and not _skip_legacy_laser_single_active:
		_replace_existing_laser_visual()
		add_to_group(SINGLE_ACTIVE_LASER_VISUAL_GROUP)
		set_meta(
			"single_active_visual_contract",
			SINGLE_ACTIVE_LASER_VISUAL_CONTRACT_ID
		)
	if skill_id == MAGIC_SHIELD_SKILL_ID:
		_replace_existing_magic_shield_visual()
		add_to_group(MAGIC_SHIELD_VISUAL_GROUP)
		set_meta("magic_shield_visual_contract", MAGIC_SHIELD_VISUAL_CONTRACT_ID)
	var entry := CasterSkillVisualRegistry.profile(skill_id)
	visual_role = str(entry.get("role", ""))
	# Generic spell visuals live in the actor-composited world, while projectiles,
	# ground fields and summons have dedicated runtimes.  A fixed z=-1 lane keeps
	# every generic effect below z=0 actors without lifting the player above map
	# occluders or monsters.  Relying on a tiny y-sort offset was not a draw-order
	# contract: equal/near-equal footpoints could still make a full-frame effect
	# cover the actor, and the result changed while the actor moved.
	z_as_relative = true
	z_index = ACTOR_VISIBILITY_Z_INDEX
	set_meta(
		"actor_visibility_render_contract",
		ACTOR_VISIBILITY_RENDER_CONTRACT_ID
	)
	if not CasterSkillVisualRegistry.is_runtime_ready(skill_id):
		rejection_reason = CasterSkillVisualRegistry.runtime_readiness_reason(skill_id)
		target_node = null
		return
	var animation := CasterSkillVisualRegistry.animation_profile(skill_id, phase_id)
	if animation.get("contract", "") != "caster_skill_animation.v1":
		rejection_reason = "missing_animation_phase:%s" % phase_id
		target_node = null
		return
	if visual_role in [
		CasterSkillVisualRegistry.ROLE_PROJECTILE,
		CasterSkillVisualRegistry.ROLE_GROUND_EFFECT,
		CasterSkillVisualRegistry.ROLE_SUMMON_ACTOR,
	]:
		rejection_reason = "role_requires_specialized_runtime:%s" % visual_role
		target_node = null
		return
	var render := CasterSkillVisualRegistry.render_policy(skill_id, phase_id)
	_attachment_policy = str(render.get("attachment_policy", "world_anchor"))
	_attachment_draw_order = str(render.get("attachment_draw_order", ""))
	if _attachment_policy not in ["target_actor", "caster_actor"]:
		target_node = null
	elif is_instance_valid(target_node):
		# Establish the exact sort key before the first drawable frame. Waiting for
		# _process() left one rounded frame that could briefly cover the actor.
		_sync_actor_attachment_position()
	_playback_strategy = str(render.get("playback_strategy", "frame_sequence"))
	_install_formal_snapshot_visual_core()
	_install_debug_skill_visual_geometry_overlay()
	lifetime = maxf(
		lifetime,
		CasterSkillVisualRegistry.animation_duration(skill_id, phase_id)
		+ COMPLETION_GRACE_SECONDS
	)
	if _playback_strategy == "firegun_trail" and skill_id == "wizard.hellfire":
		_install_hellfire_trail(render)
	else:
		_install_single()
	visual_loaded = not _sprites.is_empty()
	if not visual_loaded and rejection_reason.is_empty():
		rejection_reason = "animation_player_failed"


func _process(delta: float) -> void:
	_elapsed += delta
	if is_instance_valid(target_node):
		_sync_actor_attachment_position()
	if _is_persistent_magic_shield_visual():
		if not _magic_shield_state_is_active():
			queue_free()
			return
		# The source sequence is the shield forming. Play it once, then retain its
		# complete final frame until either duration or absorption capacity ends.
		# Re-looping the formation frames makes the shield repeatedly collapse.
		if visual_loaded and _all_playback_complete():
			return
	if _playback_strategy == "firegun_trail" and visual_loaded:
		_process_hellfire(delta)
		if _hellfire_finished:
			queue_free()
			return
	elif visual_loaded and _all_playback_complete():
		_completion_elapsed += delta
		if _completion_elapsed >= COMPLETION_GRACE_SECONDS:
			queue_free()
			return
	if _elapsed >= lifetime + 0.5:
		queue_free()


func _sync_actor_attachment_position() -> void:
	# Preserve the exact fractional actor footpoint. Draw order is owned by the
	# explicit actor-visibility z lane above; position is never perturbed to fake
	# sorting, so attached effects cannot flicker across half-pixel boundaries.
	global_position = target_node.global_position


func is_persistent_magic_shield_visual() -> bool:
	return _is_persistent_magic_shield_visual()


func _is_persistent_magic_shield_visual() -> bool:
	return skill_id == MAGIC_SHIELD_SKILL_ID and is_instance_valid(target_node)


func _magic_shield_state_is_active() -> bool:
	if not is_instance_valid(target_node) or not target_node.has_method("magic_shield_snapshot"):
		return false
	var snapshot: Variant = target_node.call("magic_shield_snapshot")
	return snapshot is Dictionary and bool(snapshot.get("active", false))


func _replace_existing_magic_shield_visual() -> void:
	if not is_instance_valid(target_node) or get_tree() == null:
		return
	for existing: Node in get_tree().get_nodes_in_group(MAGIC_SHIELD_VISUAL_GROUP):
		if (
			existing == self
			or not existing is CasterSkillVisualEffect
			or existing.target_node != target_node
		):
			continue
		if existing is CanvasItem:
			existing.visible = false


func _replace_existing_laser_visual() -> void:
	if not is_instance_valid(target_node) or get_tree() == null:
		return
	for existing: Node in get_tree().get_nodes_in_group(
		SINGLE_ACTIVE_LASER_VISUAL_GROUP
	):
		if (
			existing == self
			or not existing is CasterSkillVisualEffect
			or existing.skill_id != skill_id
			or existing.target_node != target_node
		):
			continue
		existing.visible = false
		existing.queue_free()


func _install_single() -> void:
	var sprite := AnimationPlayerScript.new()
	if not sprite.configure(
		skill_id,
		direction,
		_desired_sprite_extent_px,
		null,
		phase_id,
		_desired_sprite_footprint_px,
		_desired_sprite_axis_extent_px,
		_visual_axis_screen_px,
		_desired_sprite_cross_axis_extent_px
	):
		sprite.queue_free()
		return
	_apply_line_decoration_policy(sprite)
	add_child(sprite)
	_sprites.append(sprite)


func _install_hellfire_trail(render: Dictionary) -> void:
	_hellfire_frame_count = maxi(
		1,
		int(CasterSkillVisualRegistry.animation_profile(skill_id, phase_id).get("frame_count", 0))
	)
	_hellfire_step_seconds = maxf(
		0.001,
		float(render.get("trajectory_step_ms", 50)) / 1000.0
	)
	if not _geometry_screen_offsets_px.is_empty():
		_hellfire_step_distance = maxf(
			0.001,
			float(render.get(
				"trajectory_dominant_axis_pixels_per_second", 500.0 / 0.9
			)) * _hellfire_step_seconds
		)
		var endpoint: Vector2 = _geometry_screen_offsets_px.back()
		var dominant_distance := maxf(absf(endpoint.x), absf(endpoint.y))
		_hellfire_total_emissions = maxi(
			1,
			ceili(dominant_distance / _hellfire_step_distance)
		)
		for sample_index: int in range(_hellfire_total_emissions):
			_hellfire_emission_offsets.append(
				endpoint * (
					float(sample_index + 1) / float(_hellfire_total_emissions)
				)
			)
	else:
		_hellfire_step_distance = (
			float(render.get("trajectory_dominant_axis_pixels_per_second", 500.0 / 0.9))
			* _hellfire_step_seconds
		)
		_hellfire_total_emissions = maxi(1, ceili(radius / _hellfire_step_distance))
	for frame_index: int in range(_hellfire_frame_count):
		var sprite := AnimationPlayerScript.new()
		if not sprite.configure(
			skill_id,
			direction,
			_desired_sprite_extent_px,
			false,
			phase_id,
			_desired_sprite_footprint_px,
			_desired_sprite_axis_extent_px,
			_visual_axis_screen_px,
			_desired_sprite_cross_axis_extent_px
		):
			sprite.queue_free()
			continue
		_apply_line_decoration_policy(sprite)
		sprite.set_manual_frame(frame_index)
		sprite.visible = false
		add_child(sprite)
		_sprites.append(sprite)
	_advance_hellfire_trail()
	lifetime = maxf(
		lifetime,
		float(_hellfire_total_emissions + _hellfire_frame_count + 2)
		* _hellfire_step_seconds
	)


func _process_hellfire(delta: float) -> void:
	_hellfire_tick_elapsed += delta
	while _hellfire_tick_elapsed >= _hellfire_step_seconds and not _hellfire_finished:
		_hellfire_tick_elapsed -= _hellfire_step_seconds
		_advance_hellfire_trail()


func _advance_hellfire_trail() -> void:
	for record: Dictionary in _hellfire_records:
		record["age"] = int(record.get("age", 0)) + 1
	for index: int in range(_hellfire_records.size() - 1, -1, -1):
		if int(_hellfire_records[index].get("age", 0)) >= _hellfire_frame_count:
			_hellfire_records.remove_at(index)
	if _hellfire_emissions < _hellfire_total_emissions:
		var emission_position := (
			_hellfire_emission_offsets[_hellfire_emissions]
			if _hellfire_emissions < _hellfire_emission_offsets.size()
			else direction * minf(
				radius,
				float(_hellfire_emissions + 1) * _hellfire_step_distance
			)
		)
		_hellfire_records.push_front({"position": emission_position, "age": 0})
		_hellfire_emissions += 1
	_update_hellfire_sprites()
	_hellfire_finished = (
		_hellfire_emissions >= _hellfire_total_emissions
		and _hellfire_records.is_empty()
	)


func _update_hellfire_sprites() -> void:
	for index: int in range(_sprites.size()):
		var sprite: Sprite2D = _sprites[index]
		if index >= _hellfire_records.size():
			sprite.visible = false
			continue
		var record: Dictionary = _hellfire_records[index]
		sprite.visible = true
		sprite.position = (record.get("position", Vector2.ZERO) as Vector2).round()
		sprite.call("set_manual_frame", int(record.get("age", 0)))


func _all_playback_complete() -> bool:
	if _sprites.is_empty():
		return false
	for sprite: Sprite2D in _sprites:
		if not bool(sprite.get("playback_complete")):
			return false
	return true


func formal_core_polygon_screen_offset_px() -> PackedVector2Array:
	return _formal_core_polygon_screen_offset_px.duplicate()


func formal_core_polygons_screen_offset_px() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for polygon: PackedVector2Array in _formal_core_polygons_screen_offset_px:
		result.append(polygon.duplicate())
	return result


func formal_core_axis_screen_offset_px() -> Vector2:
	return _formal_core_axis_screen_offset_px


func snapshot_visual_projection_metadata() -> Dictionary:
	return {
		"contract_id": _snapshot_visual_projection_contract_id,
		"snapshot_id": str(_skill_footprint_snapshot.get("snapshot_id", "")),
		"snapshot_schema_version": int(
			_skill_footprint_snapshot.get("schema_version", 1)
		),
		"snapshot_coordinate_space": str(
			_skill_footprint_snapshot.get("coordinate_space", "")
		),
		"snapshot_runtime_map_id": str(
			_skill_footprint_snapshot.get("runtime_map_id", "")
		),
		"snapshot_projection_origin_ground_gu": (
			_skill_footprint_snapshot.get(
				"projection_origin_ground_gu", Vector2.ZERO
			) as Vector2
		),
		"shape_type": _snapshot_shape_type,
		"anchor_policy": _snapshot_anchor_policy,
		"anchor_screen_px": _snapshot_anchor_screen_px,
		"visual_core_policy": _snapshot_visual_core_policy,
		"projected_polygon_count": (
			_formal_core_polygons_screen_offset_px.size()
		),
		"decoration_sprite_transform_policy": (
			_decoration_sprite_transform_policy
		),
	}


func _snapshot_ok(snapshot: Dictionary) -> bool:
	return bool(SkillFootprintSnapshotScript.validate_for_consumer(
		snapshot,
		_snapshot_validation_context,
		_snapshot_validation_policy
	).get("valid", false))


func skill_visual_geometry_debug_metadata() -> Dictionary:
	return _debug_geometry_metadata.duplicate(true)


func _install_formal_snapshot_visual_core() -> void:
	if not _snapshot_ok(_skill_footprint_snapshot):
		return
	set_meta(
		"snapshot_visual_projection_contract",
		_snapshot_visual_projection_contract_id
	)
	set_meta("snapshot_shape_type", _snapshot_shape_type)
	set_meta("snapshot_anchor_policy", _snapshot_anchor_policy)
	set_meta("snapshot_visual_core_policy", _snapshot_visual_core_policy)
	set_meta(
		"decoration_sprite_transform_policy",
		_decoration_sprite_transform_policy
	)
	if _snapshot_shape_type == SkillFootprintSnapshotScript.SHAPE_SWEPT_CAPSULE_PATH:
		# Projectile children consume their capsule snapshots in collision and
		# diagnostics. A generic world effect must not force a visible capsule.
		return
	if skill_id in ["wizard.hellfire", "wizard.laser"]:
		_install_formal_line_visual_core()
		return
	if _snapshot_shape_type not in [
		SkillFootprintSnapshotScript.SHAPE_CELL_UNION,
		SkillFootprintSnapshotScript.SHAPE_CIRCLE,
		SkillFootprintSnapshotScript.SHAPE_SECTOR_ARC,
	]:
		# Target-footprint effects consume the exact anchor and selected instance;
		# they do not manufacture a visible area around that target.
		return
	var core_color := (
		Color(0.18, 0.72, 1.0, 0.10)
		if skill_id.begins_with("wizard.")
		else Color(0.32, 1.0, 0.52, 0.10)
	)
	for polygon_screen_offset_px: PackedVector2Array in (
		_formal_core_polygons_screen_offset_px
	):
		if polygon_screen_offset_px.size() < 3:
			continue
		var core_polygon := Polygon2D.new()
		core_polygon.polygon = polygon_screen_offset_px
		core_polygon.color = core_color
		core_polygon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(core_polygon)
		_formal_core_polygons.append(core_polygon)
	if not _formal_core_polygons.is_empty():
		_formal_core_polygon = _formal_core_polygons[0]
		set_meta(
			"formal_snapshot_visual_core_contract",
			FORMAL_SNAPSHOT_VISUAL_CORE_CONTRACT_ID
		)
		set_meta("formal_snapshot_polygon_count", _formal_core_polygons.size())


func _install_formal_line_visual_core() -> void:
	if (
		skill_id not in ["wizard.hellfire", "wizard.laser"]
		or not _snapshot_ok(_skill_footprint_snapshot)
		or _formal_core_polygon_screen_offset_px.size() != 4
		or _formal_core_axis_screen_offset_px.length_squared() <= 0.000001
	):
		return
	var palette := _formal_core_palette()
	_formal_core_polygon = Polygon2D.new()
	_formal_core_polygon.polygon = _formal_core_polygon_screen_offset_px
	_formal_core_polygon.color = palette.outer_fill
	_formal_core_polygon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_formal_core_polygon)
	_formal_core_polygons.append(_formal_core_polygon)
	# Presentation uses nested fills wholly contained by the authoritative quad.
	# No edge outline, cross or axis is drawn in the production effect; debug
	# overlays remain a separate integration concern.
	for layer_spec: Dictionary in [
		{"lateral_scale": 0.62, "color": palette.mid_fill},
		{"lateral_scale": 0.24, "color": palette.inner_fill},
	]:
		var glow_layer := Polygon2D.new()
		glow_layer.polygon = _inset_directed_quad(
			_formal_core_polygon_screen_offset_px,
			float(layer_spec.lateral_scale)
		)
		glow_layer.color = layer_spec.color
		glow_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(glow_layer)
		_formal_core_glow_layers.append(glow_layer)
	set_meta("formal_line_visual_core_contract", FORMAL_LINE_VISUAL_CORE_CONTRACT_ID)
	set_meta("formal_line_snapshot_id", str(
		_skill_footprint_snapshot.get("snapshot_id", "")
	))


func _formal_core_palette() -> Dictionary:
	if skill_id == "wizard.hellfire":
		return {
			"outer_fill": Color(1.0, 0.18, 0.02, 0.10),
			"mid_fill": Color(1.0, 0.38, 0.04, 0.16),
			"inner_fill": Color(1.0, 0.78, 0.24, 0.28),
		}
	return {
		"outer_fill": Color(0.08, 0.42, 1.0, 0.10),
		"mid_fill": Color(0.20, 0.68, 1.0, 0.18),
		"inner_fill": Color(0.72, 0.94, 1.0, 0.34),
	}


func _apply_line_decoration_policy(sprite: Sprite2D) -> void:
	if skill_id not in ["wizard.hellfire", "wizard.laser"]:
		return
	var decoration_modulate := sprite.modulate
	decoration_modulate.a = (
		HELLFIRE_DECORATION_ALPHA
		if skill_id == "wizard.hellfire"
		else LASER_DECORATION_ALPHA
	)
	sprite.modulate = decoration_modulate
	sprite.set_meta("formal_boundary_role", "decoration_only")


func _install_debug_skill_visual_geometry_overlay() -> void:
	if (
		not debug_skill_visual_geometry
		or not _snapshot_ok(_skill_footprint_snapshot)
		or _formal_core_polygon == null
	):
		return
	var expected_polygon_px := (
		SkillFootprintSnapshotScript.projected_polygon_screen_offset_px(
			_skill_footprint_snapshot
		)
	)
	var actual_polygon_px := _formal_core_polygon.polygon.duplicate()
	if expected_polygon_px.size() != 4 or actual_polygon_px.size() != 4:
		return
	var expected_axis_start_px: Vector2 = _skill_footprint_snapshot.get(
		"axis_start_screen_offset_px", Vector2.ZERO
	)
	var expected_axis_end_px: Vector2 = _skill_footprint_snapshot.get(
		"axis_screen_offset_px", Vector2.ZERO
	)
	var actual_axis_start_px := (
		actual_polygon_px[0] + actual_polygon_px[3]
	) * 0.5
	var actual_axis_end_px := (
		actual_polygon_px[1] + actual_polygon_px[2]
	) * 0.5

	_debug_geometry_overlay = Node2D.new()
	_debug_geometry_overlay.name = "SkillVisualGeometryDebugOverlay"
	add_child(_debug_geometry_overlay)
	# Wide expected lines stay visible below the thinner actual lines when both
	# geometries agree exactly. These colors never exist unless the plan opts in.
	_add_debug_geometry_line(
		_closed_polygon_points(expected_polygon_px),
		Color(0.20, 1.0, 0.25, 0.95),
		6.0,
		"expected_formal_range_ground_gu_projected_px"
	)
	_add_debug_geometry_line(
		_closed_polygon_points(actual_polygon_px),
		Color(0.18, 0.62, 1.0, 0.98),
		3.0,
		"actual_visual_core_px"
	)
	_add_debug_geometry_line(
		PackedVector2Array([expected_axis_start_px, expected_axis_end_px]),
		Color(0.78, 0.28, 1.0, 0.98),
		4.0,
		"expected_snapshot_axis_px"
	)
	_add_debug_geometry_line(
		PackedVector2Array([actual_axis_start_px, actual_axis_end_px]),
		Color(0.72, 0.72, 0.72, 0.98),
		2.0,
		"actual_visual_axis_px"
	)

	var corner_error_px := PackedFloat32Array()
	var maximum_corner_error_px := 0.0
	for corner_index: int in range(4):
		var error_px := expected_polygon_px[corner_index].distance_to(
			actual_polygon_px[corner_index]
		)
		corner_error_px.append(error_px)
		maximum_corner_error_px = maxf(maximum_corner_error_px, error_px)
	_debug_geometry_metadata = {
		"contract_id": DEBUG_SKILL_VISUAL_GEOMETRY_CONTRACT_ID,
		"snapshot_id": str(_skill_footprint_snapshot.get("snapshot_id", "")),
		"skill_id": str(_skill_footprint_snapshot.get("skill_id", skill_id)),
		"release_id": str(_skill_footprint_snapshot.get("release_id", "")),
		"expected_polygon_screen_offset_px": expected_polygon_px,
		"actual_polygon_screen_offset_px": actual_polygon_px,
		"expected_axis_start_screen_offset_px": expected_axis_start_px,
		"expected_axis_end_screen_offset_px": expected_axis_end_px,
		"actual_axis_start_screen_offset_px": actual_axis_start_px,
		"actual_axis_end_screen_offset_px": actual_axis_end_px,
		"expected_actual_corner_error_px": corner_error_px,
		"maximum_corner_error_px": maximum_corner_error_px,
	}
	for metadata_key: String in [
		"snapshot_id",
		"skill_id",
		"release_id",
		"expected_actual_corner_error_px",
		"maximum_corner_error_px",
	]:
		set_meta(metadata_key, _debug_geometry_metadata[metadata_key])
		_debug_geometry_overlay.set_meta(
			metadata_key, _debug_geometry_metadata[metadata_key]
		)
	set_meta(
		"debug_skill_visual_geometry_contract",
		DEBUG_SKILL_VISUAL_GEOMETRY_CONTRACT_ID
	)
	_debug_geometry_overlay.set_meta(
		"contract_id", DEBUG_SKILL_VISUAL_GEOMETRY_CONTRACT_ID
	)


func _add_debug_geometry_line(
	points_px: PackedVector2Array,
	color: Color,
	width_px: float,
	role: String
) -> void:
	var line := Line2D.new()
	line.points = points_px
	line.default_color = color
	line.width = width_px
	line.antialiased = true
	line.set_meta("debug_geometry_role", role)
	_debug_geometry_overlay.add_child(line)
	_debug_geometry_lines.append(line)


func _closed_polygon_points(
	polygon_px: PackedVector2Array
) -> PackedVector2Array:
	var result := polygon_px.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result


func _inset_directed_quad(
	quad_screen_offset_px: PackedVector2Array,
	lateral_scale: float
) -> PackedVector2Array:
	if quad_screen_offset_px.size() != 4:
		return PackedVector2Array()
	var safe_scale := clampf(lateral_scale, 0.0, 1.0)
	var start_center_px := (
		quad_screen_offset_px[0] + quad_screen_offset_px[3]
	) * 0.5
	var end_center_px := (
		quad_screen_offset_px[1] + quad_screen_offset_px[2]
	) * 0.5
	return PackedVector2Array([
		start_center_px.lerp(quad_screen_offset_px[0], safe_scale),
		end_center_px.lerp(quad_screen_offset_px[1], safe_scale),
		end_center_px.lerp(quad_screen_offset_px[2], safe_scale),
		start_center_px.lerp(quad_screen_offset_px[3], safe_scale),
	])
