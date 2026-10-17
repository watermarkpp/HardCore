extends RefCounted

## One copy of the original numeric timing formulas. Profiles are either a
## main-only live source or an independently published numeric source on S.
const DERIVED_READY := "ready"
const PRIMARY_COMPLETION_GRACE_SECONDS := 0.05
var _profiles: RefCounted

func _init(profiles: RefCounted) -> void:
	assert(profiles != null)
	_profiles = profiles

func render_policy(skill_name_or_id: String, phase_id := "") -> Dictionary:
	var entry: Dictionary = _profiles.profile(skill_name_or_id)
	if not phase_id.is_empty():
		var phase: Dictionary = entry.get("animation_phases", {}).get(phase_id, {})
		if phase.get("render") is Dictionary:
			var phase_render: Dictionary = entry.get("render", {}).duplicate(true)
			phase_render.merge(phase.render, true)
			return phase_render
	return entry.get("render", {}).duplicate(true)


func animation_profile(skill_name_or_id: String, phase_id := "") -> Dictionary:
	var entry: Dictionary = _profiles.profile(skill_name_or_id)
	if phase_id.is_empty():
		return entry.get("animation", {})
	var phases: Dictionary = entry.get("animation_phases", {})
	return phases.get(phase_id, {})


func is_runtime_ready(skill_name_or_id: String) -> bool:
	var entry: Dictionary = _profiles.profile(skill_name_or_id)
	return (
		entry.get("status", "") == "formal_primary_client_animation"
		and entry.get("animation", {}).get("contract", "") == "caster_skill_animation.v1"
		and str(entry.get("derived_status", DERIVED_READY)) == DERIVED_READY
	)


func animation_duration(skill_name_or_id: String, phase_id := "") -> float:
	if not is_runtime_ready(skill_name_or_id):
		return 0.0
	var animation := animation_profile(skill_name_or_id, phase_id)
	return (
		float(animation.get("frame_count", 0))
		* float(animation.get("frame_time_ms", 0))
		/ 1000.0
	)


func primary_action_completion_seconds(
	skill_name_or_id: String,
	phase_id := ""
) -> float:
	var render := render_policy(skill_name_or_id, phase_id)
	if not bool(render.get("movement_lock_to_primary_visual", false)):
		return 0.0
	var skill_id: String = _profiles.skill_id(skill_name_or_id)
	var animation := animation_profile(skill_id, phase_id)
	if str(render.get("playback_strategy", "frame_sequence")) == "firegun_trail":
		var frame_count := maxi(1, int(animation.get("frame_count", 1)))
		var step_seconds := maxf(
			0.001,
			float(render.get("trajectory_step_ms", 50)) / 1000.0
		)
		var step_distance := maxf(
			0.001,
			float(render.get(
				"trajectory_dominant_axis_pixels_per_second", 500.0 / 0.9
			)) * step_seconds
		)
		var maximum_dominant_distance := maxf(
			step_distance,
			float(render.get("trajectory_max_dominant_axis_pixels", 0.0))
		)
		var emission_count := maxi(
			1,
			ceili(maximum_dominant_distance / step_distance)
		)
		# The first trail sample is emitted immediately. The final sample disappears after
		# advancing through all source frames, so neither cooldown nor recovery
		# time is included in this presentation boundary.
		return float(emission_count + frame_count - 1) * step_seconds
	return animation_duration(skill_id, phase_id) + PRIMARY_COMPLETION_GRACE_SECONDS


