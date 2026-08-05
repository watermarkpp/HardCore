class_name CasterSkillBeamVisualEffect
extends CasterSkillVisualEffect

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

const DEFAULT_BEAM_WIDTH_SCALE := 1.0
const DEFAULT_BEAM_LENGTH_PX := 72.0
const DEFAULT_SINGLE_ACTIVE_SCOPE := "caster_skill"
const DEFAULT_SINGLE_ACTIVE_GROUP := "beam"
const SINGLE_ACTIVE_BEAM_GROUP_PREFIX := "caster_skill_beam_single_active"

var _visual_profile: Dictionary = {}
var _lifecycle_mode := "continuous"
var _geometry_binding_length_source := "actual_length"
var _geometry_binding_direction_source := "snapshot_axis"
var _geometry_binding_width_source := "profile"
var _animation_profile: Dictionary = {}
var _width_scale := DEFAULT_BEAM_WIDTH_SCALE
var _beam_axis_screen_px := Vector2.RIGHT
var _beam_length_px := DEFAULT_BEAM_LENGTH_PX
var _beam_debug_metadata: Dictionary = {}
var _single_active_enabled := false
var _single_active_scope := DEFAULT_SINGLE_ACTIVE_SCOPE
var _single_active_group := DEFAULT_SINGLE_ACTIVE_GROUP


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
    # Beam visual is intentionally geometry-binding driven. Ignore source-driven
    # desired extents that are used by legacy line effects.
    sanitized_visual_geometry_context["desired_sprite_extent_px"] = 0.0
    sanitized_visual_geometry_context["desired_sprite_footprint_px"] = Vector2.ZERO
    sanitized_visual_geometry_context["desired_sprite_axis_extent_px"] = 0.0
    sanitized_visual_geometry_context["desired_sprite_cross_axis_extent_px"] = 0.0
    sanitized_visual_geometry_context["visual_axis_screen_px"] = Vector2.ZERO
    _skip_legacy_laser_single_active = true
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
    _resolve_beam_profile_context(sanitized_visual_geometry_context)


func _ready() -> void:
    super._ready()
    _beam_debug_metadata = {
        "visual_type": "beam",
        "scale_policy": "axis_scaled",
        "anchor_policy": "caster_forward",
        "geometry_driven_scale": true,
        "lifecycle_mode": _lifecycle_mode,
        "width_scale": _width_scale,
        "length_source": _geometry_binding_length_source,
        "direction_source": _geometry_binding_direction_source,
        "width_source": _geometry_binding_width_source,
    }
    _apply_single_active_policy()
    _refresh_beam_debug_state()


func _install_single() -> void:
    if not _sprites.is_empty():
        return
    var sprite := AnimationPlayerScript.new()
    if not sprite.configure(
        skill_id,
        _beam_axis_screen_px,
        0.0,
        null,
        phase_id,
        Vector2.ZERO,
        maxf(0.001, _beam_length_px),
        _beam_axis_screen_px,
        0.0,
        {"anchor_policy": "align_sequence_visible_axis_start_to_geometry_origin"}
    ):
        sprite.queue_free()
        return
    _apply_beam_width_scale(sprite)
    sprite.self_modulate = Color(1.0, 1.0, 1.0, 1.0)  # Beam: full opacity; formal core polygon handles low-alpha overlay
    sprite.set_process(true)
    add_child(sprite)
    _sprites.append(sprite)


func beam_debug_metadata() -> Dictionary:
    return _beam_debug_metadata.duplicate(true)


func _apply_beam_width_scale(sprite: CasterSkillAnimationPlayer) -> void:
    if _width_scale == 1.0:
        return
    if not is_instance_valid(sprite):
        return
    var current_scale := sprite.scale
    sprite.scale = Vector2(current_scale.x, current_scale.y * _width_scale)


func _apply_single_active_policy() -> void:
    if not _single_active_enabled:
        return
    if _single_active_scope != DEFAULT_SINGLE_ACTIVE_SCOPE:
        return
    if not is_instance_valid(target_node):
        return
    if get_tree() == null:
        return
    var group_name := _single_active_group_name()
    if not is_in_group(group_name):
        add_to_group(group_name)
    for existing: Node in get_tree().get_nodes_in_group(group_name):
        if (
            existing == self
            or not existing is CasterSkillBeamVisualEffect
        ):
            continue
        var existing_beam := existing as CasterSkillBeamVisualEffect
        if (
            not is_instance_valid(existing_beam.target_node)
            or not is_instance_valid(target_node)
            or existing_beam.target_node != target_node
            or existing_beam._single_active_scope != _single_active_scope
            or existing_beam._single_active_group != _single_active_group
        ):
            continue
        existing_beam.visible = false
        existing_beam.queue_free()


func _single_active_group_name() -> String:
    var group_id := _single_active_group
    if group_id.is_empty():
        group_id = DEFAULT_SINGLE_ACTIVE_GROUP
    return "%s_%s" % [SINGLE_ACTIVE_BEAM_GROUP_PREFIX, group_id]


