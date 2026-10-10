extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const InventoryPanelScript := preload("res://scripts/inventory_panel.gd")
const Root := preload("res://scripts/game_root.gd")

var proof := Proof.new()
var failures: Array[String] = []
var panel: InventoryPanel
var formal_equipment_changed_count := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _on_formal_equipment_changed() -> void:
	formal_equipment_changed_count += 1

func _armor_instance(current_raw: int, maximum_raw := 10000) -> Dictionary:
	return {
		"name": "天魔神甲",
		"item_id": 140,
		"count": 1,
		"instance_id": "b14-durability-armor",
		"durability_raw": current_raw,
		"max_durability_raw": maximum_raw,
		"durability": int(ceil(float(current_raw) / 1000.0)) if current_raw > 0 else 0,
		"max_durability": int(ceil(float(maximum_raw) / 1000.0)),
	}

func _apply_incoming_physical_hit() -> Dictionary:
	return PlayerState.apply_durability_event(
		PlayerState.DURABILITY_EVENT_INCOMING_PHYSICAL_STRUCK,
		{
			"damage": 10,
			"damage_type": "physical",
			"causes_struck": true,
			"armor_roll": 0,
			"slot_rolls": {
				"hc.slot.armor": 1,
				"hc.slot.weapon": 1,
				"hc.slot.helmet": 1,
				"hc.slot.necklace": 1,
				"hc.slot.bracelet_left": 1,
				"hc.slot.bracelet_right": 1,
				"hc.slot.ring_left": 1,
				"hc.slot.ring_right": 1,
				"hc.slot.belt": 1,
				"hc.slot.boots": 1,
				"hc.slot.relic": 1,
				"hc.slot.badge": 1,
			},
		}
	)

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 40
	PlayerState.recalculate_stats()
	PlayerState.equipment = PlayerState._empty_equipment()
	PlayerState.equipment["hc.slot.armor"] = _armor_instance(10000)
	# Ordinary stack records intentionally have no instance_id.  The stale-ref
	# guard must still reject them after a real inventory topology change.
	PlayerState.inventory = [{"name": "太阳水", "item_id": "太阳水", "count": 3}]

	panel = InventoryPanelScript.new()
	add_child(panel)
	await panel.wait_until_runtime_ready()
	check(panel.visible, "formal inventory panel is visible")

	panel._select_inventory_item(0)
	check(panel.selected_inventory_index == 0, "ordinary stack is selected")
	check(panel.selected_inventory_ref.get("instance_id", "") == "", "selected stack has no opaque instance identity")
	var revision_before_durability := panel._selection_revision
	var hit := _apply_incoming_physical_hit()
	check(bool(hit.get("applied", false)), "physical hit changes authoritative armor durability")
	PlayerState._advance_durability_runtime(PlayerState.DURABILITY_VISUAL_INTERVAL)
	await get_tree().process_frame
	await get_tree().process_frame
	check(panel.selected_inventory_index == 0, "coalesced durability refresh preserves ordinary stack selection")
	check(panel.selected_inventory_indices.has(0), "coalesced durability refresh preserves multi-select index")
	check(panel._selection_revision == revision_before_durability, "equipment-only refresh does not advance inventory topology revision")

	panel._select_equipment_slot("hc.slot.armor")
	check(panel.selected_equipment_slot == "hc.slot.armor", "equipped armor slot is selected")
	var body_before := str(panel.item_detail_presenter.detail_label.text)
	var armor_after_hit: Dictionary = PlayerState.equipment["hc.slot.armor"]
	armor_after_hit["durability_raw"] = 5
	PlayerState._sync_durability_compatibility_fields(armor_after_hit)
	var crossed := _apply_incoming_physical_hit()
	check(bool(crossed.get("applied", false)), "physical hit crosses armor durability zero through authority")
	await get_tree().process_frame
	await get_tree().process_frame
	var body_after := str(panel.item_detail_presenter.detail_label.text)
	check(panel.selected_equipment_slot == "hc.slot.armor", "cross-zero refresh keeps selected equipment slot")
	check(body_after != body_before, "cross-zero equipment refresh rebuilds open detail snapshot")
	check("耐久" in body_after, "rebuilt equipment detail still presents durability")
	check(int((PlayerState.equipment["hc.slot.armor"] as Dictionary).get("durability_raw", -1)) == 0, "equipment authority is zero after cross-zero hit")

	panel.queue_free()
	await get_tree().process_frame
	await _run_formal_hud_path()
	_finish()

