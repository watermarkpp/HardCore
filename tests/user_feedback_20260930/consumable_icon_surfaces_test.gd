extends Node

const Cache := preload("res://scripts/ui_item_texture_cache.gd")
const Loot := preload("res://scripts/loot_pickup.gd")
var failures: Array[String] = []
var rows: Array = []

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	check(GameData.ensure_loaded(), "formal item catalog failed")
	PlayerState.inventory = [{"item_id": 910007, "name": "疗伤药", "count": 1}, {"item_id": 920001, "name": "万年雪霜", "count": 1}]
	var bag := InventoryPanel.new()
	add_child(bag)
	while not bag._bag_cells_ready: await get_tree().process_frame
	bag.refresh()
	for i in 2:
		var stack: Dictionary = PlayerState.inventory[i]
		var record := GameData.get_item_record({"item_id": stack.item_id})
		check(str(record.get("name", "")) == stack.name, "stable item identity drift: " + str(stack.item_id))
		var icon := bag._bag_cells[i].get_node("ItemButton/CenteredPixelIcon") as TextureRect
		check(icon.visible and icon.texture != null, str(stack.item_id) + ": bag missing real texture")
		for role in ["inventoryIcon", "groundIcon"]:
			var path := GameData.get_item_art_path({"item_id": stack.item_id}, role)
			check(not path.is_empty() and "/fallback/" not in path, str(stack.item_id) + ": " + role + " remains placeholder")
			var texture := Cache.texture_at_path(path)
			check(texture != null, str(stack.item_id) + ": " + role + " texture cannot load")
			if texture != null:
				check(texture.get_image().get_used_rect().has_area(), str(stack.item_id) + ": " + role + " transparent pixels")
			rows.append({"id": stack.item_id, "role": role, "path": path, "loaded": texture != null})
		var drop := Loot.new()
		drop.setup_item_record({"item_id": stack.item_id, "output_item_id": stack.item_id, "item_name": stack.name, "output_record": record}, null)
		add_child(drop)
		check(drop.icon_sprite != null and drop.icon_sprite.texture != null and drop.icon_sprite.visible, str(stack.item_id) + ": ground pickup missing texture")
		drop.free()
	bag.queue_free()
	await get_tree().process_frame
	FileAccess.open("res://outputs/test_logs/consumable_icon_surfaces.json", FileAccess.WRITE).store_string(JSON.stringify({"rows": rows, "failures": failures}, "  "))
	print("CONSUMABLE_ICON_SURFACES_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
