extends Node

## QA latency driver for the UI-L1 measure trees (identical on Before/After).
## Drives the real HUD/panel handlers so the instrument overlay records the
## real production spans. test_mode stays false: every purchase/selection runs
## the real save chain into the isolated APPDATA. The trace controller stops
## and writes user://ui_latency_l1/*.json when this scene exits.

func settle(frames: int) -> void:
	for unused in range(frames):
		await get_tree().process_frame

func _ready() -> void:
	PlayerState.test_mode = false
	_run.call_deferred()

func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await settle(40)  # cold-start window before first interaction
	var hud: GameHUD = game.hud
	# Cold first opens (L1-F cold path, L1-A hidden bank, L1-C repair preview).
	hud.open_shop("测量商人", [{"name": "金创药(小量)", "item_id": "金创药(小量)", "count": 50}], {"mode": "sell"})
	await settle(30)
	hud.call("_toggle_inventory")  # close shop by switching
	await settle(20)
	# Real purchase x5 through the ShopPanel transaction path (L1-D/E).
	var shop: Control = hud.get("shop_panel")
	if shop != null and shop.has_method("open_for"):
		var stock: Array = []
		for i: int in range(5):
			stock.append({"name": "金创药(小量)", "item_id": "金创药(小量)", "count": 10})
		shop.call("open_for", "测量商人", stock, {"mode": "sell"})
		await settle(20)
		for i: int in range(stock.size()):
			shop.call("_on_item_selected", i)
			await settle(6)
			shop.call("buy_shop_item", i, 1)
			await settle(6)
	# Warehouse open/close twice (L1-A bank display routing).
	for round_index: int in range(2):
		hud.call("open_warehouse")
		await settle(25)
		if round_index == 0:
			hud.call("_toggle_inventory")
			await settle(15)
	hud.call("_toggle_inventory")
	await settle(20)
	# Inventory open/close cycles (L1-B preview single owner).
	for round_index: int in range(2):
		hud.call("_toggle_inventory")
		await settle(20)
	# Equip/unequip x10 through the authoritative transaction (save each).
	var record: Dictionary = PlayerState.add_item("木剑", 1)
	if not record.is_empty():
		for i: int in range(10):
			PlayerState.inventory = [PlayerState.inventory[0]] if PlayerState.inventory.is_empty() == false and i == 0 else PlayerState.inventory
			var equipped_slot := ""
			for key: Variant in PlayerState.equipment:
				equipped_slot = str(key)
			if not PlayerState.inventory.is_empty():
				PlayerState.call("equip_inventory_index_result", 0)
			await settle(4)
			if not equipped_slot.is_empty():
				PlayerState.call("unequip_to_inventory_slot", equipped_slot, 0)
			await settle(4)
	await settle(30)
	print("UI_L1_QA_DRIVER_DONE")
	get_tree().quit(0)