func _resolve_beam_profile_context(visual_geometry_context: Dictionary) -> void:
    var raw_profile: Variant = visual_geometry_context.get("visual_profile", {})
    _visual_profile = _resolve_visual_profile(raw_profile)
    _animation_profile = _visual_profile.get("animation", {})
    var geometry_binding: Dictionary = _visual_profile.get("geometry_binding", {})
    var lifecycle_profile: Dictionary = _visual_profile.get("lifecycle", {})
    var anchor_profile: Dictionary = _visual_profile.get("anchor", {})
    var single_active_profile: Dictionary = _visual_profile.get("single_active", {})
    _geometry_binding_length_source = str(
        geometry_binding.get("length", "actual_length")
    )
    _geometry_binding_direction_source = str(
        geometry_binding.get("direction", "snapshot_axis")
    )
    _geometry_binding_width_source = str(geometry_binding.get("width", "profile"))
    _lifecycle_mode = str(lifecycle_profile.get("mode", "continuous"))
    _width_scale = maxf(
        0.001,
        float(_animation_profile.get("width_scale", DEFAULT_BEAM_WIDTH_SCALE))
    )
    _single_active_enabled = bool(single_active_profile.get("enabled", false))
    _single_active_scope = str(
        single_active_profile.get("scope", DEFAULT_SINGLE_ACTIVE_SCOPE)
    )
    _single_active_group = str(single_active_profile.get("group", DEFAULT_SINGLE_ACTIVE_GROUP))
    if _single_active_scope.is_empty():
        _single_active_scope = DEFAULT_SINGLE_ACTIVE_SCOPE
    if _single_active_group.is_empty():
        _single_active_group = DEFAULT_SINGLE_ACTIVE_GROUP
    _beam_length_px = _resolve_beam_length(visual_geometry_context)
    _beam_axis_screen_px = _resolve_beam_axis_direction(visual_geometry_context)
    _beam_debug_metadata["animation_scale_mode"] = str(
        _animation_profile.get("scale_mode", "axis_scaled")
    )
    _beam_debug_metadata["animation_width_scale"] = _width_scale
    _beam_debug_metadata["anchor_policy"] = str(anchor_profile.get("type", "caster_forward"))
    _beam_debug_metadata["requested_beam_length_px"] = _beam_length_px
    _beam_debug_metadata["resolved_beam_axis_screen_px"] = _beam_axis_screen_px
    _beam_debug_metadata["single_active"] = {
        "enabled": _single_active_enabled,
        "scope": _single_active_scope,
        "group": _single_active_group,
        "group_name": _single_active_group_name()
    }


func _resolve_beam_length(visual_geometry_context: Dictionary) -> float:
    var raw_snapshot: Variant = visual_geometry_context.get("skill_footprint_snapshot", {})
    var raw_length_source: String = _geometry_binding_length_source
    if (
        raw_snapshot is Dictionary
        and SkillFootprintSnapshotScript.is_valid(raw_snapshot as Dictionary)
        and raw_length_source == "actual_length"
    ):
        var snapshot_length_px := float(
            (raw_snapshot as Dictionary).get("axis_screen_length_px", 0.0)
        )
        if snapshot_length_px > 0.0:
            return snapshot_length_px
    if _beam_length_px > 0.0:
        return _beam_length_px
    return DEFAULT_BEAM_LENGTH_PX


func _resolve_beam_axis_direction(
    visual_geometry_context: Dictionary
) -> Vector2:
    var raw_snapshot: Variant = visual_geometry_context.get("skill_footprint_snapshot", {})
    var direction_source: String = _geometry_binding_direction_source
    if raw_snapshot is Dictionary and SkillFootprintSnapshotScript.is_valid(
        raw_snapshot as Dictionary
    ):
        var snapshot := raw_snapshot as Dictionary
        if direction_source == "snapshot_axis":
            var axis_screen: Vector2 = (
                snapshot.get("axis_screen_direction_px", Vector2.ZERO)
            )
            if axis_screen is Vector2 and axis_screen.length_squared() > 0.000001:
                return axis_screen.normalized()
            var direction_ground: Vector2 = (
                snapshot.get("direction_ground_gu", Vector2.ZERO)
            )
            if direction_ground is Vector2 and direction_ground.length_squared() > 0.000001:
                var axis_px := GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
                    direction_ground.normalized()
                )
                if axis_px.length_squared() > 0.000001:
                    return axis_px.normalized()
    if (
        direction is Vector2
        and direction.length_squared() > 0.000001
    ):
        return direction.normalized()
    return Vector2.RIGHT


func _resolve_visual_profile(raw_profile: Variant) -> Dictionary:
    if not raw_profile is Dictionary:
        return CasterSkillVisualRegistry.visual_profile(skill_id)
    var resolved_profile: Dictionary = raw_profile as Dictionary
    var nested_profile: Variant = resolved_profile.get("visual_profile", {})
    if nested_profile is Dictionary:
        return nested_profile.duplicate(true)
    return resolved_profile.duplicate(true)


func _refresh_beam_debug_state() -> void:
    set_meta("beam_visual_debug_metadata", _beam_debug_metadata.duplicate(true))
    set_meta("single_active_group_name", _single_active_group_name())



