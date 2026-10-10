extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")
var proof := Proof.new()
var failures: Array[String] = []
var checks := 0
var game: Node

func check(ok: bool, label: String) -> void:
	proof.record(ok, label)
	checks += 1
	if not ok:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.learned_skills = {"野蛮冲撞": 3}
	PlayerState.recalculate_stats(false)
	game = Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 30000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "actual Root reaches READY")
	if not game.gameplay_input_is_enabled():
		_finish()
		return
	# Control the existing input owner calls; do not simulate physical keyboard
	# hardware or replay full Root work while making this narrow handoff.
	game.set_process(false)
	Input.action_release("attack")
	game._reset_attack_action_lifecycle(&"test_neutral")
	game.hud.skill_button_assignment_requested.emit({
		"contract_id": "ui.skill.button_assignment.v3",
		"slot_group": "attack", "slot_index": 0,
		"slot_id": "hud.attack.primary", "skill_id": "warrior.wild_rush",
	})
	check(not PlayerState.skill_name_for_slot("attack", 0).is_empty(), "formal assignment binds attack skill")
	Input.action_press("attack")
	var before: Dictionary = game._poll_attack_action_lifecycle(true)
	check(bool(before.get("started", false)) and bool(before.get("active", false)), "fresh attack down owns keyboard action before rebind")
	var epoch_before: int = game._attack_action_lifecycle_epoch
	game.hud._ensure_skill_panel()
	var panel: Node = game.hud.skill_panel
	check(is_instance_valid(panel), "actual HUD creates skill panel")
	var clear_button: Button = panel.get_node("AssignmentPanel/ClearAttackSkillSlot")
	clear_button.pressed.emit()
	check(PlayerState.skill_name_for_slot("attack", 0).is_empty(), "real panel restore button clears saved attack binding")
	check(game._attack_action_lifecycle_epoch == epoch_before + 1, "successful rebinding retires keyboard lifecycle exactly once")
	check(not game._attack_action_press_owned, "old held key loses action ownership at rebind")
	var after: Dictionary = game._poll_attack_action_lifecycle(true)
	check(not bool(after.get("started", true)) and not bool(after.get("active", true)), "held old key cannot start ordinary attack after restore")
	check(Input.is_action_pressed("attack"), "boundary does not manufacture a physical key release")
	for index in range(3):
		var held: Dictionary = game._poll_attack_action_lifecycle(true)
		check(not bool(held.get("active", true)), "continued old hold stays retired %d" % index)
	Input.action_release("attack")
	game._poll_attack_action_lifecycle(true)
	Input.action_press("attack")
	var fresh: Dictionary = game._poll_attack_action_lifecycle(true)
	check(bool(fresh.get("started", false)) and bool(fresh.get("active", false)), "new physical down acquires ordinary attack ownership")
	var before_invalid: int = game._attack_action_lifecycle_epoch
	game.hud.skill_button_assignment_requested.emit({
		"contract_id": "invalid", "slot_group": "attack", "slot_index": 0,
		"slot_id": "hud.attack.primary", "clear": true,
	})
	check(game._attack_action_lifecycle_epoch == before_invalid, "rejected assignment leaves current input ownership intact")
	check(bool(game._poll_attack_action_lifecycle(true).get("active", false)), "valid new hold remains active after rejected configuration")
	_finish()

func _finish() -> void:
	Input.action_release("attack")
	if is_instance_valid(game):
		game.queue_free()
	var valid := proof.write_receipt("v109_skill_rebind_keyboard_owner_test", checks, failures.size())
	print("V109_SKILL_REBIND_KEYBOARD_OWNER_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
	get_tree().quit(0 if valid and failures.is_empty() else 1)
