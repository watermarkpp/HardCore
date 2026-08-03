class_name CasterSkillVisualRegistry
extends RefCounted

const MANIFEST_PATH := "res://assets/data/caster_skill_visuals.json"

const ROLE_PROJECTILE := "projectile"
const ROLE_TARGET_EFFECT := "target_effect"
const ROLE_SELF_EFFECT := "self_effect"
const ROLE_SELF_AREA := "self_area"
const ROLE_AREA_EFFECT := "area_effect"
const ROLE_LINE_EFFECT := "line_effect"
const ROLE_GROUND_EFFECT := "ground_effect"
const ROLE_SUMMON_ACTOR := "summon_actor_visual"

const SCALE_SOURCE_PIXELS := "source_pixels"
const SCALE_FIT_EXTENT := "fit_extent"
const DERIVED_READY := "ready"
const PRIMARY_COMPLETION_GRACE_SECONDS := 0.05

static var _manifest_cache: Dictionary = {}


static func profile(skill_name_or_id: String) -> Dictionary:
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
	if skill_id.is_empty():
		return {}
	var coverage: Dictionary = _manifest().get("skillCoverage", {}).get(skill_id, {})
	if coverage.is_empty():
		return {}
	var result := coverage.duplicate(true)
	result["skill_id"] = skill_id
	var asset_id := str(result.get("asset_id", ""))
	if not asset_id.is_empty():
		result.merge(_manifest().get("assets", {}).get(asset_id, {}), true)
		result["asset_id"] = asset_id
		result["resource_path"] = "res://%s" % str(result.get("path", ""))
	var render := _default_render_policy(result)
	var declared_render: Variant = result.get("render", {})
	if declared_render is Dictionary:
		render.merge(declared_render, true)
	result["render"] = render
	return result


static func visual_role(skill_name_or_id: String) -> String:
	return str(profile(skill_name_or_id).get("role", ""))


static func render_policy(skill_name_or_id: String, phase_id := "") -> Dictionary:
	var entry := profile(skill_name_or_id)
	if not phase_id.is_empty():
		var phase: Dictionary = entry.get("animation_phases", {}).get(phase_id, {})
		if phase.get("render") is Dictionary:
			var phase_render: Dictionary = entry.get("render", {}).duplicate(true)
			phase_render.merge(phase.render, true)
			return phase_render
	return entry.get("render", {}).duplicate(true)


static func animation_profile(skill_name_or_id: String, phase_id := "") -> Dictionary:
	var entry := profile(skill_name_or_id)
	if phase_id.is_empty():
		return entry.get("animation", {})
	var phases: Dictionary = entry.get("animation_phases", {})
	return phases.get(phase_id, {})


static func is_runtime_ready(skill_name_or_id: String) -> bool:
	var entry := profile(skill_name_or_id)
	return (
		entry.get("status", "") == "formal_primary_client_animation"
		and entry.get("animation", {}).get("contract", "") == "caster_skill_animation.v1"
		and str(entry.get("derived_status", DERIVED_READY)) == DERIVED_READY
	)


static func runtime_readiness_reason(skill_name_or_id: String) -> String:
	var entry := profile(skill_name_or_id)
	if entry.is_empty():
		return "missing_visual_profile"
	if entry.get("status", "") != "formal_primary_client_animation":
		return str(entry.get("reason", "not_formal_primary_client_animation"))
	if entry.get("animation", {}).get("contract", "") != "caster_skill_animation.v1":
		return "missing_animation_contract"
	var status := str(entry.get("derived_status", DERIVED_READY))
	return "" if status == DERIVED_READY else status


static func texture(skill_name_or_id: String) -> Texture2D:
	if not is_runtime_ready(skill_name_or_id):
		return null
	var entry := profile(skill_name_or_id)
	var path := str(entry.get("resource_path", ""))
	return load_texture_path(path)


static func icon_texture(skill_name_or_id: String) -> Texture2D:
	var entry := profile(skill_name_or_id)
	if entry.get("status", "") != "formal_primary_client_animation":
		return null
	var icon: Dictionary = entry.get("icon", {})
	var path := "res://%s" % str(icon.get("path", entry.get("icon_path", "")))
	return load_texture_path(path)


