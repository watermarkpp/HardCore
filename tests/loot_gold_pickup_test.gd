extends Node

const LootPickupScript := preload("res://scripts/loot_pickup.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded(), "GameData canonical catalog failed to load")
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.gold = 0
	PlayerState.inventory = []

	var target := PlayerCharacter.new()
	add_child(target)
	target.global_position = Vector2.ZERO

	var loot := LootPickupScript.new()
	add_child(loot)
	loot.setup_gold(3000, target)
	loot.global_position = Vector2.ZERO

	assert(str(loot.item_name) == "金币", "setup_gold item_name must be 金币")
	assert(int(loot.gold_amount) == 3000, "setup_gold gold_amount must be 3000")

	var gold_before := PlayerState.gold
	var inventory_before := PlayerState.inventory.duplicate(true)

	loot.gold_collected.connect(_on_gold_collected)
	# Player in pickup range: gold path must collect without inventory/weight gate.
	loot._process(0.0)

	assert(PlayerState.gold == gold_before + 3000, "gold was not added to PlayerState")
	assert(PlayerState.inventory == inventory_before, "gold pickup must not change inventory")
	assert(not loot.collection_pending() or loot.is_queued_for_deletion(), "gold pickup should be confirmed")

	# Gold must not create an inventory 金币 item.
	for item: Variant in PlayerState.inventory:
		assert(not (item is Dictionary and str(item.get("name", "")) == "金币"), "inventory gained a 金币 item")

	loot.free()
	target.free()
	print("LOOT_GOLD_PICKUP_PASS: gold=3000 inventory_unchanged=1 no_coin_item=1")
	get_tree().quit(0)


func _on_gold_collected(amount: int, pickup: LootPickup) -> void:
	PlayerState.add_gold(amount)
	pickup.confirm_collect()
