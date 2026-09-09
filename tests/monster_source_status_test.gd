extends Node

const PoisonState := preload("res://scripts/monster_source_poison_state.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var clock := PoisonState.new()
	assert(not clock.apply(2, 30.0, 0.0))
	assert(not clock.apply(2, NAN, 2.5))
	assert(clock.apply(2, 30.0, 2.5))
	assert(clock.advance(2.49) == 0)
	assert(clock.advance(0.01) == 1)
	assert(clock.advance(100.0) == 11 and clock.remaining_seconds == 0.0)
	assert(clock.advance(100.0) == 0)

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	player.max_hp = 100
	player.current_hp = 100
	player.defense_min = 100
	player.defense_max = 100
	player.shield_time = 10.0
	player.shield_capacity = 100.0
	player.damage_reduction = 0.8
	player._struck_lock_remaining = 0.0
	assert(player.apply_monster_poison(2, 30.0, 2.5))
	player._update_monster_source_poison(2.49)
	assert(player.current_hp == 100)
	player._update_monster_source_poison(0.01)
	assert(player.current_hp == 98, "source poison bypasses AC and spell bubble")
	assert(player.shield_capacity == 100.0 and player._struck_lock_remaining == 0.0)
	assert(player.begin_combat_transition("poison-test"))
	var remaining: float = player._monster_source_poison.remaining_seconds
	player._update_monster_source_poison(10.0)
	assert(player.current_hp == 98 and player._monster_source_poison.remaining_seconds == remaining)
	assert(not player.apply_monster_poison(2, 30.0, 2.5))
	assert(player.finish_combat_transition("poison-test"))
	player._update_monster_source_poison(2.5)
	assert(player.current_hp == 96)
	PlayerState.computed_special_effects["magic_shield"] = {}
	player.current_mp = 10
	player._update_monster_source_poison(2.5)
	assert(player.current_hp == 96 and player.current_mp == 7, "source poison retains MP shield")
	PlayerState.computed_special_effects.erase("magic_shield")
	assert(player.poison_time == 0.0, "new source status must not rewrite legacy poison")

	var summon := SummonActor.new()
	summon.setup(player, "骷髅", 1, 0, "taoist.summon_skeleton", 19, 1)
	add_child(summon)
	await get_tree().process_frame
	summon.set_physics_process(false)
	summon.current_hp = 100
	summon.ac_min = 100
	summon.ac_max = 100
	assert(summon.apply_monster_poison(2, 30.0, 2.5))
	summon._update_monster_source_poison(2.49)
	assert(summon.current_hp == 100)
	summon._update_monster_source_poison(0.01)
	assert(summon.current_hp == 98)
	assert(player.begin_combat_transition("pet-poison-test"))
	summon._update_monster_source_poison(20.0)
	assert(summon.current_hp == 98)
	assert(player.finish_combat_transition("pet-poison-test"))
	var pending_enemy := EnemyActor.new()
	summon._pending_attack_target = pending_enemy
	summon._pending_attack_release_remaining = 0.5
	summon.velocity = Vector2(40.0, 10.0)
	summon.apply_control(5.0)
	assert(summon._monster_control_remaining == 5.0 and summon._pending_attack_target == null)
	assert(summon._pending_attack_release_remaining == 0.0)
	pending_enemy.free()
	summon._physics_process(1.0)
	assert(summon._monster_control_remaining == 4.0 and summon.velocity == Vector2.ZERO)
	summon.current_hp = 1
	summon._update_monster_source_poison(2.5)
	assert(summon.current_hp == 0 and summon.state == SummonActor.SummonState.DEAD)
	summon._update_monster_source_poison(30.0)
	assert(summon._monster_source_poison.remaining_seconds == 0.0)
	player.current_hp = 1
	player._update_monster_source_poison(2.5)
	assert(player._dead and player.current_hp == 0)
	assert(player._monster_source_poison.remaining_seconds == 0.0)
	summon.queue_free()
	player.queue_free()
	await get_tree().process_frame
	print("MONSTER_SOURCE_STATUS_PASS: 2.5s poison clock, actual player/pet HP, WORLD-transition pause, no AC/bubble/struck, death, pet control")
	get_tree().quit(0)