func _run_formal_hud_path() -> void:
	PlayerState.test_mode = false
	var root := Root.new()
	add_child(root)
	var ready_deadline := Time.get_ticks_msec() + 20000
	while not root.gameplay_input_is_enabled() and Time.get_ticks_msec() < ready_deadline:
		await get_tree().process_frame
	check(root.gameplay_input_is_enabled(), "normal Root reaches READY without test mode")
	if not root.gameplay_input_is_enabled():
		root.queue_free()
		return

	PlayerState.equipment = PlayerState._empty_equipment()
	PlayerState.equipment["hc.slot.armor"] = _armor_instance(10000)
	PlayerState.inventory = [{"name": "太阳水", "item_id": "太阳水", "count": 3}]
	PlayerState.equipment_changed.emit()
	PlayerState.inventory_changed.emit()
	PlayerState._durability_rng.seed = 20261010
	var inventory_button := root.hud.find_child("InventoryButton", true, false) as Button
	check(inventory_button != null, "normal HUD exposes the production inventory button")
	if inventory_button == null:
		root.queue_free()
		return
	inventory_button.pressed.emit()
	await get_tree().process_frame
	var formal_panel: InventoryPanel = root.hud.inventory_panel
	check(formal_panel != null and formal_panel.visible, "normal HUD opens the production inventory panel")
	if formal_panel == null:
		root.queue_free()
		return
	await formal_panel.wait_until_runtime_ready()
	formal_panel._select_inventory_item(0)
	check(formal_panel.selected_inventory_index == 0, "normal HUD selects the legal ordinary stack")
	check(formal_panel.selected_inventory_ref.get("instance_id", "") == "", "normal HUD stack has no opaque instance identity")
	var formal_revision := formal_panel._selection_revision

	var player := root.player
	player.defense_min = 0
	player.defense_max = 0
	var hp_before := player.current_hp
	var armor_raw_before := int((PlayerState.equipment["hc.slot.armor"] as Dictionary).get("durability_raw", -1))
	formal_equipment_changed_count = 0
	if not PlayerState.equipment_changed.is_connected(_on_formal_equipment_changed):
		PlayerState.equipment_changed.connect(_on_formal_equipment_changed)
	player.take_damage(1, true, {"damage_type": "physical"})
	check(player.current_hp < hp_before, "normal Player physical hit resolves non-lethal damage")
	var armor_raw_after_hit := int((PlayerState.equipment["hc.slot.armor"] as Dictionary).get("durability_raw", -1))
	check(armor_raw_before == 10000 and armor_raw_after_hit < armor_raw_before, "normal Player physical hit reduces authoritative armor durability")
	PlayerState._advance_durability_runtime(PlayerState.DURABILITY_VISUAL_INTERVAL)
	await get_tree().process_frame
	await get_tree().process_frame
	check(formal_panel.selected_inventory_index == 0, "normal HUD coalesced durability preserves ordinary stack selection")
	check(formal_panel._selection_revision == formal_revision, "normal HUD equipment-only durability keeps topology revision")
	check(formal_equipment_changed_count > 0, "normal HUD coalesced durability emits equipment_changed")

	formal_panel._select_equipment_slot("hc.slot.armor")
	check(formal_panel.selected_equipment_slot == "hc.slot.armor", "normal HUD selects equipped armor")
	var body_before := str(formal_panel.item_detail_presenter.detail_label.text)
	var armor: Dictionary = PlayerState.equipment["hc.slot.armor"]
	armor["durability_raw"] = 5
	PlayerState._sync_durability_compatibility_fields(armor)
	var hp_before_cross := player.current_hp
	player.take_damage(1, true, {"damage_type": "physical"})
	check(player.current_hp < hp_before_cross, "normal Player second physical hit resolves")
	await get_tree().process_frame
	await get_tree().process_frame
	var body_after := str(formal_panel.item_detail_presenter.detail_label.text)
	check(formal_panel.selected_equipment_slot == "hc.slot.armor", "normal HUD cross-zero refresh preserves equipment slot")
	check(body_after != body_before, "normal HUD cross-zero refresh rebuilds open detail snapshot")
	var markup := RegEx.new()
	markup.compile("\\[[^\\]]*\\]")
	var plain_body := markup.sub(body_after, "", true)
	var durability_field := RegEx.new()
	durability_field.compile("耐久(?:：|:|\\s+)(\\d+)/(\\d+)")
	var durability_match := durability_field.search(plain_body)
	var expected_durability := int(armor.get("durability", -1))
	var expected_max_durability := int(armor.get("max_durability", -1))
	check(
		durability_match != null
			and int(durability_match.get_string(1)) == expected_durability
			and int(durability_match.get_string(2)) == expected_max_durability,
		"normal HUD detail shows exact current durability/max"
	)
	check(int(armor.get("durability_raw", -1)) == 0, "normal HUD authority reaches zero durability")

	# Topology mutation remains fail-closed for a no-instance-id stack.
	formal_panel._select_inventory_item(0)
	PlayerState.inventory = [{"name": "超级魔法药水", "item_id": "超级魔法药水", "count": 1}]
	PlayerState.inventory_changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check(formal_panel.selected_inventory_index == -1, "normal inventory topology change retires stale no-id selection")
	check(formal_panel.selected_inventory_refs.is_empty(), "normal inventory topology change clears stale refs")
	if PlayerState.equipment_changed.is_connected(_on_formal_equipment_changed):
		PlayerState.equipment_changed.disconnect(_on_formal_equipment_changed)
	root.queue_free()
	await get_tree().process_frame

func _finish() -> void:
	var written := proof.write_receipt(
		"v109_inventory_durability_projection_test",
		proof.records.size(),
		failures.size()
	)
	print(
		"V109_INVENTORY_DURABILITY_PROJECTION_",
		"PASS" if written and failures.is_empty() else "FAIL",
		" checks=", proof.records.size(),
		" failures=", failures
	)
	get_tree().quit(0 if written and failures.is_empty() else 1)
