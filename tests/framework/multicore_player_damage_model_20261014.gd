extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const MODEL_PATH := "res://scripts/gameplay/actors/player_actor_model.gd"
var proof := Proof.new()
var errors: Array[String] = []
var death_notifications := 0
var revived_and_rekilled := false
var death_commit_visible := false
var rejected_reentry := false
var healing_reentry_done := false

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		errors.append(label)

func _ready() -> void:
	_run.call_deferred()

func _on_lethal_stats(hp: int, _maximum: int, model: Object) -> void:
	if hp != 0 or revived_and_rekilled:
		return
	death_commit_visible = model._dead
	var committed_life: int = model.current_life()
	model.take_damage(7)
	rejected_reentry = model.current_life() == committed_life
	revived_and_rekilled = true
	model.complete_death_revival()
	model.take_damage(999999)

func _on_healed_stats(hp: int, _maximum: int, model: Object) -> void:
	if hp == 30 and not healing_reentry_done:
		healing_reentry_done = true
		model.take_damage(7, false)

func _run() -> void:
	check(FileAccess.file_exists(MODEL_PATH), "player damage recovery buffs stats and death share a domain model")
	if not FileAccess.file_exists(MODEL_PATH):
		_finish()
		return
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.gold = 1000
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	var model: Object = player.get("domain_model")
	check(model != null and not model is Node, "production player adapter binds a non-Node domain owner")
	if model == null:
		player.queue_free()
		_finish()
		return
	check(player.combat_actions == model.combat_actions, "damage and existing action clocks reference the same submodel")
	player.defense_min = 0
	player.defense_max = 0
	player.max_hp = 100
	player.current_hp = 100
	player.max_mp = 40
	model.apply_magic_shield(10.0, 0.8)
	model.take_damage(100, false)
	check(model.current_hp == 40 and player.current_hp == 40, "capacity limited shield commits one shared HP value")
	check(model.shield_capacity == 0.0 and model.shield_time == 0.0 and model.damage_reduction == 0.0, "exhausted shield clears original active fields")
	player.current_hp = 20
	model.stats_changed.connect(_on_healed_stats.bind(model))
	var healed: int = model.restore_health(10)
	check(healed == 10 and model.current_hp == 23 and healing_reentry_done, "healing returns its frozen write despite synchronous damage reentry")
	model.stats_changed.disconnect(_on_healed_stats.bind(model))
	player.stats_changed.connect(_on_lethal_stats.bind(model))
	player.death_requested.connect(func() -> void: death_notifications += 1)
	var initial_life: int = model.current_life()
	model.take_damage(999999)
	check(death_commit_visible and rejected_reentry, "formal death commits before signals and rejects a nested old-life hit")
	check(revived_and_rekilled and model._dead and model.current_hp == 0, "synchronous revival and second lethal hit remain on one authority")
	check(model.current_life() == initial_life + 2 and player.combat_epoch == model.current_life(), "each committed death advances the same combat life exactly once")
	check(model._death_lifecycle_generation == 3, "revival keeps the separate original death-notification cancellation token")
	check(PlayerState.gold == 902, "both committed deaths settle their economic loss exactly once despite nested revival")
	check(model.restore_health(100) == 0 and model.current_hp == 0, "ordinary healing cannot revive a formally dead model")
	model.apply_poison(5, 4.0)
	model.apply_control(3.0)
	check(model.poison_time == 0.0 and model.control_time == 0.0, "dead model rejects new poison and control")
	await get_tree().create_timer(1.1).timeout
	check(death_notifications == 1, "only the second death owns the surviving scheduled notification")
	player.queue_free()
	await get_tree().process_frame
	_finish()

func _finish() -> void:
	proof.write_receipt("multicore_player_damage_model_20261014", proof.records.size(), errors.size())
	if errors.is_empty():
		print("MULTICORE_PLAYER_DAMAGE_MODEL_20261014_PASS")
	else:
		for message: String in errors:
			printerr(message)
	get_tree().quit(0 if errors.is_empty() else 1)
