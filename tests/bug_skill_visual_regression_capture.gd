extends Node


const OUTPUT_DIR := "res://outputs/bug_skill_visual_regression"
var _capture_idx := 0
var _capture_root: Node2D


func _ready() -> void:
	_capture_root = Node2D.new()
	add_child(_capture_root)
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	var caster := _new_player()
	var base_position := Vector2(160.0, 180.0)
	caster.global_position = base_position
	_capture_root.add_child(caster)
	await _advance_frames(4)

	_capture_lightning(caster, base_position + Vector2(96.0, 0.0))
	await _advance_frames(4)
	await _capture("wizard_lightning.png", output_path)

	await _advance_frames(2)
	_capture_hellfire(caster, base_position + Vector2(160.0, 0.0))
	await _advance_frames(4)
	await _capture("wizard_hellfire.png", output_path)

	await _advance_frames(2)
	_capture_fire_wall(caster, base_position + Vector2(224.0, 0.0))
	await _advance_frames(4)
	await _capture("wizard_fire_wall.png", output_path)

	print("BUG_SKILL_VISUAL_REGRESSION_CAPTURE_PASS: %s" % output_path)
	print("BUG_SKILL_VISUAL_REGRESSION_CAPTURE_SKILLS: wizard.lightning wizard.hellfire wizard.fire_wall")
	get_tree().quit(0)


func _capture_lightning(caster: PlayerCharacter, target_position: Vector2) -> void:
	var target := _new_target(target_position)
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
	_drain_result_nodes(result)
	target.queue_free()


func _capture_hellfire(caster: PlayerCharacter, target_position: Vector2) -> void:
	var target := _new_target(target_position)
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
	_drain_result_nodes(result)
	target.queue_free()


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
	_drain_result_nodes(result)


func _capture(file_name: String, output_path: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("BUG_SKILL_VISUAL_REGRESSION_CAPTURE_SKIPPED_HEADLESS %s" % file_name)
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image != null and not image.is_empty(), "unable to read viewport image for visual regression capture")
	assert(image.save_png(output_path.path_join(file_name)) == OK)
	_capture_idx += 1


func _drain_result_nodes(result: Dictionary) -> void:
	for node: Node2D in result.get("nodes", []):
		node.free()


func _advance_frames(total: int) -> void:
	for _i in range(total):
		await get_tree().process_frame


func _new_player() -> PlayerCharacter:
	var caster := PlayerCharacter.new()
	caster.current_hp = 999
	caster.max_hp = 999
	caster.current_mp = 999
	caster.max_mp = 999
	caster.name = "SkillCastCapturePlayer"
	return caster


func _new_target(pos: Vector2) -> EnemyActor:
	var target := EnemyActor.new()
	target.max_hp = 500
	target.current_hp = 500
	target.monster_data = {"antiMagic": 0}
	target.global_position = pos
	return target


func _magic_defense(skill_id: String, incoming_damage: int, _target_stats: Dictionary) -> int:
	return maxi(0, incoming_damage - 3)
