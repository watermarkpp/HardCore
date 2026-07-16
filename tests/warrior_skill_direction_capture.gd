extends Node2D

const OUTPUT_DIR := "res://outputs/visual_acceptance/warrior_skill_direction_audit"
const DIRECTIONS := [Vector2.UP, Vector2(0.70710678, -0.70710678), Vector2.RIGHT, Vector2(0.70710678, 0.70710678), Vector2.DOWN, Vector2(-0.70710678, 0.70710678), Vector2.LEFT, Vector2(-0.70710678, -0.70710678)]
const DIRECTION_NAMES := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const SKILLS := [
	["basic_sword", "基本剑术（普通攻击动作）", "attack"],
	["power_hit", "攻杀剑术", "攻杀剑术"],
	["long_hit", "刺杀剑术", "刺杀剑术"],
	["wide_hit", "半月弯刀", "半月弯刀"],
	["wild_rush", "野蛮冲撞", "野蛮冲撞"],
	["fire_hit", "烈火剑法", "烈火剑法"],
]

var players: Array[PlayerCharacter] = []
var direction_labels: Array[Label] = []
var title: Label


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("战士")
	PlayerState.equipment["武器"] = {"name": "裁决之杖", "durability": 30}
	PlayerState.equipment["衣服"] = {"name": "重盔甲(男)", "durability": 30}
	PlayerState.equipment["头盔"] = {"name": "黑铁头盔", "durability": 30}
	var background := ColorRect.new()
	background.size = Vector2(1280, 720)
	background.color = Color("15120f")
	background.z_index = -100
	add_child(background)
	title = Label.new()
	title.position = Vector2(360, 32)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("f0ca78"))
	add_child(title)
	for index in range(8):
		var player := PlayerCharacter.new()
		player.position = Vector2(80 + index * 160, 380)
		player.facing = DIRECTIONS[index]
		player.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(player)
		players.append(player)
		player.get_node("HealthBar").visible = false
		var direction_label := Label.new()
		direction_label.text = DIRECTION_NAMES[index]
		direction_label.position = player.position + Vector2(-12, 72)
		direction_label.add_theme_font_size_override("font_size", 20)
		direction_label.add_theme_color_override("font_color", Color("f0ca78"))
		add_child(direction_label)
		direction_labels.append(direction_label)
	PlayerState.equipment_changed.emit()
	await get_tree().process_frame
	var output_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_dir)
	for skill: Array in SKILLS:
		title.text = "WARRIOR-SKILL-AUDIT · %s · 动作第5帧" % skill[1]
		for index in range(8):
			var visual: Node2D = players[index].visual
			visual.process_mode = Node.PROCESS_MODE_DISABLED
			visual._action_remaining = 0.0
			visual._action_duration = 0.0
			visual._last_state = ""
			visual.play_action(str(skill[2]), 0.51)
			visual._process(0.40)
		await RenderingServer.frame_post_draw
		var path := output_dir.path_join("%s.png" % skill[0])
		assert(get_viewport().get_texture().get_image().save_png(path) == OK)
	await _capture_isolated_fire(output_dir)
	print("WARRIOR_SKILL_DIRECTION_CAPTURE_PASS: %s" % output_dir)
	get_tree().quit(0)


func _capture_isolated_fire(output_dir: String) -> void:
	# Full-size Magic.wil fire is wider than the 160px audit spacing. Capture
	# one direction at a time so neighboring effects cannot overlap and hide
	# the weapon-head attachment point.
	for index in range(players.size()):
		players[index].visible = index == 0
		direction_labels[index].visible = false
	var montage := Image.create(1536, 640, false, Image.FORMAT_RGBA8)
	montage.fill(Color("15120f"))
	players[0].position = Vector2(640, 360)
	for direction in range(8):
		players[0].facing = DIRECTIONS[direction]
		title.position = Vector2(510, 48)
		title.text = "烈火剑法 · %s · 武器头逐帧吸附" % DIRECTION_NAMES[direction]
		var visual: Node2D = players[0].visual
		visual._action_remaining = 0.0
		visual._action_duration = 0.0
		visual._last_state = ""
		visual.play_action("烈火剑法", 0.51)
		visual._process(0.40)
		await RenderingServer.frame_post_draw
		var isolated := get_viewport().get_texture().get_image().get_region(Rect2i(256, 40, 768, 640))
		isolated.resize(384, 320, Image.INTERPOLATE_LANCZOS)
		montage.blit_rect(isolated, Rect2i(Vector2i.ZERO, isolated.get_size()), Vector2i((direction % 4) * 384, (direction / 4) * 320))
	assert(montage.save_png(output_dir.path_join("fire_hit_weapon_head_isolated.png")) == OK)
