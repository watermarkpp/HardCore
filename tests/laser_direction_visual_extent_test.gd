extends Node

const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")
const CasterSkillVisualFactory := preload("res://scripts/caster_skill_visual_factory.gd")
const CasterSkillBeamVisualEffect := preload("res://scripts/caster_skill_beam_visual_effect.gd")
const CasterSkillAnimationPlayer := preload("res://scripts/caster_skill_animation_player.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const PlayerCharacter := preload("res://scripts/player.gd")

const DIR_NAMES := ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]
const DIR_VECS: Array[Vector2] = [
	Vector2.DOWN, Vector2(-0.707, 0.707), Vector2.LEFT, Vector2(-0.707, -0.707),
	Vector2.UP, Vector2(0.707, -0.707), Vector2.RIGHT, Vector2(0.707, 0.707),
]


func _context() -> Dictionary:
	return {"skill_level":3,"caster_level":40,"owner_level":40,"target_level":20,"target_max_hp":500,"magic_stat_roll":30,"spiritual_stat_roll":30,"random_0_to_10":0}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var owner := PlayerCharacter.new()
	owner.global_position = Vector2(320.0, 240.0)
	add_child(owner)

	var plan := CasterSkillRuntime.resolve("wizard.laser", _context())
	assert(plan != {})

	var results: Array[Dictionary] = []

	for dir_idx: int in range(8):
		var dir_name: String = DIR_NAMES[dir_idx]
		var dir_vec: Vector2 = DIR_VECS[dir_idx]

		# Build beam snapshot for this direction
		var dg := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(dir_vec).normalized()
		var snapshot := SkillFootprintSnapshotScript.create_directed_rectangle(
			"wizard.laser", "laser_audit_%s" % dir_name, Vector2.ZERO, dg, 8.0, 1.0, 0.0, 8.0, 8.0, "actual"
		).duplicate(true)
		snapshot["direction_ground_gu"] = dg
		snapshot["axis_screen_direction_px"] = dir_vec.normalized()

		# Project axis start/end to screen
		var axis_start_ground: Vector2 = snapshot.get("origin_ground_gu", Vector2.ZERO)
		var axis_end_ground: Vector2 = snapshot.get("end_ground_gu", dg * 8.0)
		var axis_start_screen: Vector2 = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(axis_start_ground)
		var axis_end_screen: Vector2 = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(axis_end_ground)
		var axis_screen_length: float = axis_start_screen.distance_to(axis_end_screen)
		var axis_screen_dir := (axis_end_screen - axis_start_screen).normalized() if axis_screen_length > 0.001 else dir_vec

		# Build beam profile
		var profile: Dictionary = plan.get("visual", {}).duplicate(true)
		profile["enable_beam_visual"] = true
		profile["visual_type"] = "beam"

		var beam_plan: Dictionary = plan.duplicate(true)
		beam_plan["skill_footprint_snapshot"] = snapshot

		# Create beam
		var beam := CasterSkillVisualFactory.create(profile) as CasterSkillBeamVisualEffect
		assert(beam != null, "beam created for %s" % dir_name)
		beam.setup(
			owner.global_position, "wizard.laser", 72.0, 0.8, dir_vec, owner, "",
			{"visual_type": "beam", "skill_footprint_snapshot": snapshot, "visual_profile": profile}
		)
		add_child(beam)

		var sprites: Array = beam.get("_sprites")
		assert(sprites.size() > 0, "sprites for %s" % dir_name)
		var sprite: Sprite2D = sprites[0]

		var scale: Vector2 = sprite.scale
		var tex: Texture2D = sprite.texture
		var tex_w: float = float(tex.get_width()) if tex != null else 0.0
		var tex_h: float = float(tex.get_height()) if tex != null else 0.0

		# Visible extent from sprite: the texture bounds scaled by sprite.scale
		var visible_axis_extent: float = tex_w * scale.x  # approximation - directional axis may differ
		var visible_cross_extent: float = tex_h * scale.y

		# Compute final visible axis endpoints
		var final_axis_start: Vector2 = sprite.global_position
		var final_axis_end: Vector2 = sprite.global_position + axis_screen_dir * visible_axis_extent

		var entry := {
			"direction": dir_name,
			"dir_index": dir_idx,
			"dir_vec": dir_vec,
			"snapshot_axis_start_screen": axis_start_screen,
			"snapshot_axis_end_screen": axis_end_screen,
			"snapshot_axis_screen_length_px": axis_screen_length,
			"resolved_effect_length_gu": snapshot.get("effect_length_gu", 8.0),
			"sprite_scale": scale,
			"sprite_global_position": sprite.global_position,
			"final_visible_axis_start_px": final_axis_start,
			"final_visible_axis_end_px": final_axis_end,
			"final_visible_forward_extent_px": visible_axis_extent,
			"final_visible_cross_extent_px": visible_cross_extent,
			"modulate_a": sprite.modulate.a,
			"self_modulate_a": sprite.self_modulate.a,
			"forward_error_px": visible_axis_extent - axis_screen_length,
		}
		results.append(entry)

	# Print data table
	print("")
	print("=== LASER 8-DIRECTION VISUAL EXTENT AUDIT ===")
	print("dir | snap_len | vis_len | forward_err | cross | mod.a | self.a | scale")
	for entry: Dictionary in results:
		print("%3s | %8.1f | %7.1f | %+7.1f | %5.1f | %.4f | %.4f | %s" % [
			entry.direction,
			entry.snapshot_axis_screen_length_px,
			entry.final_visible_forward_extent_px,
			entry.forward_error_px,
			entry.final_visible_cross_extent_px,
			entry.modulate_a,
			entry.self_modulate_a,
			str(entry.sprite_scale),
		])
	print("=== END ===")
	print("")

	# Assertions
	for entry: Dictionary in results:
		var dir_label: String = entry.direction
		var forward_err: float = entry.forward_error_px

		# Each direction's visible length should match snapshot length within 1px
		# (not all directions have same px length — isometric projection varies)
		assert(absf(forward_err) <= 1.0,
			"%s: forward extent error %.1f px exceeds 1.0 px tolerance" % [dir_label, forward_err])

		# Alpha must be >= 0.99 (no 0.46 decoration alpha on beam)
		assert(entry.modulate_a >= 0.99,
			"%s: modulate.a=%.4f < 0.99 — LASER_DECORATION_ALPHA still applied!" % [dir_label, entry.modulate_a])
		assert(entry.self_modulate_a >= 0.99,
			"%s: self_modulate.a=%.4f < 0.99" % [dir_label, entry.self_modulate_a])

	# Mirror pairs
	var mirror_pairs := [["E", "W"], ["N", "S"], ["NE", "SW"], ["NW", "SE"]]
	for pair in mirror_pairs:
		var a := _find_result(results, pair[0])
		var b := _find_result(results, pair[1])
		assert(a.snapshot_axis_screen_length_px >= b.snapshot_axis_screen_length_px - 0.5 and
			a.snapshot_axis_screen_length_px <= b.snapshot_axis_screen_length_px + 0.5,
			"%s/%s: snapshot lengths differ" % [pair[0], pair[1]])
		assert(a.final_visible_forward_extent_px >= b.final_visible_forward_extent_px - 0.5 and
			a.final_visible_forward_extent_px <= b.final_visible_forward_extent_px + 0.5,
			"%s/%s: visible lengths differ" % [pair[0], pair[1]])

	print("LASER_DIRECTION_VISUAL_EXTENT_PASS: all 8 directions within tolerance")
	get_tree().quit(0)


func _find_result(results: Array, dir: String) -> Dictionary:
	for r: Dictionary in results:
		if r.direction == dir:
			return r
	return {}
