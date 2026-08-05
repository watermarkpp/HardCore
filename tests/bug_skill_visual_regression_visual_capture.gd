extends Node2D


const OUTPUT_DIR := "res://outputs/bug_skill_visual_regression_visual"
const SKY_COLOR := Color("0f1e2b")
const GROUND_COLOR := Color("1a2d34")
const CAMERA_ZOOM := Vector2(1.25, 1.25)
const EFFECT_Z_INDEX := 64

var _capture_root: Node2D
var _capture_idx := 0
var _active_effect_nodes: Array[Node] = []


func _ready() -> void:
	_build_staged_scene()
	_run.call_deferred()


func _build_staged_scene() -> void:
	_capture_root = Node2D.new()
	_capture_root.position = Vector2.ZERO
	_capture_root.name = "CaptureRoot"
	add_child(_capture_root)

	var background := ColorRect.new()
	background.position = Vector2.ZERO
	background.size = Vector2(1280, 720)
	background.color = SKY_COLOR
	background.z_index = -100
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var terrain := ColorRect.new()
	terrain.position = Vector2(0, 300)
	terrain.size = Vector2(1280, 420)
	terrain.color = GROUND_COLOR
	terrain.z_index = -90
	terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(terrain)

	_add_terrain_tiles()

	var camera := Camera2D.new()
	camera.name = "BattleCamera"
	camera.enabled = true
	camera.zoom = CAMERA_ZOOM
	camera.position = Vector2(260, 320)
	camera.offset = Vector2(0, -32)
	add_child(camera)


func _add_terrain_tiles() -> void:
	for x in range(6):
		for y in range(4):
			var tone := 0.21 + 0.04 * float(x % 2) + 0.01 * float(y)
			var tile := ColorRect.new()
			tile.position = Vector2(70 + x * 190.0, 280 + y * 95.0)
			tile.size = Vector2(150.0, 70.0)
			tile.color = Color(tone, tone * 0.72, tone * 0.56)
			tile.z_index = -80
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(tile)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	var caster := _new_player()
	var base_position := Vector2(220.0, 320.0)
	caster.global_position = base_position
	_capture_root.add_child(caster)
	await _advance_frames(6)

	var lightning_target := _capture_lightning(caster, base_position + Vector2(96.0, 0.0))
	await _advance_frames(10)
	await _capture("wizard_lightning_visual.png", output_path)
	_release_active_effect_nodes()
	lightning_target.queue_free()

	await _advance_frames(4)
	var hellfire_target := _capture_hellfire(caster, base_position + Vector2(160.0, 0.0))
	await _advance_frames(14)
	await _capture("wizard_hellfire_visual.png", output_path)
	_release_active_effect_nodes()
	hellfire_target.queue_free()

	await _advance_frames(4)
	_capture_fire_wall(caster, base_position + Vector2(224.0, 0.0))
	await _advance_frames(14)
	await _capture("wizard_fire_wall_visual.png", output_path)
	_release_active_effect_nodes()

	print("BUG_SKILL_VISUAL_REGRESSION_CAPTURE_VISUAL_PASS: %s" % output_path)
	get_tree().quit(0)


func _capture_lightning(caster: PlayerCharacter, target_position: Vector2) -> EnemyActor:
	var target := _new_target(target_position, caster)
	_capture_root.add_child(target)
	var before_hp := target.current_hp
	var plan := CasterSkillRuntime.resolve("wizard.lightning", {
		"skill_level": 3,
		"magic_stat_roll": 30,
	})
	var result := CasterSkillRuntime.execute_cast(
		plan,
		{
			"parent": _capture_root,
			"caster": caster,
			"primary_target": target,
			"affected_targets": [target],
			"origin": caster.global_position,
			"target_position": target.global_position,
			"direction": Vector2.RIGHT,
			"anti_magic_roll": 1,
			"magic_defense_adapter": Callable(self, "_magic_defense"),
		}
	)
	assert(result.success and result.nodes.size() == 1 and result.applied_count == 1, "Lightning should create damage visual and apply damage")
	assert(target.current_hp < before_hp, "Lightning did not apply damage")
	_capture_result_nodes(result)
	return target


