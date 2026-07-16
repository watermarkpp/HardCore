extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for _frame in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var output := "res://outputs/test/bich_runtime_capture.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/test"))
	assert(image.save_png(output) == OK)
	print("BICH_RUNTIME_CAPTURE_PASS ", ProjectSettings.globalize_path(output))
	get_tree().quit()
