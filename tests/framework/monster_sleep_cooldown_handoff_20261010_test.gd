extends Node

const Fixture := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failures: Array[String] = []
var checks := 0
var current_map_id := 1
var _zone_generation := 1

func check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _cold(player: PlayerCharacter, regen_phase: float = 0.0) -> EnemyActor:
	var actor := EnemyActor.new()
	actor.setup(GameData.get_monster_by_id(64), player, false)
	actor.global_position = Fixture.to_screen(Vector2(8, 8))
	actor.set_meta("spawn_position", actor.global_position)
	actor.set_meta("safe_zones", [])
	actor.set_meta("zone_generation", 1)
	actor.configure_runtime_map_projection(1, Callable(Fixture.GU, "ground_delta_gu_to_screen_delta_px"), Callable(Fixture.GU, "screen_delta_px_to_ground_delta_gu"))
	actor.configure_terrain_navigation_context(Fixture.open_context())
	add_child(actor)
	actor.set_physics_process(false)
	actor.target = null
	actor._threat_table.clear()
	actor._hc_damage_dirty = false
	actor._clear_passive_wake()
	actor._attack_timer = 0.05
	actor._natural_regen.advance(regen_phase, actor.current_hp, actor.max_hp)
	check(actor._can_use_background_ai(), "formal cold actor meets sleep gates")
	actor._enter_background_deep_sleep(false)
	actor.set_physics_process(false)
	check(actor._background_deep_sleeping, "real background owner entered sleep")
	actor._physics_process(0.1)
	actor.set_physics_process(false)
	check(actor._background_deep_sleeping and is_equal_approx(actor._attack_timer, 0.05), "sleep advances owner clock while maintenance has not consumed cooldown")
	return actor

func _run() -> void:
	PlayerState.test_mode = true
	var player := Fixture.player(self, Vector2(9, 8))
	# The formal halo receiver assigns the target and executes the real wake
	# handoff before the maintenance Timer, without adding a struck animation.
	var actor := _cold(player)
	check(actor.request_passive_player_wakeup(player, 1, 1), "formal halo accepts legal player")
	check(not actor._background_deep_sleeping, "halo wakes the existing owner")
	check(is_equal_approx(actor._attack_timer, -0.05), "halo handoff preserves elapsed existing cooldown")
	var after_wake := actor._attack_timer
	actor._leave_background_deep_sleep()
	actor._on_background_wakeup_timeout()
	check(is_equal_approx(actor._attack_timer, after_wake), "duplicate wake and stale timeout cannot consume twice")
	actor.free()
	# Normal maintenance consumes the same interval once. The later foreground
	# handoff must not deduct the already-serviced Timer slice a second time.
	actor = _cold(player)
	actor._on_background_wakeup_timeout()
	check(is_equal_approx(actor._attack_timer, -0.05), "normal maintenance consumes elapsed cooldown once")
	actor._leave_background_deep_sleep()
	check(is_equal_approx(actor._attack_timer, -0.05), "Timer-to-foreground handoff does not double deduct")
	actor.free()
	# A pending activation makes the Timer's foreground gate exit early. That
	# early exit still owes the old cooldown slice to the one existing owner.
	actor = _cold(player)
	actor._passive_wake_pending = true
	actor._on_background_wakeup_timeout()
	check(not actor._background_deep_sleeping and is_equal_approx(actor._attack_timer, -0.05), "early Timer foreground handoff preserves elapsed cooldown")
	actor.free()
	# The same sleep interval also belongs to the continuously running regen
	# cadence. A full-HP tick must be consumed before newly arriving damage.
	actor = _cold(player, 5.95)
	var full_hp := actor.current_hp
	actor.take_damage(20, player)
	actor.set_physics_process(false)
	var regen_state: Dictionary = actor._natural_regen.state_snapshot()
	check(int(regen_state.total_ticks) == 1 and is_equal_approx(float(regen_state.elapsed_seconds), 0.05), "damage wake preserves the old regen phase")
	check(actor.current_hp == full_hp - 20, "old full-HP regen cannot offset the new waking damage")
	actor._leave_background_deep_sleep()
	actor._on_background_wakeup_timeout()
	check(actor._natural_regen.state_snapshot() == regen_state, "duplicate wake cannot consume regen twice")
	actor.free()
	actor = _cold(player, 5.95)
	check(actor.request_passive_player_wakeup(player, 1, 1), "regen handoff uses the formal halo receiver")
	regen_state = actor._natural_regen.state_snapshot()
	check(int(regen_state.total_ticks) == 1 and is_equal_approx(float(regen_state.elapsed_seconds), 0.05), "halo wake preserves continuous regen phase")
	actor.free()
	actor = _cold(player, 5.95)
	actor._on_background_wakeup_timeout()
	regen_state = actor._natural_regen.state_snapshot()
	actor._leave_background_deep_sleep()
	check(int(regen_state.total_ticks) == 1 and actor._natural_regen.state_snapshot() == regen_state, "maintenance then foreground does not consume regen twice")
	actor.free()
	actor = _cold(player, 5.95)
	actor.current_hp = 0
	actor._death_pending = true
	actor._leave_background_deep_sleep()
	check(actor.current_hp == 0, "death handoff never resurrects the actor through regen")
	actor.free()
	player.free()
	for message: String in failures:
		print("HC_TEST_FAIL ", message)
	print("MONSTER_SLEEP_COOLDOWN_HANDOFF_%s checks=%d" % ["PASS" if failures.is_empty() else "FAIL", checks])
	if not proof.write_receipt("monster_sleep_cooldown_handoff_20261010_test", checks, failures.size()):
		get_tree().quit(1)
		return
	get_tree().quit(0 if failures.is_empty() else 1)