func _capture_hellfire(caster: PlayerCharacter, target_position: Vector2) -> EnemyActor:
	var target := _new_target(target_position, caster)
	_capture_root.add_child(target)
	var before_hp := target.current_hp
	var plan := CasterSkillRuntime.resolve("wizard.hellfire", {"skill_level": 3})
	var result := CasterSkillRuntime.execute_cast(
		plan,
		{
			"parent": _capture_root,
			"caster": caster,
			"primary_target": target,
			"affected_targets": [target],
			"origin": caster.global_position,
			"target_position": target.global_position,
			"direction": Vector2.RIGHT,
			"spatial_test_adapter_id": CasterSkillRuntime.NON_PRODUCTION_SPATIAL_ADAPTER_ID,
			"anti_magic_roll": 1,
			"magic_defense_adapter": Callable(self, "_magic_defense"),
		}
	)
	assert(result.success and result.nodes.size() >= 1, "Hellfire should create a runtime visual")
	if result.applied_count > 0:
		assert(target.current_hp < before_hp, "Hellfire did not apply damage")
	_capture_result_nodes(result)
	return target


func _capture_fire_wall(caster: PlayerCharacter, target_position: Vector2) -> void:
	var plan := CasterSkillRuntime.resolve("wizard.fire_wall", {
		"skill_level": 3,
		"magic_stat_roll": 50,
	})
	var result := CasterSkillRuntime.execute_cast(
		plan,
		{
			"parent": _capture_root,
			"caster": caster,
			"origin": caster.global_position,
			"target_position": target_position,
			"direction": Vector2.RIGHT,
		}
	)
	assert(result.success and result.nodes.size() == 4, "Fire wall should create four tiles")
	_capture_result_nodes(result)


func _capture(file_name: String, output_path: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("BUG_SKILL_VISUAL_REGRESSION_CAPTURE_VISUAL_SKIPPED_HEADLESS %s" % file_name)
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image != null and not image.is_empty(), "unable to read viewport image for visual regression capture")
	var output_file := output_path.path_join(file_name)
	assert(image.save_png(output_file) == OK, "failed to save screenshot %s" % file_name)
	_capture_idx += 1


func _capture_result_nodes(result: Dictionary) -> void:
	_active_effect_nodes = []
	for node: Node in result.get("nodes", []):
		_active_effect_nodes.append(node)
		_set_visual_on_top(node)


func _set_visual_on_top(node: Node) -> void:
	if node is Node2D:
		var visual_node := node as Node2D
		visual_node.z_as_relative = false
		visual_node.z_index = EFFECT_Z_INDEX
		visual_node.visible = true
		visual_node.modulate = Color(1, 1, 1, 1)
	for child: Node in node.get_children():
		_set_visual_on_top(child)


func _release_active_effect_nodes() -> void:
	for node: Node in _active_effect_nodes:
		if is_instance_valid(node):
			node.free()
	_active_effect_nodes = []


func _advance_frames(total: int) -> void:
	for _i in range(total):
		await get_tree().process_frame


func _new_player() -> PlayerCharacter:
	var caster := PlayerCharacter.new()
	caster.current_hp = 999
	caster.max_hp = 999
	caster.current_mp = 999
	caster.max_mp = 999
	caster.name = "BugSkillVisualCapturePlayer"
	return caster


func _new_target(position: Vector2, caster: PlayerCharacter) -> EnemyActor:
	var target := EnemyActor.new()
	var monster_data := GameData.get_monster("稻草人")
	assert(not monster_data.is_empty(), "Could not resolve monster data for 稻草人")
	target.setup(monster_data, caster, false)
	target.max_hp = 500
	target.current_hp = 500
	target.global_position = position
	target.set_meta("spawn_position", position)
	target.set_meta("safe_zones", [])
	target.set_physics_process(false)
	target.set_process_mode(Node.PROCESS_MODE_DISABLED)
	return target


func _magic_defense(skill_id: String, incoming_damage: int, _target_stats: Dictionary) -> int:
	return maxi(0, incoming_damage - 3)
