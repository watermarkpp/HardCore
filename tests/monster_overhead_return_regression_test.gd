extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	player.global_position = Vector2(1000, 0)
	add_child(player)
	player.set_physics_process(false)

	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(31), player, false)
	enemy.global_position = Vector2(160, 0)
	enemy.set_meta("spawn_position", Vector2.ZERO)
	enemy.set_meta("safe_zones", [])
	add_child(enemy)
	enemy.set_physics_process(false)
	await get_tree().process_frame

	assert(enemy.visual.uses_final_art(), "monsterId=31 final art fixture did not load")
	_assert_name_above_health_bar(enemy)
	enemy.facing = Vector2.RIGHT
	enemy.movement_facing = Vector2.RIGHT
	enemy.velocity = Vector2.ZERO
	enemy.visual._process(0.01)
	_assert_name_above_health_bar(enemy)

	enemy.target = null
	var return_direction := enemy.global_position.direction_to(enemy.get_meta("spawn_position"))
	enemy._return_to_spawn()
	assert(enemy.facing.dot(return_direction) > 0.99, "return combat facing points away from spawn")
	assert(enemy.movement_facing.dot(return_direction) > 0.99, "return walk animation kept stale pursuit facing")
	enemy.visual._process(0.05)
	assert(enemy.visual.current_state == "walk", "return movement did not select walk animation")
	assert(enemy.visual.current_direction == enemy.visual._direction_row(return_direction), "return walk row faces away from spawn")

	# A delayed melee hit may mature before _physics_process reaches its target
	# safe-zone branch. Both the pending resolver and final hit authority must
	# reject the player using the enemy's published safe-zone snapshot.
	player.global_position = enemy.global_position + Vector2(20, 0)
	enemy.set_meta("safe_zones", [{"shape": "circle", "center": player.global_position, "radius": 96.0}])
	var hp_before := player.current_hp
	enemy._pending_attack_target = player
	enemy._pending_attack_damage = 25
	enemy._pending_attack_time = 0.01
	enemy._update_pending_attack(0.02)
	assert(player.current_hp == hp_before, "delayed melee hit damaged player after entering Bich safe zone")
	enemy._deal_melee_hit(player, 25)
	assert(player.current_hp == hp_before, "final melee authority ignored Bich safe zone")

	print("MONSTER_OVERHEAD_RETURN_REGRESSION_PASS stable monsterId=31 overhead anchor, return facing, and safe-zone hit guard")
	get_tree().quit(0)


func _assert_name_above_health_bar(enemy: EnemyActor) -> void:
	assert(is_equal_approx(enemy.name_label.position.y, enemy.name_label_anchor_y()), "monster name did not follow authored frame-top anchor")
	var label_bottom := enemy.name_label.position.y + enemy.name_label.size.y
	assert(is_equal_approx(label_bottom + EnemyActor.NAME_LABEL_HEALTH_BAR_GAP, enemy.health_bar_anchor_y()), "monster name overlaps or detaches from health bar")
