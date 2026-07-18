extends Control

const WORLD_TEXTURE := preload("res://assets/ui/gothic_preview/world_scene_reference.png")
const LoadingTransitionOverlayScript := preload("res://scripts/loading_transition_overlay.gd")
const OUTPUT_PATH := "res://outputs/visual_acceptance/loading_transition/loading_transition_v1.png"


func _ready() -> void:
	var world := TextureRect.new()
	world.name = "WorldBackdrop"
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.texture = WORLD_TEXTURE
	world.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	world.stretch_mode = TextureRect.STRETCH_SCALE
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)
	var overlay: Control = LoadingTransitionOverlayScript.new()
	overlay.name = "LoadingTransitionOverlay"
	add_child(overlay)
	await get_tree().process_frame
	overlay.show_loading_immediately("preview")
	await get_tree().process_frame
	await get_tree().process_frame
	var output_dir := ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir())
	DirAccess.make_dir_recursive_absolute(output_dir)
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	assert(error == OK, "无法保存Loading过渡样板")
	print("LOADING_TRANSITION_PREVIEW_PASS：%s" % OUTPUT_PATH)
	get_tree().quit(0)
