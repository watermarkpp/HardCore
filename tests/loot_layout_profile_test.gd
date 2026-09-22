extends Node
const Layout := preload("res://scripts/loot_name_layout.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	LootPreferences.set_filter_level(0)
	var rows: Array = []
	for count: int in [10, 20, 40, 75, 150]:
		var pickups: Array = []
		var spawn_start := Time.get_ticks_usec()
		for i in range(count):
			var pickup := LootPickup.new()
			var item := GameData.get_item_record(130 if i % 2 else 80)
			pickup.setup_item_record({"item_id": item.itemId, "output_item_id": item.itemId, "item_name": item.name, "output_record": item}, null)
			pickup.position = Vector2((i % 10) * 18, (i / 10) * 16)
			pickup.set_meta("loot_registration_order", i)
			add_child(pickup)
			pickups.append(pickup)
		var spawn_usec := Time.get_ticks_usec() - spawn_start
		Layout.arrange(pickups)
		var times: Array = []
		for trial in range(20):
			var start := Time.get_ticks_usec()
			Layout.arrange(pickups)
			times.append(Time.get_ticks_usec() - start)
		times.sort()
		var offsets: Array = []
		for pickup: LootPickup in pickups:
			offsets.append([pickup.name_label_display_offset.x, pickup.name_label_display_offset.y])
			pickup.free()
		rows.append({"count": count, "spawn_usec": spawn_usec, "layout_p50_usec": times[10], "layout_p95_usec": times[18], "offsets": offsets})
	var label := OS.get_environment("HARDCORE_V92_LABEL")
	var file := FileAccess.open("res://outputs/repair_v92/loot_layout_%s.json" % label, FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	file.close()
	print("LOOT_LAYOUT_PROFILE_PASS ", rows.map(func(row: Dictionary) -> Array: return [row.count, row.spawn_usec, row.layout_p50_usec, row.layout_p95_usec]))
	get_tree().quit()
