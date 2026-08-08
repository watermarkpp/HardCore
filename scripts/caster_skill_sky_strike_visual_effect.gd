class_name CasterSkillSkyStrikeVisualEffect
extends CasterSkillVisualEffect

const SKY_STRIKE_DEFAULT_WARNING_SECONDS := 0.0
const SKY_STRIKE_DEFAULT_IMPACT_SECONDS := 0.0
const SKY_STRIKE_DEFAULT_DURATION_SECONDS := 0.5

var _visual_profile: Dictionary = {}
var _anchor_type := ""
var _anchor_offset_px := Vector2.ZERO
var _release_anchor_screen_px := Vector2.ZERO
var _lifecycle_warning_seconds := SKY_STRIKE_DEFAULT_WARNING_SECONDS
var _lifecycle_impact_seconds := SKY_STRIKE_DEFAULT_IMPACT_SECONDS
var _lifecycle_duration_seconds := SKY_STRIKE_DEFAULT_DURATION_SECONDS
var _ground_projection_enabled := false
var _scale_policy := ""
var _impact_started := false
var _lifecycle_clock := 0.0
var _debug_metadata: Dictionary = {}


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
	var sanitized_visual_geometry_context := visual_geometry_context.duplicate(true)
	sanitized_visual_geometry_context["desired_sprite_extent_px"] = 0.0
	sanitized_visual_geometry_context["desired_sprite_footprint_px"] = Vector2.ZERO
	sanitized_visual_geometry_context["desired_sprite_axis_extent_px"] = 0.0
	sanitized_visual_geometry_context["desired_sprite_cross_axis_extent_px"] = 0.0
	sanitized_visual_geometry_context["visual_axis_screen_px"] = Vector2.ZERO
	super.setup(
		position_value,
		source_skill_id,
		radius_value,
		lifetime_value,
		direction_value,
		target,
		requested_phase_id,
		sanitized_visual_geometry_context
	)
	_apply_sky_strike_profile_context(sanitized_visual_geometry_context)
	# Sky-strike visuals can arrive with non-actor attachment policies that clear
	# `target_node` during base initialization. Capture a deterministic target
	# anchor early so `world_target_footpoint` remains stable through
	# _ready/_process even if attachment logic detaches the runtime target.
	_release_anchor_screen_px = (
		target_node.global_position + _anchor_offset_px
		if is_instance_valid(target_node)
		and _anchor_type in ["target_top", "world_target_footpoint"]
		else position_value
	)
	if _sprites.is_empty():
		_install_single()
	_lifecycle_clock = 0.0
	_impact_started = false
	if not _debug_metadata.is_empty():
		_debug_metadata = {}


func _ready() -> void:
	# Base class clears target_node for world_anchor attachment, but SkyStrike
	# needs it for profile-driven anchor tracking after target moves.
	var saved_target := target_node
	super._ready()
	target_node = saved_target
	# Calling set_process(false) before an AnimationPlayer enters the tree does
	# not survive Godot's automatic activation of its `_process` callback.  The
	# lightning sprite therefore completed all six frames while still hidden by
	# the impact gate and only exposed its effectively empty 4x1 terminal frame.
	# Re-apply the gate after every child is ready so frame zero remains intact
	# until the existing SkyStrike lifecycle starts playback.
	if skill_id == "wizard.lightning" and not _impact_started:
		for node in _sprites:
			if node is CasterSkillAnimationPlayer:
				(node as CasterSkillAnimationPlayer).set_process(false)
	_refresh_sky_strike_debug_metadata()
	if rejection_reason != "":
		return
	_apply_profile_anchor()


func _process(delta: float) -> void:
	if not _impact_started:
		_lifecycle_clock += delta
		if _lifecycle_clock < _lifecycle_warning_seconds:
			if is_instance_valid(target_node):
				_apply_profile_anchor()
			return
		if _lifecycle_clock < _lifecycle_warning_seconds + _lifecycle_impact_seconds:
			if is_instance_valid(target_node):
				_apply_profile_anchor()
			return
		_start_sky_strike_playback()
	if is_instance_valid(target_node):
		_apply_profile_anchor()
	_lifecycle_clock += delta
	if not _impact_started:
		return
	if _sprites.is_empty():
		if _lifecycle_clock >= _lifecycle_duration_seconds:
			queue_free()
		return
	if not _all_playback_complete():
		return
	if _lifecycle_clock >= _lifecycle_duration_seconds:
		queue_free()


func _install_single() -> void:
	if not _sprites.is_empty():
		return
	var sprite := AnimationPlayerScript.new()
	if not sprite.configure(
		skill_id,
		direction,
		0.0,
		null,
		phase_id,
		Vector2.ZERO,
		0.0,
		Vector2.ZERO,
		0.0
	):
		sprite.queue_free()
		return
	_apply_fixed_source_profile_scale(sprite)
	_apply_line_decoration_policy(sprite)
	sprite.visible = false
	sprite.set_process(false)
	add_child(sprite)
	_sprites.append(sprite)


