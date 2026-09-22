extends Node2D

const GU := preload("res://scripts/ground_unit_space.gd")
const IDLE_INTERVAL := 0.5

class ProbeEnemy extends EnemyActor:
	var wake_count := 0
	func _on_background_wakeup_timeout() -> void:
		wake_count += 1
		super._on_background_wakeup_timeout()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.position = Vector2(50000, 50000)
	var enemy := ProbeEnemy.new()
	enemy.setup(GameData.get_monster_by_id(18), player, false)
	enemy.set_meta("spawn_position", Vector2.ZERO)
	enemy.set_meta("safe_zone_context", {"valid": true, "zones": [], "revision": 1})
	add_child(enemy)
	enemy._enter_background_deep_sleep(false)
	assert(enemy._background_deep_sleeping)
	assert(is_equal_approx(enemy._background_wakeup_timer.wait_time, IDLE_INTERVAL),
		"a resting idle actor should schedule one local scan every 0.5 seconds")
	enemy.wake_count = 0
	await get_tree().create_timer(1.1).timeout
	assert(enemy.wake_count == 2, "idle wakeups must be 2 Hz, actual=%d" % enemy.wake_count)
	assert(enemy.target == null and not enemy.is_physics_processing())

	# A fresh complete interval is the worst phase for entering view. Observe
	# the actual Timer signal, target setter and physics wake, not just constants.
	enemy._on_background_wakeup_timeout()
	player.position = GU.ground_delta_gu_to_screen_delta_px(Vector2(5, 0))
	var entered_at := Time.get_ticks_msec()
	var deadline := entered_at + 650
	while enemy.target == null and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	var acquisition_ms := Time.get_ticks_msec() - entered_at
	assert(enemy.target == player and enemy.is_physics_processing(),
		"player entering view was not acquired on the next idle wake")
	assert(acquisition_ms <= 550, "idle player acquisition exceeded interval plus scheduling tolerance")

	# No full idle interval may be added to the existing damage wake path.
	player.position = GU.ground_delta_gu_to_screen_delta_px(Vector2(10, 0))
	enemy.target = null
	enemy._threat_table.clear()
	enemy._clear_autonomous_step_state()
	enemy.position = Vector2.ZERO
	enemy._enter_background_deep_sleep(false)
	assert(enemy._background_deep_sleeping)
	var hp_before := enemy.current_hp
	enemy.take_damage(1, player)
	assert(enemy.current_hp < hp_before)
	assert(not enemy._background_deep_sleeping and enemy.is_physics_processing(),
		"damage must wake immediately, without waiting for the idle timer")

	# Returning to spawn keeps the pre-existing maintenance cadence. The
	# slower interval applies only when truly resting, not between return steps.
	enemy.target = null
	enemy._threat_table.clear()
	enemy._hc_damage_dirty = false
	enemy._clear_autonomous_step_state()
	enemy.position = GU.ground_delta_gu_to_screen_delta_px(Vector2(3, 0))
	enemy._enter_background_deep_sleep(false)
	assert(is_equal_approx(enemy._background_wakeup_timer.wait_time, EnemyActor.BACKGROUND_AI_INTERVAL_SECONDS))
	assert(is_equal_approx(EnemyActor.TARGET_GRID_REFRESH_SECONDS, 0.25),
		"new pets must retain the existing shared target discovery window")
	enemy.free()
	player.free()
	print("MONSTER_IDLE_SCAN_CADENCE_PASS idle_hz=2 acquisition_ms=%d damage_wake=immediate" % acquisition_ms)
	get_tree().quit(0)
