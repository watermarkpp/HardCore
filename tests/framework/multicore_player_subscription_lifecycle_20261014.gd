extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var errors: Array[String] = []
var notifications := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		errors.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	var model: Object = player.domain_model
	var listener := Callable(model, "_apply_profile_stats")
	check(PlayerState.profile_changed.is_connected(listener), "live player model owns the original synchronous profile subscription")
	remove_child(player)
	check(PlayerState.profile_changed.is_connected(listener), "leaving the tree without destruction preserves the original profile subscription")
	add_child(player)
	model.death_requested.connect(func() -> void: notifications += 1)
	model.take_damage(999999, false)
	player.queue_free()
	await get_tree().process_frame
	check(not PlayerState.profile_changed.is_connected(listener), "final adapter destruction retires the subscription even while the model has an external reference")
	# Do not invoke a known stale callback merely to produce a second error;
	# the connection itself is the failed lifecycle postcondition above.
	if not PlayerState.profile_changed.is_connected(listener):
		PlayerState.profile_changed.emit()
	await get_tree().create_timer(1.0).timeout
	check(notifications == 0, "the original death timer cannot notify after final actor destruction")
	proof.write_receipt("multicore_player_subscription_lifecycle_20261014", proof.records.size(), errors.size())
	if errors.is_empty():
		print("MULTICORE_PLAYER_SUBSCRIPTION_LIFECYCLE_20261014_PASS")
	else:
		for message: String in errors:
			printerr(message)
	get_tree().quit(0 if errors.is_empty() else 1)
