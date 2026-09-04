extends Control

const WORLD_TEXTURE := preload("res://assets/ui/gothic_preview/world_scene_reference.png")
const DeathRevivalPanelScript := preload("res://scripts/death_revival_panel.gd")
const OUTPUT_PATH := "res://outputs/visual_acceptance/death_revival/death_revival_gothic_v1.png"


func _ready() -> void:
	var world := TextureRect.new()
	world.name = "WorldBackdrop"
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.texture = WORLD_TEXTURE
	world.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	world.stretch_mode = TextureRect.STRETCH_SCALE
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)
	var panel: Control = DeathRevivalPanelScript.new()
	panel.name = "DeathRevivalPanel"
	add_child(panel)
	await get_tree().process_frame
	panel.open_death_screen({
		"death_id": "death:preview:001",
		"message": "你倒在了兽人古墓",
		"loss_text": "死亡损失：经验 10%",
		"revival_options": [
			{
				"option_slot": "town",
				"method_id": "revive.nearest_town",
				"label": "最近城镇复活",
				"enabled": true,
				"countdown_seconds": 3,
				"hint": "返回比奇省安全区",
			},
			{
				"option_slot": "special",
				"method_id": "revive.special.scroll",
				"label": "使用复活卷轴",
				"enabled": false,
				"reason": "背包中没有复活卷轴",
			},
		],
	})
	await get_tree().process_frame
	await get_tree().process_frame
	var output_dir := ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir())
	DirAccess.make_dir_recursive_absolute(output_dir)
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	assert(error == OK, "无法保存死亡复活样板")
	print("DEATH_REVIVAL_GOTHIC_PREVIEW_PASS：%s" % OUTPUT_PATH)
	get_tree().quit(0)
