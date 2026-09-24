extends Node

const BlackIron := preload("res://scripts/layers/rules/equipment_enhancement_black_iron.gd")
const Detail := preload("res://scripts/item_detail_presenter.gd")


func _ready() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	PlayerState.reset_progress(false)
	assert(BlackIron.records().size() == 11)
	assert(GameData.get_item_record("黑铁矿").is_empty(), "retired name-only ore must not enter gameplay")
	assert(GameData.get_item_record({"service_index": 828}).is_empty(), "retired service ore must not enter gameplay")
	for purity in range(10, 21):
		var item_id := 940000 + purity
		var item := GameData.get_item_record({"item_id": item_id})
		assert(item.itemId == item_id and item.name == "黑铁矿")
		assert(item.kind == "material" and item.category == "矿石" and item.purity == purity)
		assert(not item.stackable and item.maxStack == 1 and item.weight == 1)
		assert(BlackIron.purity_for({"item_id": item_id, "name": "黑铁矿"}) == purity)
		assert(not GameData.get_item_art_path({"item_id": item_id}).is_empty())
		assert(Detail.format_item(item).begins_with("类别：矿石\n纯度：%d\n" % purity))
		assert("[color=#b58a45]乌黑色的矿石，天外陨石的碎片[/color]" in Detail.format_item(item))
		assert(GameData.get_item_price_record({"item_id": item_id, "name": "黑铁矿"}).is_empty(), "ore must not have a merchant price")
	assert(BlackIron.purity_for({"service_index": 828, "name": "黑铁矿"}) == -1)
	var a := PlayerState.receive_record({"item_id": 940010, "name": "黑铁矿", "count": 2}, false)
	var b := PlayerState.receive_record({"item_id": 940011, "name": "黑铁矿", "count": 3}, false)
	assert(bool(a.success) and bool(b.success))
	assert(PlayerState.inventory.size() == 5, "ore must occupy one slot per unit")
	assert(PlayerState.inventory_weight() == 5, "each ore must weigh one, independent of purity")
	for slot: int in range(PlayerState.inventory.size()):
		assert(int(PlayerState.inventory[slot].count) == 1)
		assert(int(PlayerState.inventory[slot].item_id) == (940010 if slot < 2 else 940011))
	print("EQUIPMENT_ENHANCEMENT_BLACK_IRON_PASS")
	get_tree().quit(0)
