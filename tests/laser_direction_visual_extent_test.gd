extends Node

const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")
const CasterSkillVisualFactory := preload("res://scripts/caster_skill_visual_factory.gd")
const CasterSkillAnimationPlayer := preload("res://scripts/caster_skill_animation_player.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const PlayerCharacter := preload("res://scripts/player.gd")

const DIR_NAMES: Array[String] = ["E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW","N","NNE","NE","ENE"]
const DIR_VECS: Array[Vector2] = [
	Vector2.RIGHT, Vector2(0.924,0.383), Vector2(0.707,0.707), Vector2(0.383,0.924),
	Vector2.DOWN, Vector2(-0.383,0.924), Vector2(-0.707,0.707), Vector2(-0.924,0.383),
	Vector2.LEFT, Vector2(-0.924,-0.383), Vector2(-0.707,-0.707), Vector2(-0.383,-0.924),
	Vector2.UP, Vector2(0.383,-0.924), Vector2(0.707,-0.707), Vector2(0.924,-0.383),
]
const GAME8_NAMES: Array[String] = ["S","SW","W","NW","N","NE","E","SE"]


func _context() -> Dictionary:
	return {"skill_level":3,"caster_level":40,"owner_level":40,"target_level":20,"target_max_hp":500,"magic_stat_roll":30,"spiritual_stat_roll":30,"random_0_to_10":0}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var owner := PlayerCharacter.new()
	owner.global_position = Vector2(320.0, 240.0)
	add_child(owner)

	var plan := CasterSkillRuntime.resolve("wizard.laser", _context())
	var profile: Dictionary = plan.get("visual", {}).duplicate(true)
	profile["enable_beam_visual"] = true
	profile["visual_type"] = "beam"

	var results: Array[Dictionary] = []

	for seq_idx: int in range(16):
		var dir_name: String = DIR_NAMES[seq_idx]
		var dir_vec: Vector2 = DIR_VECS[seq_idx]

		var dg: Vector2 = GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(dir_vec).normalized()
		var snapshot: Dictionary = SkillFootprintSnapshotScript.create_directed_rectangle(
			"wizard.laser", "laser_%s" % dir_name, Vector2.ZERO, dg, 8.0, 1.0, 0.0, 8.0, 8.0, "actual"
		).duplicate(true)
		snapshot["direction_ground_gu"] = dg

		var axis_start: Vector2 = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(snapshot.get("origin_ground_gu", Vector2.ZERO))
		var axis_end: Vector2 = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(snapshot.get("end_ground_gu", Vector2.ZERO))
		var snap_len: float = axis_start.distance_to(axis_end)
		var axis_unit: Vector2 = (axis_end - axis_start).normalized() if snap_len > 0.001 else dir_vec

		var beam := CasterSkillVisualFactory.create(profile)
		assert(beam != null, "beam seq %d" % seq_idx)
		beam.setup(owner.global_position, "wizard.laser", 72.0, 0.8, dir_vec, owner, "", {
			"visual_type": "beam", "skill_footprint_snapshot": snapshot, "visual_profile": profile,
		})
		add_child(beam)

		var sprites: Array = beam.get("_sprites")
		var sprite := sprites[0] as CasterSkillAnimationPlayer

		var vis_fwd: float = sprite.fitted_visual_forward_extent(axis_unit)
		var vis_cross: float = sprite.fitted_visual_cross_extent(axis_unit)
		var bounds: Rect2 = sprite.fitted_visual_bounds()

		var vis_min: float = INF
		var vis_max: float = -INF
		for ci: int in range(4):
			var lx: float = bounds.position.x + (bounds.size.x if ci & 1 else 0.0)
			var ly: float = bounds.position.y + (bounds.size.y if ci & 2 else 0.0)
			var proj: float = (Vector2(lx, ly) - axis_start).dot(axis_unit)
			vis_min = minf(vis_min, proj)
			vis_max = maxf(vis_max, proj)

		# Defined error metrics
		var start_err: float = vis_min - 0.0
		var end_err: float = vis_max - snap_len
		var extent_err: float = (vis_max - vis_min) - snap_len
		assert(absf(extent_err - (end_err - start_err)) <= 0.01,
			"%s: extent_err %.2f != end_err-start_err %.2f" % [dir_name, extent_err, end_err - start_err])

		results.append({
			"seq": seq_idx, "dir": dir_name,
			"snap_len": snap_len, "vis_start": vis_min, "vis_end": vis_max,
			"vis_fwd": vis_fwd, "vis_cross": vis_cross,
			"start_err": start_err, "end_err": end_err, "extent_err": extent_err,
			"mod_a": sprite.modulate.a, "self_a": sprite.self_modulate.a,
		})

	print("")
	print("=== LASER 16-SEQUENCE SEPARATE START/END/EXTENT ERRORS ===")
	print("seq dir | snap_len | vis_start | vis_end | start_err | end_err | extent_err | mod.a")
	for e: Dictionary in results:
		print("%3d %4s | %8.1f | %9.1f | %7.1f | %+8.1f | %+7.1f | %+9.1f | %.4f" % [
			e.seq, e.dir, e.snap_len, e.vis_start, e.vis_end,
			e.start_err, e.end_err, e.extent_err, e.mod_a,
		])
	print("=== END ===")
	print("")

	# Assertions: all three errors independently verified
	for e: Dictionary in results:
		var lbl: String = "seq %d %s" % [e.seq, e.dir]
		assert(e.mod_a >= 0.99, "%s: mod.a=%.4f" % [lbl, e.mod_a])
		assert(e.self_a >= 0.99, "%s: self.a=%.4f" % [lbl, e.self_a])
		assert(absf(e.extent_err) <= 1.0, "%s: extent_err %.1f > 1px" % [lbl, e.extent_err])
		assert(absf(e.start_err) <= 1.0, "%s: start_err %.1f > 1px (anchor behind caster)" % [lbl, e.start_err])
		assert(absf(e.end_err) <= 1.0, "%s: end_err %.1f > 1px (endpoint misaligned)" % [lbl, e.end_err])

	# Mirror pairs
	var g8: Dictionary = {}
	for e: Dictionary in results:
		if e.dir in GAME8_NAMES:
			g8[e.dir] = e
	for pair in [["E","W"],["N","S"],["NE","SW"],["NW","SE"]]:
		var a: Dictionary = g8.get(pair[0], {})
		var b: Dictionary = g8.get(pair[1], {})
		if a.is_empty() or b.is_empty():
			continue
		assert(absf(a.snap_len - b.snap_len) <= 0.5, "%s/%s snap_len diff" % [pair[0],pair[1]])
		assert(absf(a.start_err - b.start_err) <= 1.0, "%s/%s start_err diff" % [pair[0],pair[1]])
		assert(absf(a.end_err - b.end_err) <= 1.0, "%s/%s end_err diff" % [pair[0],pair[1]])

	print("LASER_DIRECTION_VISUAL_EXTENT_PASS")
	get_tree().quit(0)
