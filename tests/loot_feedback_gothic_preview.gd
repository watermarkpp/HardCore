extends Control

const WORLD_TEXTURE := preload("res://assets/ui/gothic_preview/world_scene_reference.png")
const LootFeedbackLayerScript := preload("res://scripts/loot_feedback_layer.gd")
const LootGroundLabelScript := preload("res://scripts/loot_ground_label.gd")
const STANDARD_OUTPUT := "res://outputs/visual_acceptance/loot_feedback/loot_feedback_standard_v1.png"
const BOSS_OUTPUT := "res://outputs/visual_acceptance/loot_feedback/loot_feedback_boss_full_v1.png"

var feedback_layer: Control


func _ready() -> void:
	var world := TextureRect.new()
	world.name = "WorldBackdrop"
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.texture = WORLD_TEXTURE
	world.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	world.stretch_mode = TextureRect.STRETCH_SCALE
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)
	_add_ground_label(Vector2(474, 370), {"item_name": "金币", "count": 120, "item_kind": "currency", "emphasis": "normal"})
	_add_ground_label(Vector2(610, 424), {"item_name": "沃玛号角", "count": 1, "item_kind": "quest_item", "emphasis": "normal"})
	_add_ground_label(Vector2(770, 350), {"item_name": "裁决之杖", "count": 1, "item_kind": "equipment", "emphasis": "boss"})
	feedback_layer = LootFeedbackLayerScript.new()
	feedback_layer.name = "LootFeedbackLayer"
	add_child(feedback_layer)
	await get_tree().process_frame
	feedback_layer.show_feedback({"event_type": "pickup_success", "item_name": "金币", "count": 120, "item_kind": "currency"})
	feedback_layer.show_feedback({"event_type": "pickup_success", "item_name": "沃玛号角", "count": 1, "item_kind": "quest_item"})
	feedback_layer.show_feedback({"event_type": "pickup_success", "item_name": "强效太阳水", "count": 2, "item_kind": "consumable"})
	await get_tree().process_frame
	await get_tree().process_frame
	_save_viewport(STANDARD_OUTPUT)
	feedback_layer.clear_feedback()
	feedback_layer.show_feedback({
		"event_type": "rare_drop",
		"item_name": "裁决之杖",
		"source_name": "祖玛教主",
		"source_is_boss": true,
		"message": "祖玛教主掉落的高价值装备",
		"duration": 10.0,
	})
	feedback_layer.show_feedback({
		"event_type": "pickup_failed",
		"item_name": "裁决之杖",
		"reason": "背包已满",
		"duration": 10.0,
	})
	await get_tree().process_frame
	_save_viewport(BOSS_OUTPUT)
	print("LOOT_FEEDBACK_GOTHIC_PREVIEW_PASS：standard=%s boss=%s" % [STANDARD_OUTPUT, BOSS_OUTPUT])
	get_tree().quit(0)


func _add_ground_label(center: Vector2, data: Dictionary) -> void:
	var ground_label: Control = LootGroundLabelScript.new()
	ground_label.setup(data)
	ground_label.position = center - ground_label.size * 0.5
	add_child(ground_label)


func _save_viewport(path: String) -> void:
	var output_dir := ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(output_dir)
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	assert(error == OK, "无法保存战利品反馈样板：%s" % path)
