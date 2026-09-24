extends Node

const Detail := preload("res://scripts/item_detail_presenter.gd")
const ItemTextures := preload("res://scripts/ui_item_texture_cache.gd")
const LootPickupScript := preload("res://scripts/loot_pickup.gd")
const ITEM_ID := 950001
const ITEM_NAME := "远古圣物碎片"


func _ready() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	PlayerState.reset_progress(false)
	var item := GameData.get_item_record({"item_id": ITEM_ID})
	assert(int(item.get("itemId", -1)) == ITEM_ID)
	assert(str(item.get("name", "")) == ITEM_NAME)
	assert(str(item.get("kind", "")) == "material")
	assert(str(item.get("category", "")) == "材料")
	assert(int(item.get("weight", -1)) == 1)
	assert(not bool(item.get("stackable", true)) and int(item.get("maxStack", -1)) == 1)
	assert(str(item.get("useEffect", "")) == "none" and not bool(item.get("usable", true)))
	var inventory_icon := ItemTextures.texture_for(item, "inventoryIcon")
	var ground_icon := ItemTextures.texture_for(item, "groundIcon")
	assert(inventory_icon != null and ground_icon != null)
	assert(inventory_icon.get_size() != ground_icon.get_size(), "inventory and ground art must be distinct")
	assert(GameData.get_item_art_path({"item_id": ITEM_ID}, "inventoryIcon") != GameData.get_item_art_path({"item_id": ITEM_ID}, "groundIcon"))
	var ground_descriptor := LootPickupScript.ground_visual_descriptor(ITEM_NAME)
	assert(str(ground_descriptor.get("path", "")) == GameData.get_item_art_path({"item_id": ITEM_ID}, "groundIcon"))
	assert(Detail.format_item(item) == "类别：材料\n重量：1\n[color=#b58a45]不知道是什么，似乎拥有一种神秘力量。[/color]")
	assert(GameData.get_item_price_record({"item_id": ITEM_ID, "name": ITEM_NAME}).is_empty())
	var received := PlayerState.receive_record({"item_id": ITEM_ID, "name": ITEM_NAME, "count": 2}, false)
	assert(bool(received.get("success", false)))
	assert(PlayerState.inventory.size() == 2 and PlayerState.inventory_weight() == 2)
	for slot: int in range(2):
		assert(int(PlayerState.inventory[slot].get("count", -1)) == 1)
		assert(int(PlayerState.inventory[slot].get("item_id", -1)) == ITEM_ID)
	print("ANCIENT_RELIC_FRAGMENT_PASS")
	get_tree().quit(0)
