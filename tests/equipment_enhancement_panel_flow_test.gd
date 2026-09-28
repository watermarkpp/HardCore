extends Node

const EnhancementPanelScript := preload("res://scripts/enhancement_panel.gd")

class NoticeHost extends Control:
	var messages: Array[String] = []

	func show_error_message(message: String, _seconds := 2.0) -> void:
		messages.append(message)

	func show_success_message(message: String) -> void:
		messages.append(message)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	PlayerState.reset_progress(false)
	for item_id: int in [81, 940010, 191, 192]:
		var item := GameData.get_item_record({"item_id": item_id})
		assert(bool(PlayerState.receive_record({"item_id": item_id, "name": str(item.name)}, false).success))
	PlayerState.gold = 1000000
	var host := NoticeHost.new()
	add_child(host)
	var panel := EnhancementPanelScript.new()
	host.add_child(panel)
	for frame in 4:
		await get_tree().process_frame
	assert(panel.forge_button.disabled, "incomplete inputs must keep action disabled")
	# Invalid contents are removable; validity belongs to the action button.
	assert(PlayerState.place_workbench_item("forge", 1, _index_for_id(191)).success)
	panel._refresh_forge_information()
	assert(panel.forge_button.disabled)
	assert(PlayerState.take_workbench_item("forge", 1).success)
	# Materials before equipment is a supported order, with the same quote.
	for placement: Array in [[940010, 1], [191, 3], [192, 5], [81, 4]]:
		panel.selected_inventory_index = _index_for_id(int(placement[0]))
		panel._on_forge_slot_pressed(int(placement[1]))
	assert(not panel.forge_button.disabled)
	# Extra equipment must be accepted into an empty cell, then invalidate
	# both the real quote and the UI until the user removes it.
	var extra := GameData.get_item_record({"item_id": 81})
	assert(PlayerState.receive_record({"item_id": 81, "name": str(extra.name)}, false).success)
	assert(PlayerState.place_workbench_item("forge", 8, _index_for_id(81)).success)
	panel._refresh_forge_information()
	assert(panel.forge_button.disabled and not PlayerState.quote_forge_tray().valid)
	assert(PlayerState.take_workbench_item("forge", 8).success)
	var available_gold := PlayerState.gold
	PlayerState.gold = 0
	panel._refresh_forge_information()
	assert(panel.forge_button.disabled, "unaffordable forge must not light up")
	PlayerState.gold = available_gold
	panel._refresh_forge_information()
	assert(not panel.forge_button.disabled)
	assert("%" in panel.chance_label.text)
	assert("100000" in panel.fee_label.text)
	var gold_before := PlayerState.gold
	panel.forge_button.pressed.emit()
	assert(panel._forging)
	assert(panel.forge_button.disabled)
	assert(panel._forge_audio.playing)
	assert(PlayerState.gold < gold_before)
	await get_tree().create_timer(0.25).timeout
	assert(panel._forge_glow_overlays.size() == 9)
	assert((panel._forge_glow_overlays[0] as Panel).modulate.a > 0.0, "forge cell glow did not animate")
	await get_tree().create_timer(2.85).timeout
	assert(not panel._forging)
	assert(not panel._forge_audio.playing)
	assert(panel._forge_audio_plays_in_cycle == 3, "forge audio should start once per second for three seconds")
	assert((panel._forge_glow_overlays[0] as Panel).modulate.a == 0.0, "glow must stop after forge result")
	assert(host.messages.size() == 1)
	assert(panel.forge_button.disabled, "consumed materials must disable the next action")
	assert((panel.forge_artwork["ForgeImageSuccess"] as TextureRect).visible != (panel.forge_artwork["ForgeImageFailure"] as TextureRect).visible)
	var inventory_after := PlayerState.inventory.duplicate(true)
	var gold_after := PlayerState.gold
	panel.preview_forge_animation()
	await get_tree().create_timer(0.25).timeout
	assert(panel._forging and (panel._forge_glow_overlays[0] as Panel).modulate.a > 0.0)
	await get_tree().create_timer(2.85).timeout
	assert(not panel._forging and panel._forge_audio_plays_in_cycle == 3)
	assert((panel.forge_artwork["ForgeImageInitial"] as TextureRect).visible)
	assert(PlayerState.inventory == inventory_after and PlayerState.gold == gold_after, "calibrator animation preview changed player resources")
	print("EQUIPMENT_ENHANCEMENT_PANEL_FLOW_PASS")
	get_tree().quit(0)


func _index_for_id(item_id: int) -> int:
	for index in range(PlayerState.inventory.size()):
		var value: Variant = PlayerState.inventory[index]
		if value is Dictionary and int((value as Dictionary).get("item_id", -1)) == item_id:
			return index
	return -1
