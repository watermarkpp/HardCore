extends Node
## 2026-09-26 approved contract: names stay centered above their own icon.
## Spawn/removal/filter events must not move existing names or ground items.
const Manager := preload("res://scripts/loot_pickup_runtime_manager.gd")
const Layout := preload("res://scripts/loot_name_layout.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded())
	LootPreferences.set_filter_level(0)
	var manager := Manager.new()
	add_child(manager)
	manager.configure_map(1, 1, func(p: Vector2) -> Vector2: return p, func(p: Vector2) -> Vector2: return p)
	var pickups: Array = []
	var positions: Array[Vector2] = []
	# Deliberately crowded: centering remains the rule even when text overlaps.
	for index in range(150):
		var pickup := LootPickup.new()
		var item := GameData.get_item_record(80 if index % 2 == 0 else 130)
		pickup.setup_item_record({"item_id": item.itemId, "output_item_id": item.itemId, "item_name": item.name, "output_record": item}, null)
		if index == 1:
			pickup.setup_gold(12345, null)
		elif index == 3:
			# Presentation fixture only: exercise a name wider than its neighbors.
			pickup.item_name = "超长名称显示测试装备超长名称显示测试装备"
		pickup.position = Vector2((index % 15) * 10.0, (index / 15) * 8.0)
		positions.append(pickup.position)
		add_child(pickup)
		assert(manager.register_pickup(pickup))
		pickups.append(pickup)
		# Staggered arrival used to trigger another full layout each frame.
		if index % 10 == 0:
			await get_tree().process_frame
			_assert_home(pickups, positions)
	await get_tree().process_frame
	_assert_home(pickups, positions)
	assert(pickups[1].name_label.text == "金币 12345")
	assert(pickups[3].name_plate_size.x > pickups[0].name_plate_size.x)
	var long_name_rect := Rect2(pickups[3].global_position + pickups[3].name_label.position, pickups[3].name_label.size)
	var neighbor_rect := Rect2(pickups[4].global_position + pickups[4].name_label.position, pickups[4].name_label.size)
	assert(long_name_rect.intersects(neighbor_rect), "overlapping names must keep their own anchors")
	var placement_count: int = manager.get("name_placement_count")
	assert(placement_count == 150, "only each new item may require placement")
	for index in range(5):
		await get_tree().process_frame
	assert(manager.get("name_placement_count") == placement_count)
	LootPreferences.set_filter_level(1)
	await get_tree().process_frame
	assert(manager.get("name_placement_count") == placement_count, "filter must not reposition names")
	for index in range(0, 150, 2):
		assert(not pickups[index].name_label.visible)
	LootPreferences.set_filter_level(0)
	await get_tree().process_frame
	_assert_home(pickups, positions)
	# Removing half the pile must neither move nor recompute the survivors.
	for index in range(149, 74, -1):
		manager.unregister_pickup(pickups[index])
		pickups[index].queue_free()
		pickups.remove_at(index)
		positions.remove_at(index)
	await get_tree().process_frame
	_assert_home(pickups, positions)
	assert(manager.get("name_placement_count") == placement_count)
	# Moving an item moves its local child name with it, with no group layout.
	pickups[0].position += Vector2(500, 80)
	positions[0] = pickups[0].position
	assert(manager.update_pickup_position(pickups[0]))
	await get_tree().process_frame
	_assert_home(pickups, positions)
	assert(manager.get("name_placement_count") == placement_count)
	var started := Time.get_ticks_usec()
	Layout.arrange(pickups)
	var elapsed := Time.get_ticks_usec() - started
	assert(elapsed < 8000, "explicit batch positioning must remain bounded")
	for pickup: LootPickup in pickups:
		pickup.queue_free()
	await get_tree().process_frame
	manager.queue_free()
	await get_tree().process_frame
	print("GROUND_NAMES_HOME_FIRST_PASS fixed_home=150 staggered=true survivors=75 no_group_relayout=true explicit_batch_usec=", elapsed)
	get_tree().quit(0)

func _assert_home(pickups: Array, positions: Array[Vector2]) -> void:
	for index in range(pickups.size()):
		var pickup: LootPickup = pickups[index]
		assert(pickup.position == positions[index], "name layout must never move ground loot")
		assert(pickup.name_label_display_offset == Vector2.ZERO, "name must stay over its own item")
		assert(pickup.name_label.position == pickup.name_label_home_position())
		assert(is_zero_approx(pickup.name_label.position.x + pickup.name_plate_size.x * 0.5))
		assert(pickup.name_label.position.y < pickup.icon_sprite.position.y)
		assert(pickup.z_index == -2 and not pickup.z_as_relative)
		assert(pickup.name_label.z_index == 1 and not pickup.name_label.z_as_relative)
