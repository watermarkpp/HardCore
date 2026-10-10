extends Node

const Enemy := preload("res://scripts/enemy.gd")
const Budget := preload("res://scripts/monster_ai_package/decision_budget.gd")
const FrameBudget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const Fixture := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failures: Array[String] = []
var current_map_id := 1
var _zone_generation := 1

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _epoch() -> int:
	return Engine.get_process_frames()

func _clock() -> int:
	return Time.get_ticks_usec()

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	Enemy.configure_owner_decision_interval_for_test(300)
	Enemy.configure_owner_optional_budget_for_test(true)
	Enemy.configure_pursuit_process_budget_mode("budgeted")
	Budget.reset_pursuit_process_state()
	FrameBudget.configure_for_tests(0, _epoch, _clock)
	var player := Fixture.player(self, Vector2(14, 8))
	var actor := Fixture.enemy(self, 70, Vector2(8, 8), player)
	actor.set_physics_process(false)
	actor.visual.advance_struck_action(5.0)
	check(actor.monster_id == 70 and not actor.is_boss, "real registered ordinary monster 70")
	check(actor._hc_standard_melee() and not actor._source176_ordinary_melee(), "formal named contact delivery remains distinct from source geometry")
	check(str(actor.attack_delivery_rule.get("kind", "")) == "special_melee", "registered named delivery was not replaced by ordinary attack")
	actor._combat_action_time_s = 1.0
	actor._owner_decision_next_time_s = 0.0
	var damage_known_position: Vector2 = actor._hc_known_ground
	actor.set_physics_process(true)
	check(not actor._owner_decision_window_due(), "named optional owner refuses exhausted process allowance")
	actor._owner_optional_budget_end()
	check(not actor._hc_refresh_observation(), "named optional observation cannot spend necessary allowance")
	check(actor._hc_known_ground == damage_known_position and not actor._hc_observed, "denied observation preserves real damage-supplied position without inventing visibility")
	actor._pursuit_process_budget_end()
	actor.set_physics_process(false)
	var due: float = actor._owner_decision_next_time_s
	for tick: int in 3:
		actor.set_physics_process(true)
		actor._physics_process(1.0 / 60.0)
		actor.set_physics_process(false)
	check(is_equal_approx(actor._owner_decision_next_time_s, due), "multiple physics callbacks cannot consume an unserved owner deadline")
	check(not actor._movement_step_active, "zero allowance does not admit a new pursuit leg")
	check(int(Budget.pursuit_process_snapshot().get("open_turns", -1)) == 0, "denied owner leaves no lease")
	check(int(FrameBudget.snapshot().get("open_scopes", -1)) == 0, "denied owner leaves no frame scope")
	# Ready named attacks keep their source-locked delivery. Optional geometry
	# exhaustion cannot delay the real attack admission or its committed damage.
	player.global_position = Fixture.to_screen(Vector2(8.5, 8))
	actor._attack_timer = 0.0
	actor._pending_attack_time = -1.0
	actor._attack_action_active = false
	await get_tree().physics_frame
	var hp: int = player.current_hp
	# ID70 commits immediate magic damage through the player's real anti-magic
	# roll. Keep the original probabilities and HP assertions, but make this
	# hit-path regression reproducible instead of depending on randomize().
	player._rng.seed = 1
	actor.set_physics_process(true)
	actor._physics_process(1.0 / 60.0)
	actor.set_physics_process(false)
	check(actor._attack_action_active, "ready named contact starts despite exhausted optional allowance")
	print("NAMED_REAL_DAMAGE_RESOLUTION ", JSON.stringify(actor.last_magic_attack_resolution))
	check(player.current_hp < hp or actor._pending_attack_time >= 0.0, "accepted named delivery retains real damage authority")
	for tick: int in 30:
		actor._physics_process(1.0 / 60.0)
		actor.set_physics_process(false)
	check(player.current_hp < hp, "committed named attack actually settles HP while optional work is denied")
	Budget.cancel(actor.get_instance_id())
	Fixture.dispose(actor, player)
	# A positive owner quantum must consume one simulation-clock deadline,
	# rather than turn a named monster into a permanently denied statue.
	Budget.reset_pursuit_process_state()
	FrameBudget.configure_for_tests(1200, _epoch, _clock)
	player = Fixture.player(self, Vector2(14, 8))
	actor = Fixture.enemy(self, 70, Vector2(8, 8), player)
	actor.set_physics_process(false)
	actor.visual.advance_struck_action(5.0)
	actor._owner_decision_next_time_s = 0.0
	actor._combat_action_time_s = 1.0
	await get_tree().physics_frame
	actor.set_physics_process(true)
	check(actor._owner_decision_window_due(), "named owner is serviceable with available process allowance")
	check(actor._hc_refresh_observation(), "named owner completes formal observation within admitted quantum")
	actor._owner_decision_record_served()
	actor._owner_optional_budget_end()
	actor.set_physics_process(false)
	var next_due: float = actor._owner_decision_next_time_s
	check(is_equal_approx(next_due, 1.3), "served named owner advances exactly one accepted 300ms simulation deadline")
	actor._combat_action_time_s = 1.299
	await get_tree().physics_frame
	actor.set_physics_process(true)
	check(not actor._owner_decision_window_due(), "named actor holds the accepted result until its deadline")
	check(is_equal_approx(actor._owner_decision_next_time_s, next_due), "waiting cannot restart or accumulate owner debt")
	actor.set_physics_process(false)
	actor._combat_action_time_s = 1.3
	await get_tree().process_frame
	await get_tree().physics_frame
	actor.set_physics_process(true)
	check(actor._owner_decision_window_due(), "named actor can receive the next due owner quantum")
	actor._owner_optional_budget_end()
	actor.set_physics_process(false)
	check(int(Budget.pursuit_process_snapshot().get("open_turns", -1)) == 0, "positive owner closes all process leases")
	check(int(FrameBudget.snapshot().get("open_scopes", -1)) == 0, "positive owner closes all frame scopes")
	Budget.cancel(actor.get_instance_id())
	Fixture.dispose(actor, player)
	Budget.reset_pursuit_process_state()
	FrameBudget.reset_test_configuration()
	for message: String in failures:
		print("HC_TEST_FAIL ", message)
	var receipt_ok := proof.write_receipt("crowd_named_melee_optional_budget_20261010_test", proof.records.size(), failures.size())
	print("CROWD_NAMED_MELEE_OPTIONAL_BUDGET_%s checks=%d" % ["PASS" if failures.is_empty() else "FAIL", proof.records.size()])
	get_tree().quit(0 if failures.is_empty() and receipt_ok else 1)
