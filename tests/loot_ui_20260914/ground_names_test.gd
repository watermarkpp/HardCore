extends Node
const Manager := preload("res://scripts/loot_pickup_runtime_manager.gd")
const Layout := preload("res://scripts/loot_name_layout.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded())
	LootPreferences.set_filter_level(0)
	var manager := Manager.new()
	add_child(manager)
	manager.configure_map(1,1,func(p:Vector2)->Vector2:return p,func(p:Vector2)->Vector2:return p)
	var pickups: Array = []
	var before: Array = []
	var target := PlayerCharacter.new()
	for i in range(150):
		var pickup := LootPickup.new()
		var item := GameData.get_item_record(130 if i % 2 else 80)
		var item_id := GameData._stable_item_id(item)
		pickup.setup_item_record({"item_id":item_id,"output_item_id":item_id,"item_name":item.name,"output_record":item},target)
		pickup.position = Vector2((i % 15) * 10, (i / 15) * 8)
		add_child(pickup)
		assert(pickup.z_index == -2 and not pickup.z_as_relative)
		assert(manager.register_pickup(pickup))
		pickups.append(pickup)
		before.append(pickup.global_position)
	await get_tree().process_frame
	assert(manager.name_layout_count == 1, "burst must coalesce into one layout")
	var start := Time.get_ticks_usec()
	Layout.arrange(pickups)
	var elapsed := Time.get_ticks_usec() - start
	var columns: Dictionary = {}
	for i in range(pickups.size()):
		assert(pickups[i].global_position == before[i])
		var rect: Rect2 = pickups[i].name_label.get_global_rect()
		columns[rect.position.x] = true
		for j in range(i): assert(not rect.intersects(pickups[j].name_label.get_global_rect()))
	assert(columns.size() == 2)
	for i in range(5): await get_tree().process_frame
	assert(manager.name_layout_count == 1, "idle frames must not relayout")
	LootPreferences.set_filter_level(1)
	await get_tree().process_frame
	assert(manager.name_layout_count == 2)
	for i in range(0,150,2): assert(not pickups[i].name_label.visible)
	for pickup: LootPickup in pickups: pickup.queue_free()
	await get_tree().process_frame
	manager.queue_free()
	target.free()
	await get_tree().process_frame
	print("GROUND_NAMES_V81_PASS count=150 layout_usec=%d coalesced=1 columns=2 identities_unchanged=true" % elapsed)
	get_tree().quit()