func _apply_profile_anchor() -> void:
	var anchor_position_px := _release_anchor_screen_px
	if is_instance_valid(target_node):
		match _anchor_type:
			"target_top", "world_target_footpoint":
				anchor_position_px = target_node.global_position + _anchor_offset_px
			_:
				anchor_position_px = target_node.global_position
	else:
		anchor_position_px = _release_anchor_screen_px
	global_position = anchor_position_px.round()
	for node in _sprites:
		if not node is CasterSkillAnimationPlayer:
			continue
		var sprite: CasterSkillAnimationPlayer = node
		sprite.position = Vector2.ZERO


func _apply_sky_strike_profile_context(
	visual_geometry_context: Dictionary
) -> void:
	var raw_profile: Variant = visual_geometry_context.get("visual_profile", {})
	_visual_profile = _resolve_visual_profile(raw_profile)
	var animation_profile: Dictionary = _visual_profile.get("animation", {})
	var anchor_profile: Dictionary = _visual_profile.get("anchor", {})
	var lifecycle_profile: Dictionary = _visual_profile.get("lifecycle", {})
	var ground_projection_profile: Dictionary = _visual_profile.get("ground_projection", {})
	_scale_policy = str(animation_profile.get("scale_mode", "source_pixels"))
	_anchor_type = str(anchor_profile.get("type", "target_top"))
	_anchor_offset_px = _vector2_from_profile_offset(anchor_profile.get("offset", [0, 0]))
	_lifecycle_warning_seconds = maxf(
		0.0,
		float(lifecycle_profile.get("warning", SKY_STRIKE_DEFAULT_WARNING_SECONDS))
	)
	_lifecycle_impact_seconds = maxf(
		0.0,
		float(lifecycle_profile.get("impact", SKY_STRIKE_DEFAULT_IMPACT_SECONDS))
	)
	_lifecycle_duration_seconds = maxf(
		0.05,
		float(lifecycle_profile.get("duration", SKY_STRIKE_DEFAULT_DURATION_SECONDS))
	)
	_ground_projection_enabled = bool(ground_projection_profile.get("enabled", false))


func _resolve_visual_profile(raw_profile: Variant) -> Dictionary:
	if not raw_profile is Dictionary:
		return CasterSkillVisualRegistry.visual_profile(skill_id)
	var resolved_profile: Dictionary = raw_profile as Dictionary
	# Validated profiles from visual_profile() carry anchor/animation at the
	# top level. Legacy profiles wrap them inside a nested "visual_profile" key.
	if resolved_profile.has("anchor") or resolved_profile.has("animation"):
		return resolved_profile.duplicate(true)
	var nested_profile: Variant = resolved_profile.get("visual_profile", {})
	if nested_profile is Dictionary and not nested_profile.is_empty():
		return nested_profile.duplicate(true)
	return resolved_profile.duplicate(true)


func _vector2_from_profile_offset(raw_offset: Variant) -> Vector2:
	if raw_offset is Vector2:
		return raw_offset
	if raw_offset is Array and raw_offset.size() >= 2:
		return Vector2(float(raw_offset[0]), float(raw_offset[1]))
	return Vector2.ZERO


func _start_sky_strike_playback() -> void:
	_impact_started = true
	_lifecycle_clock = 0.0
	for node in _sprites:
		if not node is CasterSkillAnimationPlayer:
			continue
		var sprite: CasterSkillAnimationPlayer = node
		sprite.visible = true
		sprite.set_process(true)


func _refresh_sky_strike_debug_metadata() -> void:
	_debug_metadata = {
		"visual_type": "sky_strike",
		"scale_policy": _scale_policy,
		"anchor_policy": _anchor_type,
		"geometry_driven_scale": false,
		"lifecycle": sky_strike_lifecycle_profile(),
		"ground_projection_enabled": _ground_projection_enabled,
		"warning": _lifecycle_warning_seconds,
		"impact": _lifecycle_impact_seconds,
		"duration": _lifecycle_duration_seconds,
	}
	set_meta("sky_strike_visual_debug_metadata", _debug_metadata.duplicate(true))


func sky_strike_visual_debug_metadata() -> Dictionary:
	return _debug_metadata.duplicate(true)


func sky_strike_lifecycle_profile() -> Dictionary:
	return {
		"warning": _lifecycle_warning_seconds,
		"impact": _lifecycle_impact_seconds,
		"duration": _lifecycle_duration_seconds,
	}


func _apply_fixed_source_profile_scale(sprite: CasterSkillAnimationPlayer) -> void:
	if _scale_policy != "fixed_source":
		return
	var animation_profile: Dictionary = _visual_profile.get("animation", {})
	var width_scale := maxf(0.001, float(animation_profile.get("width_scale", 1.0)))
	var height_scale := maxf(0.001, float(animation_profile.get("height_scale", 1.0)))
	sprite.scale = Vector2(width_scale, height_scale)
