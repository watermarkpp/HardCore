class_name CasterSkillVisualEffect
extends Node2D

const AnimationPlayerScript := preload("res://scripts/caster_skill_animation_player.gd")

const COMPLETION_GRACE_SECONDS := 0.05

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
var _hellfire_records: Array[Dictionary] = []
var _hellfire_tick_elapsed := 0.0
var _hellfire_emissions := 0
var _hellfire_total_emissions := 0
var _hellfire_frame_count := 0
var _hellfire_finished := false
var _hellfire_step_seconds := 0.05
var _hellfire_step_distance := 25.0
var _geometry_world_offsets: Array[Vector2] = []
var _hellfire_emission_offsets: Array[Vector2] = []
var _desired_sprite_extent := 0.0
var _desired_sprite_footprint := Vector2.ZERO


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
	_desired_sprite_extent = maxf(
		0.0,
		float(visual_geometry_context.get("desired_sprite_extent", 0.0))
	)
	_desired_sprite_footprint = visual_geometry_context.get(
		"desired_sprite_footprint", Vector2.ZERO
	)
	for raw_offset: Variant in visual_geometry_context.get("geometry_world_offsets", []):
		if raw_offset is Vector2:
			_geometry_world_offsets.append(raw_offset)


func _ready() -> void:
	add_to_group("zone_content")
	var entry := CasterSkillVisualRegistry.profile(skill_id)
	visual_role = str(entry.get("role", ""))
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
	if _attachment_policy not in ["target_actor", "caster_actor"]:
		target_node = null
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
		global_position = target_node.global_position.round()
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


func _install_single() -> void:
	var sprite := AnimationPlayerScript.new()
	if not sprite.configure(
		skill_id,
		direction,
		_desired_sprite_extent,
		null,
		phase_id,
		_desired_sprite_footprint
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
	if not _geometry_world_offsets.is_empty():
		_hellfire_step_distance = maxf(
			0.001,
			float(render.get(
				"trajectory_dominant_axis_pixels_per_second", 500.0 / 0.9
			)) * _hellfire_step_seconds
		)
		var endpoint: Vector2 = _geometry_world_offsets.back()
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
			_desired_sprite_extent,
			false,
			phase_id,
			_desired_sprite_footprint
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
