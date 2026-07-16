extends Node


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var intro: Control = load("res://scenes/brand_intro.tscn").instantiate()
	intro.auto_advance = false
	add_child(intro)
	await get_tree().create_timer(2.45).timeout
	await RenderingServer.frame_post_draw
	var output_dir := ProjectSettings.globalize_path("res://outputs/visual_acceptance")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var output := output_dir.path_join("brand_intro_20260715.png")
	assert(get_viewport().get_texture().get_image().save_png(output) == OK)
	print("BRAND_INTRO_CAPTURE_PASS: %s" % output)
	get_tree().quit(0)
