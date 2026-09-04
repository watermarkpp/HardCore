extends Control

const WORLD_TEXTURE := preload("res://assets/ui/gothic_preview/world_scene_clean.png")
const GothicConfirmationPanelScript := preload("res://scripts/gothic_confirmation_panel.gd")
const OUTPUT_NORMAL := "res://outputs/visual_acceptance/confirmation/confirmation_normal_v1.png"
const OUTPUT_DANGER := "res://outputs/visual_acceptance/confirmation/confirmation_danger_v1.png"

var dialog: Control


func _ready() -> void:
	var world := TextureRect.new()
	world.name = "WorldBackdrop"
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.texture = WORLD_TEXTURE
	world.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	world.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)
	dialog = GothicConfirmationPanelScript.new()
	add_child(dialog)
	await get_tree().process_frame
	dialog.open_confirmation({
		"action_id": "ui.preview.normal",
		"title": "确认操作",
		"message": "是否继续当前操作？",
		"confirm_label": "确认",
		"cancel_label": "取消",
		"tone": "normal",
	})
	await get_tree().process_frame
	await get_tree().process_frame
	_save_viewport(OUTPUT_NORMAL)
	dialog.open_confirmation({
		"action_id": "quest.abandon",
		"title": "确认放弃任务",
		"message": "放弃后，当前任务进度将按游戏规则处理。",
		"confirm_label": "确认放弃",
		"cancel_label": "取消",
		"tone": "danger",
	})
	await get_tree().process_frame
	await get_tree().process_frame
	_save_viewport(OUTPUT_DANGER)
	print("GOTHIC_CONFIRMATION_PREVIEW_PASS：%s，%s" % [OUTPUT_NORMAL, OUTPUT_DANGER])
	get_tree().quit(0)


func _save_viewport(path: String) -> void:
	var output_dir := ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(output_dir)
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	assert(error == OK, "无法保存确认弹窗样板：%s" % path)