static func load_texture_path(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		var imported := load(path) as Texture2D
		if imported != null:
			return imported
	# Clean worktrees can run the safe headless test runner before Godot has
	# imported newly generated PNGs. Decode the exact source PNG directly so
	# tests and runtime use the same pixels; exports still use normal imports.
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


static func animation_duration(skill_name_or_id: String, phase_id := "") -> float:
	if not is_runtime_ready(skill_name_or_id):
		return 0.0
	var animation := animation_profile(skill_name_or_id, phase_id)
	return (
		float(animation.get("frame_count", 0))
		* float(animation.get("frame_time_ms", 0))
		/ 1000.0
	)


static func primary_action_completion_seconds(
	skill_name_or_id: String,
	phase_id := ""
) -> float:
	var render := render_policy(skill_name_or_id, phase_id)
	if not bool(render.get("movement_lock_to_primary_visual", false)):
		return 0.0
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
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


static func direction_index(direction: Vector2) -> int:
	if direction.length_squared() <= 0.0:
		return 8
	# Exact port of MirClient/ClFunc.pas GetFlyDirection16. Its four strict
	# slope thresholds are intentionally asymmetric with angle rounding.
	var fx := direction.x
	var fy := direction.y
	if fx == 0.0:
		return 0 if fy < 0.0 else 8
	if fy == 0.0:
		return 12 if fx < 0.0 else 4
	var result := 4 if fx > 0.0 else 12
	var absolute_y := absf(fy)
	var absolute_x := absf(fx)
	if absolute_y > absolute_x / 4.0:
		result = 3 if fy < 0.0 and fx > 0.0 else (
			5 if fy > 0.0 and fx > 0.0 else (
				11 if fy > 0.0 else 13
			)
		)
	if absolute_y > absolute_x / 1.9:
		result = 2 if fy < 0.0 and fx > 0.0 else (
			6 if fy > 0.0 and fx > 0.0 else (
				10 if fy > 0.0 else 14
			)
		)
	if absolute_y > absolute_x * 1.4:
		result = 1 if fy < 0.0 and fx > 0.0 else (
			7 if fy > 0.0 and fx > 0.0 else (
				9 if fy > 0.0 else 15
			)
		)
	if absolute_y > absolute_x * 4.0:
		result = 0 if fy < 0.0 else 8
	return result


static func sequence_index(direction_16: int, sequences_or_count: Variant) -> int:
	var normalized := posmod(direction_16, 16)
	if sequences_or_count is int:
		var count := int(sequences_or_count)
		if count <= 1:
			return 0
		var scaled := float(normalized) * float(count) / 16.0
		return posmod(int(floor(scaled + 0.5)), count)
	if not sequences_or_count is Array or sequences_or_count.is_empty():
		return 0
	var sequences: Array = sequences_or_count
	var best_index := 0
	var best_distance := 17
	var best_clockwise_delta := 17
	for index: int in range(sequences.size()):
		var candidate := posmod(int(sequences[index].get("direction_index", 0)), 16)
		var clockwise_delta := posmod(candidate - normalized, 16)
		var counterclockwise_delta := posmod(normalized - candidate, 16)
		var distance := mini(clockwise_delta, counterclockwise_delta)
		if distance < best_distance or (
			distance == best_distance and clockwise_delta < best_clockwise_delta
		):
			best_index = index
			best_distance = distance
			best_clockwise_delta = clockwise_delta
	return best_index


static func has_formal_visual(skill_name_or_id: String) -> bool:
	return (
		is_runtime_ready(skill_name_or_id)
		and texture(skill_name_or_id) != null
		and icon_texture(skill_name_or_id) != null
	)


static func active_skill_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for skill_id: String in _manifest().get("skillCoverage", {}):
		if _manifest().skillCoverage[skill_id].get("status", "") == "formal_primary_client_animation":
			result.append(skill_id)
	return result


static func runtime_ready_skill_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for skill_id: String in active_skill_ids():
		if is_runtime_ready(skill_id):
			result.append(skill_id)
	return result


static func _default_render_policy(entry: Dictionary) -> Dictionary:
	var role := str(entry.get("role", ""))
	var attachment := "world_anchor"
	match role:
		ROLE_PROJECTILE:
			attachment = "world_projectile"
		ROLE_TARGET_EFFECT:
			attachment = "target_actor"
		ROLE_SELF_EFFECT, ROLE_SELF_AREA, ROLE_LINE_EFFECT:
			attachment = "caster_actor"
		ROLE_SUMMON_ACTOR:
			attachment = "summon_actor"
	var skill_id := str(entry.get("skill_id", ""))
	if skill_id in ["wizard.lightning", "wizard.hellfire", "wizard.teleport"]:
		attachment = "world_anchor"
	return {
		"contract": "caster_skill_render.v2",
		"scale_mode": SCALE_FIT_EXTENT if role == ROLE_PROJECTILE else SCALE_SOURCE_PIXELS,
		"source_scale": 1.0,
		"fit_extent": 34.0 if role == ROLE_PROJECTILE else 0.0,
		"anchor_policy": "top_left_from_world_anchor",
		"attachment_policy": attachment,
		"playback_strategy": "firegun_trail" if skill_id == "wizard.hellfire" else "frame_sequence",
		"pixel_snap": true,
	}


static func _manifest() -> Dictionary:
	if not _manifest_cache.is_empty():
		return _manifest_cache
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_manifest_cache = parsed if parsed is Dictionary else {}
	return _manifest_cache
