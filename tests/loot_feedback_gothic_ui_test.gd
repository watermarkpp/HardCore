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

	layer.show_feedback({
		"event_type": "rare_drop",
		"item_name": "裁决之杖",
		"source_name": "祖玛教主",
		"source_is_boss": true,
	})
	assert(layer.rare_banner.visible, "Boss 高价值掉落横幅没有显示")
	assert(layer.rare_banner.get_meta("stable_id", "") == "loot.feedback.rare_drop", "高价值横幅稳定 ID 错误")
	assert(layer.rare_title.text == "Boss 掉落 · 裁决之杖", "Boss 掉落标题错误")
	layer.show_feedback({
		"event_type": "pickup_failed",
		"item_name": "裁决之杖",
		"reason": "背包已满",
	})
	assert(layer.failure_panel.visible, "背包已满提示没有显示")
	assert(layer.failure_label.text == "背包已满 · 裁决之杖", "拾取失败原因错误")

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
	assert(currency_label.size.y == 32 and rare_label.size.y == 32, "地面名称高度应保持轻量")
	print("LOOT_FEEDBACK_GOTHIC_UI_PASS：地面名称、分类颜色、三条拾取提示、满包失败和Boss高价值横幅均正常")
	get_tree().quit(0)
