extends Node

const Root := preload("res://scripts/game_root.gd")
const Quest := preload("res://scripts/quest_panel.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.learned_skills = {"野蛮冲撞": 3}
	PlayerState.recalculate_stats(false)
	var game := Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 30000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "actual Root reaches READY")
	if not game.gameplay_input_is_enabled():
		_finish(game)
		return
	game.set_process(false)
	var quest := Quest.new()
	add_child(quest)
	var quest_id := "bich_beginner_gear"
	PlayerState.quest_states = {quest_id: {"status": "ready", "progress": {"稻草人": 3}}}
	PlayerState.gold = PlayerState.PLAYER_GOLD_CAP
	quest.open_for("老兵")
	check(quest.current_quest_id == quest_id and not quest.action_button.disabled, "real quest UI offers completed first reward")
	var inventory_before := PlayerState.inventory.duplicate(true)
	quest.action_button.pressed.emit()
	var rejected_message := quest.status_label.text
	check(rejected_message.contains("金币已达上限"), "formal claim rejects actual gold cap")
	await get_tree().process_frame
	await get_tree().process_frame
	check(quest.status_label.text == rejected_message, "deferred refresh preserves claim failure reason")
	check(PlayerState.gold == PlayerState.PLAYER_GOLD_CAP and PlayerState.inventory == inventory_before, "failed real claim changes no gold or items")
	check(PlayerState.quest_states[quest_id].status == "ready", "failed real claim keeps reward claimable")
	quest._select_quest("bich_field_hunt")
	quest._select_quest(quest_id)
	check(quest.status_label.text == "目标完成", "new user selection clears previous action failure")
	quest.action_button.pressed.emit()
	await get_tree().process_frame
	check(quest.status_label.text == rejected_message, "second actual rejection remains visible")
	quest._close()
	quest.open_for("老兵")
	check(quest.status_label.text == "目标完成", "new quest session starts with current owner state")

	game.hud._ensure_skill_panel()
	var panel: Node = game.hud.skill_panel
	panel.open_for("技能导师")
	var index := -1
	for i in panel.skill_entries.size():
		if str(panel.skill_entries[i].get("skillName", "")) == "野蛮冲撞": index = i
	check(index >= 0, "actual skill panel has formally learned assignable skill")
	if index >= 0:
		panel._open_assignment_popup_for(index)
		check(panel.assignment_popup.visible and panel.assignment_scrim.visible, "actual configuration popup opens")
		panel._begin_skill_long_press(index, Vector2.ZERO)
		var bindings_before: Dictionary = panel.skill_button_assignments.duplicate(true)
		game.hud.show_death_screen({})
		check(not panel.visible, "formal HUD death route hides skill panel")
		check(not panel.assignment_popup.visible and not panel.assignment_scrim.visible, "death closes transient popup and scrim")
		check(panel._long_press_timer.is_stopped() and panel._pressed_skill_index == -1, "death retires long press intent")
		game.hud.close_death_screen()
		panel.open_for("技能导师")
		check(not panel.assignment_popup.visible and not panel.assignment_scrim.visible, "revival reentry does not resurrect configuration popup")
		check(panel.skill_button_assignments == bindings_before, "hide cleanup preserves persistent skill bindings")
		panel._open_assignment_popup_for(index)
		panel._close()
		panel.open_for("技能导师")
		check(not panel.assignment_popup.visible, "normal close also ends transient configuration session")
	quest.queue_free()
	_finish(game)

func _finish(game: Node) -> void:
	game.queue_free()
	var valid := proof.write_receipt("v109_quest_skill_session_ui_test", proof.records.size(), failures.size())
	print("V109_QUEST_SKILL_SESSION_UI_", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	get_tree().quit(0 if valid and failures.is_empty() else 1)
