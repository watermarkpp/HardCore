extends Control

const OUTPUT_PATH := "res://outputs/visual_acceptance/skill/skill_gothic_sample_v1.png"
const WORLD_TEXTURE := preload("res://assets/ui/gothic_preview/world_scene_clean.png")


func _ready() -> void:
	_build_background()
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "战士"
	PlayerState.level = 40
	PlayerState.learned_skills = {
		"攻杀剑术": 3,
		"刺杀剑术": 3,
		"半月弯刀": 3,
		"野蛮冲撞": 3,
		"烈火剑法": 3,
	}
	PlayerState.quick_slots = ["刺杀剑术", "半月弯刀", "烈火剑法", "野蛮冲撞"]
	var panel := SkillPanel.new()
	panel.name = "SkillPanel"
	add_child(panel)
	await get_tree().process_frame
	panel.open_for("技能导师")
	for index in range(panel.skill_entries.size()):
		if str(panel.skill_entries[index].get("skillName", "")) == "刺杀剑术":
			panel._on_skill_selected(index)
			break
	await get_tree().process_frame
	await get_tree().process_frame
	var output_dir := ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir())
	DirAccess.make_dir_recursive_absolute(output_dir)
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	assert(error == OK, "无法保存技能哥特样板")
	print("SKILL_GOTHIC_PREVIEW_CAPTURE_PASS output=%s" % OUTPUT_PATH)
	get_tree().quit(0)


func _build_background() -> void:
	var world := TextureRect.new()
	world.name = "WorldBackdrop"
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.texture = WORLD_TEXTURE
	world.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	world.stretch_mode = TextureRect.STRETCH_SCALE
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)
	var dim := ColorRect.new()
	dim.name = "ModalDim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.008, 0.006, 0.005, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
