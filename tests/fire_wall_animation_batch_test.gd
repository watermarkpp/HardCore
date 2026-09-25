extends Node2D

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const Geometry := preload("res://scripts/skills/caster_spell_geometry.gd")
var _failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	CasterSkillVisualRegistry.clear_frame_texture_cache()
	CasterSkillVisualRegistry.set_loading_window_active(false)
	var field := _make_field()
	add_child(field)
	field.set_physics_process(false)
	field.set_process(false)
	_check(field.visual_cells.size() == 9, "3x3 cells must remain intact")
	for cell: GroundSkillVisualCell in field.visual_cells:
		_check(not cell.is_physics_processing(), "controller-owned cell must not run a second lifetime clock")
		_check(not cell._sprite.is_processing(), "batched cell must not schedule an independent animation process")
		_check(not cell._sprite.visual_loaded, "cold fixture must start pending")
		_check(cell._sprite._trial_screen_copy == null, "fire wall must not copy the full viewport per cell")
		_check(is_instance_valid(cell._sprite._fire_wall_additive_sprite), "fire wall cell must have its additive pass")
	# Real resource residency is advanced deliberately; no fake animation frames.
	for path: String in CasterSkillVisualRegistry.animation_sequence_paths("wizard.fire_wall", 0, ""):
		CasterSkillVisualRegistry.retain_loaded_texture(path, load(path))
	if field.has_method("_process"):
		field.call("_process", 0.0)
	var first: CasterSkillAnimationPlayer = field.visual_cells[0]._sprite
	_check(is_equal_approx(first.animation_duration(), 0.36), "six fire wall frames must total 360 ms")
	var original_scale := first.scale
	var snapshots: Array[String] = []
	for cell: GroundSkillVisualCell in field.visual_cells:
		snapshots.append(str(cell.skill_footprint_snapshot.snapshot_id))
	# Small steps, a long frame and wraparound all select the same final frame.
	for clock_ms: float in [0.0, 59.0, 60.0, 119.0, 120.0, 359.0, 360.0, 1000.0]:
		field._anim_clock_ms = clock_ms
		if field.has_method("_process"):
			field.call("_process", 0.0)
		var expected := int(floor(fmod(clock_ms, first.animation_duration() * 1000.0) / 60.0))
		for index in range(field.visual_cells.size()):
			var cell: GroundSkillVisualCell = field.visual_cells[index]
			var sprite: CasterSkillAnimationPlayer = cell._sprite
			_check(sprite.visual_loaded and sprite.current_frame_index == expected, "all nine cells must commit the shared final frame")
			_check(sprite.scale.is_equal_approx(original_scale), "frame changes must preserve the approved compressed height")
			_check(sprite._fire_wall_additive_sprite.texture == sprite.texture, "both blend passes must use the same frame")
			_check(sprite._fire_wall_additive_sprite.offset.is_equal_approx(sprite.offset), "both blend passes must keep the same anchor")
			_check(str(cell.skill_footprint_snapshot.snapshot_id) == snapshots[index], "animation must not rebuild damage geometry")
			_check(not sprite.is_processing(), "warm recovery must not re-enable independent scheduling")
	_check(is_equal_approx(original_scale.y, GroundSkillEffect.FIRE_WALL_HEIGHT_SCALE), "height remains 0.6")
	field.cancel()
	await get_tree().process_frame
	_check(CasterSkillVisualRegistry.frame_texture_cache_diagnostics().get("leased_sequence_refcount_total", -1) == 0,
		"cancel must release every cell lease")
	if _failures.is_empty():
		print("FIRE_WALL_ANIMATION_BATCH_PASS")
		get_tree().quit(0)
	else:
		for failure: String in _failures: push_error(failure)
		get_tree().quit(1)

func _make_field() -> FireWallFieldController:
	var cells: Array[Vector2i] = []
	var positions: Array[Vector2] = []
	for y in range(-1, 2):
		for x in range(-1, 2):
			cells.append(Vector2i(10 + x, 10 + y))
			positions.append(_project(Vector2(cells.back())))
	var context := Snapshot.make_absolute_runtime_context(42, Vector2(10, 10), Vector2(10, 10), _project)
	context.expected_runtime_map_id = 42
	var snapshot := Geometry.create_exact_cell_union_release_snapshot("wizard.fire_wall", "batch-lifecycle", Vector2(10, 10), cells, context)
	var field := FireWallFieldController.new()
	var filters: Array[Callable] = []
	field.setup_fire_wall_field(self, "wizard.fire_wall", {"duration_seconds": 60.0},
		positions, cells, filters, Callable(), _unproject, "batch-lifecycle", snapshot, context, null, 42)
	return field

func _project(point: Vector2) -> Vector2:
	return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(point)

func _unproject(point: Vector2) -> Vector2:
	return GroundUnitSpace.screen_delta_px_to_ground_delta_gu(point)

func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message): _failures.append(message)
