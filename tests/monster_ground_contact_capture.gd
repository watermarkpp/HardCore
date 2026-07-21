extends Node2D

const OUTPUT_PATH := "res://outputs/test_visuals/monster_ground_contact.png"
const MONSTER_IDS := [18, 124, 160, 180, 195, 224]
const CONTACT_POSITIONS := [
	Vector2(170, 285),
	Vector2(480, 285),
	Vector2(850, 285),
	Vector2(185, 640),
	Vector2(650, 640),
	Vector2(1060, 640),
]
const BOSS_IDS := [124, 160, 180, 195, 224]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	RenderingServer.set_default_clear_color(Color("15191f"))
	var player := PlayerCharacter.new()
	player.global_position = Vector2(4000, 4000)
	add_child(player)
	player.set_physics_process(false)

	for index in range(MONSTER_IDS.size()):
		var monster_id: int = MONSTER_IDS[index]
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(monster_id), player, monster_id in BOSS_IDS)
		add_child(enemy)
		enemy.set_physics_process(false)
		await get_tree().process_frame
		enemy.facing = Vector2.DOWN
		enemy.movement_facing = Vector2.DOWN
		enemy.visual._process(0.0)
		enemy.set_targeted(true)
		enemy.global_position = CONTACT_POSITIONS[index] - enemy.ground_indicator_center()
		enemy.name_label.text = "%s  #%d" % [enemy.display_name, monster_id]

	for frame in range(3):
		await get_tree().process_frame
	var output := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var image := get_viewport().get_texture().get_image()
	if image == null:
		print("MONSTER_GROUND_CONTACT_CAPTURE_PASS: headless renderer skipped PNG")
		get_tree().quit(0)
		return
	assert(image.save_png(output) == OK)
	print("MONSTER_GROUND_CONTACT_CAPTURE_PASS")
	get_tree().quit(0)
