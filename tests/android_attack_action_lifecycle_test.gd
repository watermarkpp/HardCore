extends Node

const GameRoot := preload("res://scripts/game_root.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := GameRoot.new()
	game._register_input_actions()
	Input.action_release("attack")
	await get_tree().process_frame

	# A pressed action inherited from Android/app entry has no DOWN owned by this
	# GameRoot lifecycle and must never start or sustain an attack.
	Input.action_press("attack")
	game._reset_attack_action_lifecycle(&"test_fresh_entry")
	var stale_entry: Dictionary = game._poll_attack_action_lifecycle(true)
	assert(not stale_entry.started and not stale_entry.active)
	assert(_event_count(game, "pressed_without_fresh_down_ignored") == 1)
	game._poll_attack_action_lifecycle(true)
	assert(_event_count(game, "pressed_without_fresh_down_ignored") == 1,
		"ignored held input diagnostics must remain bounded per lifecycle")

	Input.action_release("attack")
	var neutral: Dictionary = game._poll_attack_action_lifecycle(true)
	assert(not neutral.active)
	Input.action_press("attack")
	var fresh_down: Dictionary = game._poll_attack_action_lifecycle(true)
	assert(fresh_down.started and fresh_down.active)
	var continued_hold: Dictionary = game._poll_attack_action_lifecycle(true)
	assert(not continued_hold.started and continued_hold.active,
		"a legitimate long hold must remain active without duplicate DOWN")
	Input.action_release("attack")
	var released: Dictionary = game._poll_attack_action_lifecycle(true)
	assert(released.ended and not released.active)

	# Loading/focus boundaries revoke only the raw action owner. Keeping the
	# physical action pressed across either boundary cannot create a new owner.
	Input.action_press("attack")
	assert(game._poll_attack_action_lifecycle(true).started)
	game._acquire_gameplay_input_lock(game.INPUT_LOCK_MAP_TRANSITION)
	assert(not game._poll_attack_action_lifecycle(false).active)
	assert(not game._poll_attack_action_lifecycle(true).active)
	Input.action_release("attack")
	game._poll_attack_action_lifecycle(true)
	Input.action_press("attack")
	assert(game._poll_attack_action_lifecycle(true).started)
	game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(not game._poll_attack_action_lifecycle(true).active)

	var snapshot: Dictionary = game.attack_action_lifecycle_snapshot()
	assert(snapshot.contract_id == game.ATTACK_ACTION_LIFECYCLE_CONTRACT_ID)
	assert((snapshot.events as Array).size() <= game.ATTACK_ACTION_DIAGNOSTIC_LIMIT)
	Input.action_release("attack")
	game.free()
	print("ANDROID_ATTACK_ACTION_LIFECYCLE_TEST_PASS")
	get_tree().quit(0)


func _event_count(game: Node, kind: String) -> int:
	var count := 0
	for raw_event: Variant in game.attack_action_lifecycle_snapshot().events:
		if raw_event is Dictionary and str(raw_event.get("kind", "")) == kind:
			count += 1
	return count
