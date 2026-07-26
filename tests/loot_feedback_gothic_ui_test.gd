extends Node

const CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/loot_feedback_contract_v1.json"
const LootFeedbackLayerScript := preload("res://scripts/loot_feedback_layer.gd")
const LootGroundLabelScript := preload("res://scripts/loot_ground_label.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	assert(contract is Dictionary, "战利品反馈契约无法解析")
	assert(contract.get("contractId", "") == "ui.loot.feedback.v1", "战利品反馈契约 ID 错误")
	var stable_ids: Array = contract.get("stableVisualIds", [])
	for stable_id in ["loot.ground_label", "loot.feedback.normal", "loot.feedback.inventory_full", "loot.feedback.rare_drop"]:
		assert(stable_id in stable_ids, "缺少稳定视觉 ID：%s" % stable_id)

	var layer: Control = LootFeedbackLayerScript.new()
	add_child(layer)
	await get_tree().process_frame
	layer.show_feedback({"event_type": "pickup_success", "item_name": "金币", "count": 120, "item_kind": "currency"})
	layer.show_feedback({"event_type": "pickup_success", "item_name": "沃玛号角", "count": 1, "item_kind": "quest_item"})
	layer.show_feedback({"event_type": "pickup_success", "item_name": "强效太阳水", "count": 2, "item_kind": "consumable"})
	layer.show_feedback({"event_type": "pickup_success", "item_name": "多余物品", "count": 1, "item_kind": "material"})
	assert(layer.toast_container.get_child_count() == 3, "普通拾取提示没有限制为最近三条")
	assert(layer.toast_container.get_child(0).get_meta("stable_id", "") == "loot.feedback.normal", "普通提示稳定 ID 错误")
	assert("多余物品" in layer.toast_container.get_child(0).get_node("Text").text, "最新拾取提示没有置顶")
	assert(layer.toast_container.get_child(0).size.y == 30, "普通拾取提示仍然过高")
	assert(layer.toast_container.get_child(0).size.x < layer.toast_container.size.x, "普通拾取提示没有按文字裁切")

	layer.show_feedback({
		"event_type": "rare_drop",
		"item_name": "裁决之杖",
		"source_name": "祖玛教主",
		"source_is_boss": true,
	})
	assert(layer.rare_banner.visible, "Boss 高价值掉落横幅没有显示")
	assert(layer.rare_banner.get_meta("stable_id", "") == "loot.feedback.rare_drop", "高价值横幅稳定 ID 错误")
	assert(layer.rare_title.text == "Boss 掉落 · 裁决之杖", "Boss 掉落标题错误")
	assert(layer.rare_banner.size.y == 56 and layer.rare_banner.size.x <= 420, "Boss 横幅仍然占用过多空间")
	layer.show_feedback({
		"event_type": "pickup_failed",
		"item_name": "裁决之杖",
		"reason": "背包已满",
	})
	assert(layer.failure_panel.visible, "背包已满提示没有显示")
	assert(layer.failure_label.text == "背包已满 · 裁决之杖", "拾取失败原因错误")
	assert(layer.failure_panel.size.y == 36 and layer.failure_panel.size.x < 300, "背包已满提示没有裁切多余空间")

	var currency_label: Control = LootGroundLabelScript.new()
	currency_label.setup({"item_name": "金币", "count": 120, "item_kind": "currency", "emphasis": "normal"})
	add_child(currency_label)
	var rare_label: Control = LootGroundLabelScript.new()
	rare_label.setup({"item_name": "裁决之杖", "count": 1, "item_kind": "equipment", "emphasis": "boss"})
	add_child(rare_label)
	await get_tree().process_frame
	assert(currency_label.frame.theme_type_variation == "GothicLootGroundPanel", "普通地面名称样式错误")
	assert(rare_label.frame.theme_type_variation == "GothicLootRareGroundPanel", "高价值地面名称没有强化")
	assert(rare_label.frame.get_meta("stable_id", "") == "loot.ground_label", "地面名称稳定 ID 错误")
	assert(currency_label.size.y == 24 and rare_label.size.y == 24, "地面名称高度应保持轻量")
	var normal_style := layer.theme.get_stylebox("panel", "GothicLootToastPanel") as StyleBoxFlat
	var rare_style := layer.theme.get_stylebox("panel", "GothicLootRareBanner") as StyleBoxFlat
	var error_style := layer.theme.get_stylebox("panel", "GothicLootErrorPanel") as StyleBoxFlat
	for style: StyleBoxFlat in [normal_style, rare_style, error_style]:
		assert(style.bg_color.a < 0.80, "战利品反馈背景不是半透明灰色")
		assert(style.border_width_left == 1 and style.border_width_top == 1, "战利品反馈轮廓不是最细1像素")
	await _assert_landscape_safe_area_centering()
	print("LOOT_FEEDBACK_GOTHIC_UI_PASS：地面名称、分类颜色、三条拾取提示、满包失败和Boss高价值横幅均正常")
	get_tree().quit(0)


func _assert_landscape_safe_area_centering() -> void:
	var cases := [
		{"name": "1280x720", "viewport": Vector2(1280, 720), "safe": Rect2(0, 0, 1280, 720)},
		{"name": "2400x1080", "viewport": Vector2(2400, 1080), "safe": Rect2(80, 0, 2240, 1080)},
		{"name": "2664x1200", "viewport": Vector2(2664, 1200), "safe": Rect2(120, 0, 2544, 1200)},
	]
	for entry: Dictionary in cases:
		var viewport_size: Vector2 = entry.viewport
		var safe_rect: Rect2 = entry.safe
		assert(safe_rect.end.x <= viewport_size.x, "%s 测试安全区越出视口" % entry.name)
		var safe_root := Control.new()
		safe_root.position = safe_rect.position
		safe_root.size = safe_rect.size
		add_child(safe_root)
		var feedback: Control = LootFeedbackLayerScript.new()
		safe_root.add_child(feedback)
		await get_tree().process_frame
		feedback.show_feedback({"event_type": "pickup_success", "item_name": "金币", "count": 1, "item_kind": "currency"})
		feedback.show_feedback({"event_type": "rare_drop", "item_name": "裁决之杖", "source_is_boss": true})
		feedback.show_feedback({"event_type": "pickup_failed", "item_name": "裁决之杖", "reason": "背包已满"})
		var expected_center_x := safe_rect.get_center().x
		var centered_controls: Array[Control] = [
			feedback.toast_container,
			feedback.toast_container.get_child(0) as Control,
			feedback.rare_banner,
			feedback.failure_panel,
		]
		for control: Control in centered_controls:
			var actual_center_x := control.get_global_rect().get_center().x
			assert(absf(actual_center_x - expected_center_x) <= 1.0, "%s 拾取提示没有对准可用安全区中心：%.2f != %.2f" % [entry.name, actual_center_x, expected_center_x])
		assert(is_equal_approx(feedback.toast_container.position.y, 108.0), "%s 普通拾取提示纵向位置漂移" % entry.name)
		assert(is_equal_approx(feedback.rare_banner.position.y, 104.0), "%s 稀有掉落横幅纵向位置漂移" % entry.name)
		assert(is_equal_approx(feedback.failure_panel.position.y, 122.0), "%s 拾取失败提示纵向位置漂移" % entry.name)
		safe_root.queue_free()
		await get_tree().process_frame
