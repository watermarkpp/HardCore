class_name CasterSkillVisualEffect
extends Node2D

const AnimationPlayerScript := preload("res://scripts/caster_skill_animation_player.gd")

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

var skill_id := ""
var phase_id := ""
var visual_role := ""
var radius := 72.0
var lifetime := 0.8
var direction := Vector2.DOWN
var target_node: Node2D
var visual_loaded := false
var rejection_reason := ""
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
	for raw_offset: Variant in visual_geometry_context.get("geometry_screen_offsets_px", []):
		if raw_offset is Vector2:
			_geometry_screen_offsets_px.append(raw_offset)


func _ready() -> void:
	add_to_group("zone_content")
	if skill_id == "wizard.laser" and is_instance_valid(target_node):
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
