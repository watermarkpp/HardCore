extends Node2D

const OUTPUT_PATH := "res://outputs/test_visuals/orc_tomb_monsters_fixed.png"
const MONSTER_IDS := [47, 50, 52, 54, 43, 46, 56]
const POSITIONS := [
	Vector2(150, 270), Vector2(445, 270), Vector2(750, 270), Vector2(1080, 270),
	Vector2(210, 610), Vector2(590, 610), Vector2(1010, 610),
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	RenderingServer.set_default_clear_color(Color("15191f"))
	var player := PlayerCharacter.new()
	player.global_position = Vector2(640, 360)
	add_child(player)
	player.set_physics_process(false)

	for index in range(MONSTER_IDS.size()):
		var monster_id: int = MONSTER_IDS[index]
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(monster_id), player, monster_id == 56)
		add_child(enemy)
		enemy.set_physics_process(false)
		await get_tree().process_frame
		enemy.facing = Vector2.DOWN
		enemy.movement_facing = Vector2.DOWN
		enemy.visual._process(0.0)
		enemy.set_targeted(true)
		enemy.current_hp = maxi(1, int(enemy.max_hp * 0.68))
		enemy.global_position = POSITIONS[index] - enemy.ground_indicator_center()
		enemy.name_label.text = "%s  #%d" % [enemy.display_name, monster_id]
		enemy.queue_redraw()

	for frame in range(3):
		await get_tree().process_frame
	var output := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		print("ORC_TOMB_MONSTER_VISUAL_CAPTURE_SKIP: renderer has no viewport image")
		get_tree().quit(0)
		return
	assert(image.save_png(output) == OK, "兽人古墓怪物截图保存失败")
	print("ORC_TOMB_MONSTER_VISUAL_CAPTURE_PASS")
	get_tree().quit(0)
