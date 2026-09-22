extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("法师")
	PlayerState.learned_skills = {"火球术": 0}
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.current_mp = 100
	player.max_hp = 500
	player.current_hp = 500
	var releases: Array[String] = []
	player.skill_requested.connect(func(skill: String, _origin: Vector2, _direction: Vector2, _power: int) -> void: releases.append(skill))
	assert(player.request_skill("火球术"))
	player.take_damage(15, true, {}, true)
	assert(player.struck_reaction_snapshot().queued)
	# Physics can catch up before the process-frame SceneTreeTimer delivers
	# the accepted cast's release. Its transaction still owns that boundary.
	player._physics_process(1.0)
	assert(not player.combat_action_snapshot().committed)
	assert(player.struck_reaction_snapshot().queued, "struck consumed before the pending cast actually released")
	assert(player.visual._action_name == "cast", "struck replaced the still-pending cast visual")
	await get_tree().create_timer(1.0).timeout
	assert(releases.size() == 1 and player.combat_action_snapshot().committed)
	player._physics_process(0.001)
	assert(not player.struck_reaction_snapshot().queued)
	assert(player.struck_reaction_snapshot().reaction_lock_remaining > 0.0)
	assert(player.visual._action_name == "hit")
	player._physics_process(1.0)
	assert(player.struck_reaction_snapshot().reaction_lock_remaining == 0.0 and releases.size() == 1)
	player.queue_free()
	await get_tree().process_frame
	print("PLAYER_STRUCK_RELEASE_ORDER_PASS")
	get_tree().quit()
