extends Node

const Enemy := preload("res://scripts/enemy.gd")
const Budget := preload("res://scripts/monster_ai_package/decision_budget.gd")
const FrameBudget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const Fixture := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Spatial := preload("res://scripts/runtime_combat_spatial_index.gd")

var failures: Array[String] = []
var evidence: Dictionary = {}
var quantum_clock_usec := 0

class QuantumOwner extends Node:
	func _hc_pursuit_budget_scope() -> Array:
		return ["quantum_accounting", get_instance_id()]
	func _hc_pursuit_budget_kind_runnable(_kind: StringName) -> bool:
		return true

func _quantum_clock() -> int:
	return quantum_clock_usec

func _epoch() -> int:
	return Engine.get_process_frames()

func _clock() -> int:
	return Time.get_ticks_usec()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _ready() -> void:
	await get_tree().process_frame
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	check(GameData.is_loaded(), "formal data ready")
	check(Enemy._owner_decision_interval_ms == 300, "production owner interval defaults to the accepted 300ms")
	check(Enemy._owner_optional_budget_enabled, "production optional owner budget is enabled")
	check(Enemy._ordinary_contact_instant_settle_enabled, "production ready contact attack settles immediately")
	check(Enemy._ordinary_attack_visual_move_override_enabled, "production visual override preserves timely pursuit")
	check(int(ProjectSettings.get_setting("hardcore/performance/frame_optional_budget_usec", -1)) == 1200, "production frame budget uses the actual consumer setting")
	Enemy.configure_pursuit_process_budget_mode("immediate")
	Enemy.configure_owner_decision_interval_for_test(300)
	Enemy.configure_attack_visual_policy_for_test(true, true)
	Enemy.configure_owner_optional_budget_for_test(true)
	Enemy.reset_pursuit_process_budget_diagnostics()
	await test_denial_and_urgent_attack()
	await test_initial_acquisition()
	await test_idle_selection_cadence()
	await test_fifo_callback_order()
	await test_simultaneous_real_owners()
	await test_scope_suspend_resume()
	Enemy.configure_owner_optional_budget_for_test(false)
	Enemy.configure_owner_decision_interval_for_test(0)
	Enemy.configure_attack_visual_policy_for_test(false, false)
	Budget.reset_pursuit_process_state()
	FrameBudget.reset_test_configuration()
	evidence["failures"] = failures
	evidence["status"] = "PASS" if failures.is_empty() else "FAIL"
	var output := FileAccess.open("res://outputs/test_logs/crowd_owner_optional_budget_contract_20261009.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(evidence, "\t"))
	if failures.is_empty():
		print("HC_OWNER_OPTIONAL_BUDGET_CONTRACT_20261009_PASS")
	else:
		for message: String in failures:
			print("HC_TEST_FAIL ", message)
	get_tree().quit(0 if failures.is_empty() else 1)

func test_denial_and_urgent_attack() -> void:
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	FrameBudget.configure_for_tests(0, _epoch, _clock)
	var player := Fixture.player(self, Vector2(14.0, 8.0))
	var actor := Fixture.enemy(self, 64, Vector2(8.0, 8.0), player)
	actor.set_physics_process(false)
	actor.visual.advance_struck_action(5.0)
	actor._combat_action_time_s = 0.0
	await get_tree().physics_frame
	await get_tree().process_frame
	var deadline: float = actor._owner_decision_next_time_s
	actor.set_physics_process(true)
	actor._physics_process(1.0 / 60.0)
	actor.set_physics_process(false)
	check(is_equal_approx(actor._owner_decision_next_time_s, deadline), "denied optional planning keeps its original due deadline")
	var denied := Budget.pursuit_process_snapshot()
	check(int(denied.get("budget_denied", 0)) > 0, "zero budget refuses the real owner lane")
	check(int(denied.get("open_turns", -1)) == 0, "denied callback leaves no open owner lease")
	check(int(FrameBudget.snapshot().get("open_scopes", -1)) == 0, "denied callback leaves no frame scope")
	evidence["denied"] = denied
	player.global_position = Fixture.to_screen(Vector2(8.5, 8.0))
	actor._attack_timer = 0.0
	var hp: int = player.current_hp
	await get_tree().physics_frame
	await get_tree().process_frame
	actor.set_physics_process(true)
	actor._physics_process(1.0 / 60.0)
	actor.set_physics_process(false)
	check(player.current_hp < hp, "legal contact attack settles despite exhausted optional budget")
	check(actor._attack_action_active, "legal attack still owns its committed action")
	check(int(Budget.pursuit_process_snapshot().get("open_turns", -1)) == 0, "urgent attack callback closes optional scope")
	Budget.cancel(actor.get_instance_id())
	Fixture.dispose(actor, player)

func test_initial_acquisition() -> void:
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	FrameBudget.configure_for_tests(1200, _epoch, _clock)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for _frame: int in 1200:
		await get_tree().process_frame
		if not game._world_bootstrap_in_progress and not game._map_transition_in_progress:
			break
	check(game.gameplay_input_is_enabled(), "formal world bootstrap completes for passive player wake")
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.player.current_hp = 1000000
	var actor: EnemyActor = null
	for raw: Variant in game._active_enemy_cache.values():
		if raw is EnemyActor:
			raw.set_physics_process(false)
			if actor == null and raw._source176_ordinary_melee() and not raw.is_boss and raw.passive_acquisition_extent_gu() > 0.0:
				actor = raw
	if actor == null:
		check(false, "formal spawn factory supplies an ordinary budget-owned actor for wake regression")
		game.free()
		return
	actor._hc_forget(actor.target)
	actor.target = null
	actor._threat_table.clear()
	actor._hc_damage_dirty = false
	actor._clear_passive_wake()
	actor._hold_pursuit_at_current_position()
	var ground: Vector2 = game._canonical_screen_px_to_ground_gu(actor.global_position)
	var clear_position := false
	for offset: Vector2 in [Vector2(1.0,0.0), Vector2(-1.0,0.0), Vector2(0.0,1.0), Vector2(0.0,-1.0)]:
		game.player.global_position = game._canonical_ground_gu_to_screen_px(ground + offset)
		if not actor._point_inside_safe_zone(game.player.global_position) and actor._initial_acquisition_static_los_clear(game.player):
			clear_position = true
			break
	check(clear_position, "formal map supplies an unprotected visible position inside acquisition range")
	actor.set_physics_process(true)
	for _tick: int in 8:
		await get_tree().physics_frame
		await get_tree().process_frame
	check(not is_instance_valid(actor.target), "nearby player reference alone cannot autonomously activate a passive actor")
	check(int(Budget.pursuit_process_snapshot().get("queue_length", -1)) == 0, "passive actor owns no combat planning request")
	FrameBudget.configure_for_tests(0, _epoch, _clock)
	check(actor.request_passive_player_wakeup(game.player, game.current_map_id, game._zone_generation), "formal player proximity event is accepted")
	check(not actor._can_use_background_ai(), "pending wake cannot be swallowed by background preflight")
	check(actor.target == game.player, "formal proximity event assigns the live player immediately")
	check(not actor._hc_observed, "immediate activation does not synthesize rich observation")
	check(int(Budget.pursuit_process_snapshot().get("queue_length", -1)) == 0, "immediate activation does not enqueue rich planning")
	FrameBudget.configure_for_tests(1200, _epoch, _clock)
	actor.set_physics_process(false)
	check(actor.target == game.player, "formal proximity event retains the assigned player across budget recovery")
	evidence["initial_acquisition"] = Budget.pursuit_process_snapshot()
	evidence["initial_acquisition"]["monster_id"] = actor.monster_id
	evidence["initial_acquisition"]["ordinary_budget_owned"] = actor._source176_ordinary_melee()
	Budget.cancel(actor.get_instance_id())
	actor._hc_forget(actor.target)
	actor.target = null
	actor._threat_table.clear()
	actor._hc_damage_dirty = false
	actor._clear_passive_wake()
	actor._hold_pursuit_at_current_position()
	game.player.apply_stealth(60.0)
	check(not actor.request_passive_target_wakeup(game.player, game.current_map_id, game._zone_generation), "hidden player emits no activation request")
	game.player.global_position = game._canonical_ground_gu_to_screen_px(ground + Vector2(100.0, 100.0))
	var summon := SummonActor.new()
	summon.setup(game.player, "skeleton", 40, 3, "taoist.summon_skeleton", 35)
	summon.configure_runtime_map_projection(game.current_map_id, Callable(game, "_canonical_ground_gu_to_screen_px"), Callable(game, "_canonical_screen_px_to_ground_gu"))
	summon.configure_spatial_index(game._combat_spatial_index)
	summon.global_position = game._canonical_ground_gu_to_screen_px(ground + Vector2(1.0, 0.0))
	game.add_child(summon)
	summon.set_physics_process(false)
	game._register_passive_wake_emitter(summon)
	game._apply_friendly_stealth_to_actor(summon, 60.0, "buff.taoist.mass_invisibility")
	check(summon.is_stealthed(), "existing group invisibility application covers the summon")
	check(not actor.request_passive_target_wakeup(summon, game.current_map_id, game._zone_generation), "hidden summon emits no activation request")
	summon._update_support_buff_timers(61.0)
	check(not summon.is_stealthed(), "summon visibility expiry retains its old duration rule")
	actor.set_physics_process(true)
	for _tick: int in 45:
		await get_tree().physics_frame
		await get_tree().process_frame
		game._pump_passive_monster_wakeup()
		if actor.target == summon:
			break
	actor.set_physics_process(false)
	check(actor.target == summon, "visible summon halo wakes a monster and formal target selection chooses the actual summon")
	check(int(FrameBudget.snapshot().get("open_scopes", -1)) == 0, "multi-emitter pump closes its scopes")
	check(game._passive_wake_candidates_used >= 1, "movement wake batch records candidate work without the retired optional eight-candidate cap")
	Budget.cancel(actor.get_instance_id())
	summon.free()
	# A staged query can outlive a candidate after death/map teardown.
	var retired := Enemy.new()
	game._passive_wake_candidates.clear()
	game._passive_wake_candidates.append(retired)
	retired.free()
	game._passive_wake_cursor = 0
	game._passive_wake_query_pending = false
	game._passive_wake_dirty = false
	await get_tree().process_frame
	game._pump_passive_monster_wakeup()
	check(game._passive_wake_candidates.is_empty(), "wake cursor drains a freed candidate without typed-call failure")
	check(int(FrameBudget.snapshot().get("open_scopes", -1)) == 0, "freed wake candidate closes its budget scope")
	game.free()

func test_idle_selection_cadence() -> void:
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	FrameBudget.configure_for_tests(1200, _epoch, _clock)
	var player := Fixture.player(self, Vector2(100.0, 100.0))
	var actor := Enemy.new()
	actor.setup(GameData.get_monster_by_id(64), player, false)
	actor.global_position = Fixture.to_screen(Vector2(8.0, 8.0))
	actor.set_meta("spawn_position", Fixture.to_screen(Vector2(40.0, 40.0)))
	actor.set_meta("zone_generation", 1)
	actor.configure_runtime_map_projection(1, Fixture.to_screen, Fixture.to_ground)
	actor.configure_terrain_navigation_context(Fixture.open_context())
	add_child(actor)
	actor.set_physics_process(true)
	var position_before: Vector2 = actor.global_position
	for _tick: int in 40:
		await get_tree().physics_frame
		await get_tree().process_frame
	var state := Budget.pursuit_process_snapshot()
	check(not is_instance_valid(actor.target), "idle actor remains passive without an external wake")
	check(int(state.get("grants", -1)) == 0 and int(state.get("queue_length", -1)) == 0, "idle background maintenance never enqueues combat planning")
	check(actor.global_position.is_equal_approx(position_before), "disengaged actor holds its actual position instead of returning to spawn")
	check(int(state.get("open_turns", -1)) == 0, "passive background maintenance leaves no lease")
	evidence["idle_cadence"] = state
	actor.target = player
	actor._background_deep_sleeping = true
	actor._background_maintenance_running = false
	check(not actor._hc_owner_optional_budget_runnable(), "a background lightweight clock cannot reserve a rich-work slot")
	actor._background_maintenance_running = true
	check(actor._hc_owner_optional_budget_runnable(), "actual background maintenance callback retains its formal planning opportunity")
	actor._background_maintenance_running = false
	actor.target = null
	Budget.cancel(actor.get_instance_id())
	actor.free()
	player.free()

func test_simultaneous_real_owners() -> void:
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	FrameBudget.configure_for_tests(1200, _epoch, _clock)
	var player := Fixture.player(self, Vector2(20.0, 20.0))
	player.current_hp = 1000000
	var actors: Array[EnemyActor] = []
	var shared_index := Spatial.new()
	for index: int in 30:
		var actor := Fixture.enemy(self, 64, Vector2(10.0 + index % 6, 10.0 + index / 6), player)
		actor.combat_spatial_index.unregister(actor.spatial_actor_runtime_id)
		actor.combat_spatial_index = shared_index
		shared_index.register(actor.spatial_actor_runtime_id, 1, Fixture.to_ground(actor.global_position), actor.combat_radius_gu, 1, actor)
		actor.visual.advance_struck_action(5.0)
		actor._combat_action_time_s = 0.0
		actor.set_physics_process(true)
		actors.append(actor)
	var cpu_peak := 0
	for tick: int in 120:
		await get_tree().physics_frame
		await get_tree().process_frame
		var frame := FrameBudget.snapshot()
		cpu_peak = maxi(cpu_peak, int(frame.get("spent_usec", 0)))
	var served := 0
	for actor: EnemyActor in actors:
		actor.set_physics_process(false)
		if actor._owner_decision_next_time_s > 0.0:
			served += 1
	var state := Budget.pursuit_process_snapshot()
	check(served == 30, "all 30 simultaneous owners eventually receive actual planning service")
	check(int(state.get("epoch_owner_max", 100)) <= 5, "one process admits at most five distinct optional owners")
	check(int(state.get("open_turns", -1)) == 0 and int(state.get("open_borrowed", -1)) == 0, "completed engine callbacks leave no nested leases")
	check(int(FrameBudget.snapshot().get("open_scopes", -1)) == 0, "engine frame ends with no frame scope")
	evidence["burst"] = state
	evidence["burst"]["served_actor_count"] = served
	evidence["burst"]["optional_frame_spent_peak_usec"] = cpu_peak
	evidence["burst"]["physics_ticks"] = 120
	for actor: EnemyActor in actors:
		Budget.cancel(actor.get_instance_id())
		if actor.combat_spatial_index != null:
			actor.combat_spatial_index.unregister(actor.spatial_actor_runtime_id)
		actor.free()
	player.free()

func test_scope_suspend_resume() -> void:
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	quantum_clock_usec = 0
	FrameBudget.configure_for_tests(100, _epoch, _quantum_clock)
	var owner := QuantumOwner.new()
	add_child(owner)
	owner.set_physics_process(true)
	await get_tree().process_frame
	var token := Budget.begin_pursuit_turn(owner, owner._hc_pursuit_budget_scope(), &"new_step")
	check(token > 0, "quantum planning scope admits runnable owner")
	if token > 0:
		quantum_clock_usec += 80
		check(Budget.suspend_pursuit_turn(token), "planning suspends its frame scope for physical advancement")
		quantum_clock_usec += 1000
		check(int(FrameBudget.snapshot().get("spent_usec", -1)) == 80, "physical work outside planning scope is not charged as optional planning")
		check(Budget.resume_pursuit_turn(token), "same callback can resume its admitted owner without a second grant")
		quantum_clock_usec += 25
		check(Budget.suspend_pursuit_turn(token), "second pure planning quantum closes its accounting")
		check(not Budget.resume_pursuit_turn(token), "next planning quantum cannot bypass exhausted frame allowance")
		check(int(FrameBudget.snapshot().get("spent_usec", -1)) == 105, "shared budget retains prior planning cost across suspended segments")
		check(int(Budget.pursuit_process_snapshot().get("grants", -1)) == 1, "resume never creates a second owner grant")
		Budget.end_pursuit_turn(token)
	check(int(FrameBudget.snapshot().get("open_scopes", -1)) == 0, "resume denial leaves no open frame scope")
	check(int(Budget.pursuit_process_snapshot().get("open_turns", -1)) == 0, "final callback retires suspended owner lease")
	owner.free()

func test_fifo_callback_order() -> void:
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	FrameBudget.configure_for_tests(0, _epoch, _clock)
	var player := Fixture.player(self, Vector2(14.0, 8.0))
	var oldest := Fixture.enemy(self, 64, Vector2(8.0, 8.0), player)
	var newer := Fixture.enemy(self, 64, Vector2(8.0, 9.0), player)
	oldest.visual.advance_struck_action(5.0)
	newer.visual.advance_struck_action(5.0)
	oldest.set_physics_process(false)
	newer.set_physics_process(false)
	check(not oldest._owner_optional_budget_try_begin(), "zero allowance queues the oldest real owner")
	await get_tree().process_frame
	FrameBudget.configure_for_tests(1200, _epoch, _clock)
	oldest.set_physics_process(true)
	newer.set_physics_process(true)
	check(not newer._owner_optional_budget_try_begin(), "new callback cannot consume the category turn ahead of an older reserved owner")
	check(oldest._owner_optional_budget_try_begin(), "old request receives its category turn when its real callback arrives")
	oldest._owner_optional_budget_end()
	oldest.set_physics_process(false)
	newer.set_physics_process(false)
	check(int(FrameBudget.snapshot().get("open_scopes", -1)) == 0, "FIFO callback-order regression closes all scopes")
	Budget.cancel(oldest.get_instance_id())
	Budget.cancel(newer.get_instance_id())
	if oldest.combat_spatial_index != null:
		oldest.combat_spatial_index.unregister(oldest.spatial_actor_runtime_id)
	oldest.free()
	Fixture.dispose(newer, player)
