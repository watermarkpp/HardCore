extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Fixture := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")

class SleepEnemy extends EnemyActor:
	func _ready() -> void:
		# This fixture exercises the production physics owner without client assets.
		pass

var proof := Proof.new()
var failures: Array[String] = []
var checks := 0
var actor: EnemyActor
var player: PlayerCharacter

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	# The target is valid before sleep and remains the same object throughout this
	# test. Only its position changes across the background/foreground threshold.
	player = Fixture.player(self, Vector2(100.0, 0.0))
	actor = SleepEnemy.new()
	actor.setup(GameData.get_monster_by_id(64), player, false)
	actor.global_position = Fixture.to_screen(Vector2.ZERO)
	actor.set_meta("spawn_position", actor.global_position)
	actor.set_meta("safe_zones", [])
	actor.configure_runtime_map_projection(1, Callable(Fixture.GU, "ground_delta_gu_to_screen_delta_px"),
		Callable(Fixture.GU, "screen_delta_px_to_ground_delta_gu"))
	actor.configure_terrain_navigation_context(Fixture.open_context())
	add_child(actor)
	actor._background_wakeup_timer = Timer.new()
	actor._background_wakeup_timer.one_shot = true
	actor._background_wakeup_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	actor._background_wakeup_timer.timeout.connect(actor._on_background_wakeup_timeout)
	actor.add_child(actor._background_wakeup_timer)
	await get_tree().physics_frame
	actor.set_physics_process(false)
	# Keep the formal target assigned by setup. Do not invoke the target setter as
	# a handoff: the production bug is a position-only foreground transition.
	actor.target = player
	check(actor.target == player and actor.primary_target == player,
		"existing valid target is retained before background sleep")
	check(actor._can_use_background_ai(),
		"distant valid target permits the real background owner")
	actor._combat_action_time_s = 0.0
	actor._attack_timer = 1.0
	actor.current_hp = actor.max_hp - 100
	actor._natural_regen.advance(5.9, actor.current_hp, actor.max_hp)
	actor._enter_background_deep_sleep(true)
	check(actor._background_deep_sleeping,
		"valid-target actor enters the real background sleep owner")
	check(is_equal_approx(actor._background_last_wakeup_game_s, 0.0),
		"sleep anchor starts at the combat clock")

	# Cross the activation threshold without changing target identity. This is
	# the missing production handoff: physics becomes foreground while the stale
	# maintenance owner still has the old anchor and timer.
	player.global_position = Fixture.to_screen(Vector2(2.0, 0.0))
	check(not actor._can_use_background_ai(),
		"position-only target movement requests foreground service")
	actor._physics_process(0.10)
	check(actor.target == player,
		"physics handoff keeps the existing target identity")
	check(not actor._background_deep_sleeping,
		"physics handoff retires the stale sleep owner before foreground service")
	check(is_equal_approx(actor._attack_timer, 0.90),
		"foreground physics consumes the elapsed cooldown exactly once")
	check(is_equal_approx(actor._background_last_wakeup_game_s, 0.10),
		"handoff anchor is advanced to the post-physics combat clock")
	var expected_heal := floori(float(actor.max_hp) / 75.0) + 1
	check(actor.current_hp == actor.max_hp - 100 + expected_heal,
		"foreground physics advances natural regen exactly once")

	# The old timer may still deliver a late callback. Once the sleep owner is
	# retired it must be a no-op, rather than consuming the same interval again.
	var timer_anchor := actor._background_last_wakeup_game_s
	var timer_attack := actor._attack_timer
	var timer_hp := actor.current_hp
	actor._on_background_wakeup_timeout()
	check(is_equal_approx(actor._background_last_wakeup_game_s, timer_anchor)
		and is_equal_approx(actor._attack_timer, timer_attack)
		and actor.current_hp == timer_hp,
		"late maintenance callback cannot double-consume foreground time")

	_finish()

func _finish() -> void:
	if is_instance_valid(actor):
		actor.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	var valid := proof.write_receipt("v109_sleep_foreground_reentry_test", checks, failures.size())
	if not valid:
		failures.append("receipt failed")
	print("V109_SLEEP_FOREGROUND_REENTRY_", "PASS" if failures.is_empty() else "FAIL",
		" checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
