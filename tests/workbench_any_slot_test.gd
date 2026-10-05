extends Node

func _ready() -> void:
	_run.call_deferred()

func _stack(id: int) -> Dictionary:
	var record := GameData.get_item_record({"item_id": id})
	return {"item_id": id, "name": str(record.name), "count": 1}

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	assert(GameData.ensure_loaded())
	PlayerState.gold = 1000000
	# Each role must work in every cell; enumeration only quotes, never rolls.
	for offset in 9:
		for rotation in 4:
			PlayerState.forge_tray = PlayerState._empty_workbench_tray()
			var ids := [100, 940013, 239, 239]
			for role in 4:
				PlayerState.forge_tray[(offset + role) % 9] = _stack(ids[(role + rotation) % 4])
			assert(PlayerState.quote_forge_tray().valid, "valid ingredients must work at every cell")
	PlayerState.forge_tray = PlayerState._empty_workbench_tray()
	# Exact arrangement read from the device. A ring is in slot 0, not 5.
	for pair in [[0, 239], [1, 940013], [3, 239], [4, 100]]:
		PlayerState.forge_tray[pair[0]] = _stack(pair[1])
	var panel := EnhancementPanel.new()
	add_child(panel)
	while not panel._bag_cells_ready or panel._bag_cell_initialization_running:
		await get_tree().process_frame
	panel._refresh_forge_information()
	assert(not panel.forge_button.disabled, "device wand + two Fashen rings + iron must enable forging")
	for extra_id in [100, 940013, 239, 950001]:
		PlayerState.forge_tray[8] = _stack(extra_id)
		panel._refresh_forge_information()
		assert(panel.forge_button.disabled, "extra equipment/material must disable forging")
		PlayerState.forge_tray[8] = {}
	panel._refresh_forge_information()
	var quote := PlayerState.quote_forge_tray()
	assert(quote.valid and quote.target_index == 4 and quote.accessory_a_index == 0 and quote.accessory_b_index == 3)
	assert(PlayerState.commit_forge(quote).committed)
	assert(PlayerState.forge_tray[0].is_empty() and PlayerState.forge_tray[1].is_empty() and PlayerState.forge_tray[3].is_empty())
	assert(int(PlayerState.forge_tray[4].item_id) == 100)
	for index in 4:
		PlayerState.synthesis_tray[index] = _stack(950001)
	panel._set_mode("synthesis")
	panel._on_synthesis_recipe_pressed(0)
	assert(not panel.forge_button.disabled, "device four fragments including slot 0 must enable synthesis")
	PlayerState.synthesis_tray[8] = _stack(950001)
	panel._refresh_forge_information()
	assert(panel.forge_button.disabled, "a fifth fragment must disable synthesis")
	PlayerState.synthesis_tray[8] = {}
	panel._refresh_forge_information()
	var result: Dictionary = PlayerState.commit_relic_synthesis(panel._synthesis_quote)
	assert(result.committed)
	assert(int(PlayerState.synthesis_tray[0].item_id) == int(result.item_id))
	for index in range(1, 9):
		assert(PlayerState.synthesis_tray[index].is_empty())
	# A persisted tray item must be removable by selecting it, then a bag cell.
	PlayerState.synthesis_tray[8] = JSON.parse_string(JSON.stringify(_stack(950001)))
	panel._selected_workbench_slot = -1
	panel._refresh_forge_information()
	_tap(panel.forge_slots[8])
	var destination := panel._bag_cells[70].get_child(0) as Button
	assert(not destination.disabled, "selecting a tray item must enable an empty bag destination immediately")
	_tap(destination)
	assert(PlayerState.synthesis_tray[8].is_empty(), "one bag click must finish tray removal")
	assert(int(PlayerState.inventory[70].get("item_id", -1)) == 950001)
	var after := PlayerState.inventory.duplicate(true)
	_tap(destination)
	assert(PlayerState.inventory == after, "duplicate destination click must not duplicate the item")
	panel.free()
	print("WORKBENCH_ANY_SLOT_PASS")
	get_tree().quit(0)

func _tap(button: Button) -> void:
	for down in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = down
		event.position = button.size * 0.5
		button.gui_input.emit(event)
