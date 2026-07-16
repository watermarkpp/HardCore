extends Node2D

const OUTPUT := "res://outputs/visual_acceptance/npc_facing_runtime_20260715.png"
const DIRECTIONS := [
	Vector2.DOWN, Vector2(-0.70710678, 0.70710678), Vector2.LEFT, Vector2(-0.70710678, -0.70710678),
	Vector2.UP, Vector2(0.70710678, -0.70710678), Vector2.RIGHT, Vector2(0.70710678, 0.70710678),
]
const NAMES := ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]


func _ready() -> void:
	var background := ColorRect.new()
	background.position = Vector2.ZERO
	background.size = Vector2(1280, 720)
	background.color = Color("161310")
	background.z_index = -20
	add_child(background)
	var title := Label.new()
	title.text = "NPC-FACING-1  主客户端 Npc.wil · Godot 实际加载八方向验收"
	title.position = Vector2(260, 24)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("f1cf83"))
	add_child(title)
	for index in range(8):
		var npc := NPCActor.new()
		npc.setup("方向 %s" % NAMES[index], "shop", [], "", [0, 8, 10, 11, 14, 15, 22, 1][index], Vector2(640, 360))
		npc.position = Vector2(145 + (index % 4) * 315, 250 + (index / 4) * 300)
		add_child(npc)
		npc.face_toward(npc.global_position + DIRECTIONS[index] * 100.0)
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	assert(get_viewport().get_texture().get_image().save_png(output) == OK)
	print("NPC_FACING_CAPTURE_PASS: %s" % output)
	get_tree().quit(0)
