extends Node

const CROP := Rect2i(535, 205, 210, 220)
const DIRECTION_NAMES := ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
const ACCEPTANCE_VERSION := "v108_death_anchor_20260717"
const DIRECTION_VECTORS := [
	Vector2.UP,
	Vector2(0.70710678, -0.70710678),
	Vector2.RIGHT,
	Vector2(0.70710678, 0.70710678),
	Vector2.DOWN,
	Vector2(-0.70710678, 0.70710678),
	Vector2.LEFT,
	Vector2(-0.70710678, -0.70710678),
]


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.ensure_zuma_test_character()
	assert(PlayerState.select_character("developer_zuma_warrior_40"))
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: PlayerCharacter = game.player
	var visual: Node2D = player.get_node("PlayerVisual")
	var output_dir := ProjectSettings.globalize_path("res://outputs/visual_acceptance/player_states")
	DirAccess.make_dir_recursive_absolute(output_dir)

	player.velocity = Vector2.ZERO
	for direction_index in range(DIRECTION_NAMES.size()):
		player.facing = DIRECTION_VECTORS[direction_index]
		visual._action_remaining = 0.0
		visual._elapsed = 0.0
		visual._process(0.01)
		await get_tree().process_frame
		_save_crop(output_dir.path_join("idle_%s.png" % DIRECTION_NAMES[direction_index]))
		_save_crop(output_dir.path_join("%s_idle_%s.png" % [ACCEPTANCE_VERSION, DIRECTION_NAMES[direction_index]]))
	# Stable compatibility filename used by the earlier acceptance record.
	player.facing = Vector2.DOWN
	visual._action_remaining = 0.0
	visual._process(0.01)
	await get_tree().process_frame
	_save_crop(output_dir.path_join("idle_south.png"))
	_save_crop(output_dir.path_join("%s_idle_south.png" % ACCEPTANCE_VERSION))

	player.velocity = Vector2.RIGHT * 80.0
	player.actual_motion_facing = Vector2.RIGHT
	player.movement_facing = Vector2.RIGHT
	player.movement_input_active = true
	visual._action_remaining = 0.0
	visual._elapsed = 0.0
	visual._process(0.24)
	await get_tree().process_frame
	_save_crop(output_dir.path_join("walk_east.png"))
	_save_crop(output_dir.path_join("%s_walk_east.png" % ACCEPTANCE_VERSION))
	player.velocity = Vector2.ZERO
	player.movement_input_active = false

	player.facing = Vector2.RIGHT
	visual.play_action("attack", 1.0)
	visual._process(0.45)
	await get_tree().process_frame
	_save_crop(output_dir.path_join("attack_east.png"))
	_save_crop(output_dir.path_join("%s_attack_east.png" % ACCEPTANCE_VERSION))

	player.facing = Vector2.DOWN
	visual.play_hit(0.6)
	visual._process(0.30)
	await get_tree().process_frame
	_save_crop(output_dir.path_join("hit_south.png"))
	_save_crop(output_dir.path_join("%s_hit_south.png" % ACCEPTANCE_VERSION))

	visual.play_death(0.8)
	visual._process(0.58)
	await get_tree().process_frame
	_save_crop(output_dir.path_join("death_south.png"))
	_save_crop(output_dir.path_join("%s_death_south.png" % ACCEPTANCE_VERSION))

	# Death is a 32-cell authored mapping. Capture every direction and every
	# frame so a correct south sample cannot hide a mismatched east/west row.
	for direction_index in range(DIRECTION_NAMES.size()):
		for death_frame in range(4):
			# The live player loop can refresh facing between awaited frames.
			# Pin it for every captured death cell so the test itself cannot
			# contaminate the direction-row assertion.
			player.facing = DIRECTION_VECTORS[direction_index]
			visual.play_death(0.8)
			visual._process((float(death_frame) + 0.1) * 0.2)
			await get_tree().process_frame
			assert(visual.current_direction == direction_index)
			assert(visual.current_frame == death_frame)
			_save_crop(output_dir.path_join("death_%s_f%d.png" % [DIRECTION_NAMES[direction_index], death_frame]))
			_save_crop(output_dir.path_join("%s_death_%s_f%d.png" % [ACCEPTANCE_VERSION, DIRECTION_NAMES[direction_index], death_frame]))

	assert(player.get_node("HealthBar").position == ArtSpec.PLAYER_HEALTH_BAR_OFFSET)
	print("PLAYER_HELMET_HEALTH_CAPTURE_PASS")
	get_tree().quit(0)


func _save_crop(path: String) -> void:
	var viewport_image := get_viewport().get_texture().get_image()
	var crop := viewport_image.get_region(CROP)
	crop.resize(CROP.size.x * 3, CROP.size.y * 3, Image.INTERPOLATE_NEAREST)
	assert(crop.save_png(path) == OK)
