extends Node

var playback_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for _frame in range(4):
		await get_tree().process_frame
	assert(not game._map_transition_in_progress)
	var effect: Node2D = game._player_level_up_effect
	assert(effect != null and effect.get_parent() == game.player)
	assert(effect.z_index == 0 and not bool(effect.get_meta("preview_only")))
	effect.playback_started.connect(func() -> void: playback_count += 1)
	PlayerState.add_experience(10)
	assert(PlayerState.level == 3, "one generic reward should cross two reduced thresholds")
	assert(playback_count == 1, "one multi-level reward must play exactly once")
	assert(effect.position == game.player.approved_ground_footpoint_local_px())
	var old_position := effect.global_position
	game.player.position += Vector2(9.0, 4.0)
	assert(effect.global_position.is_equal_approx(old_position + Vector2(9.0, 4.0)))
	PlayerState.add_experience(0)
	PlayerState.add_experience(1)
	assert(playback_count == 1, "zero/non-level rewards must not replay")
	var before_level: int = PlayerState.level
	var result: Dictionary = PlayerState.record_kills_and_experience_batch([
		{"monster_name": "稻草人", "experience": 200},
	], true)
	assert(bool(result.get("success", false)))
	assert(PlayerState.level > before_level + 1)
	assert(playback_count == 2, "one kill settlement crossing levels must play once")
	game.queue_free()
	await get_tree().process_frame
	assert(not PlayerState.levels_gained.has_connections(), "world exit must disconnect its effect")
	print("PLAYER_LEVEL_UP_EFFECT_RUNTIME_PASS")
	get_tree().quit(0)
