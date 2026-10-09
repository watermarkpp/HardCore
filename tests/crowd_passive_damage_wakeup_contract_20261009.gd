extends Node

const Enemy := preload("res://scripts/enemy.gd")
const Fixture := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Budget := preload("res://scripts/monster_ai_package/decision_budget.gd")
const FrameBudget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const Spatial := preload("res://scripts/runtime_combat_spatial_index.gd")

var failures: Array[String] = []
var evidence: Dictionary = {}

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _epoch() -> int:
	return Engine.get_process_frames()

func _clock() -> int:
	return Time.get_ticks_usec()

func _ready() -> void:
	await get_tree().process_frame
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	check(GameData.is_loaded(), "canonical game data is loaded")
	await _test_remote_physical_damage_wakes_cold_enemy()
	await _test_remote_magic_and_ground_damage_wake_cold_enemy()
	evidence["failures"] = failures
	evidence["status"] = "PASS" if failures.is_empty() else "FAIL"
	var out := FileAccess.open("res://outputs/test_logs/crowd_passive_damage_wakeup_contract_20261009.json", FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(evidence, "\t"))
	if failures.is_empty():
		print("HC_PASSIVE_DAMAGE_WAKEUP_CONTRACT_20261009_PASS")
	else:
		for message: String in failures:
			print("HC_TEST_FAIL ", message)
	get_tree().quit(0 if failures.is_empty() else 1)

func _make_enemy(id: int, ground: Vector2, primary: PlayerCharacter) -> EnemyActor:
	var actor := Enemy.new()
	actor.setup(GameData.get_monster_by_id(id), primary, false)
	actor.global_position = Fixture.to_screen(ground)
	actor.set_meta("spawn_position", actor.global_position)
	actor.set_meta("safe_zones", [])
	actor.set_meta("zone_generation", 1)
	actor.configure_runtime_map_projection(1, Callable(Fixture.GU, "ground_delta_gu_to_screen_delta_px"), Callable(Fixture.GU, "screen_delta_px_to_ground_delta_gu"))
	actor.configure_terrain_navigation_context(Fixture.open_context())
	actor.combat_spatial_index = Spatial.new()
	actor.spatial_actor_runtime_id = actor.get_instance_id()
	actor.combat_spatial_index.register(actor.spatial_actor_runtime_id, 1, Fixture.to_ground(actor.global_position), actor.combat_radius_gu, 1, actor)
	add_child(actor)
	actor.set_physics_process(false)
	actor.target = null
	actor._threat_table.clear()
	actor._hc_damage_dirty = false
	actor._clear_passive_wake()
	return actor

func _make_player(ground: Vector2) -> PlayerCharacter:
	var player := Fixture.player(self, ground)
	player.set_meta("zone_generation", 1)
	return player

func _sleep(actor: EnemyActor) -> void:
	actor._enter_background_deep_sleep(true)
	check(actor._background_deep_sleeping, "cold actor entered the real background sleep path")

func _dispose_enemy(actor: EnemyActor) -> void:
	if actor == null:
		return
	Budget.cancel(actor.get_instance_id())
	if actor.combat_spatial_index != null and actor.spatial_actor_runtime_id > 0:
		actor.combat_spatial_index.unregister(actor.spatial_actor_runtime_id)
	actor.free()

func _test_remote_physical_damage_wakes_cold_enemy() -> void:
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	FrameBudget.configure_for_tests(0, _epoch, _clock)
	var player := _make_player(Vector2(16.0, 8.0))
	var cold := _make_enemy(64, Vector2(8.0, 8.0), player)
	var attacker: PlayerCharacter = player
	# Eight GU is outside the ordinary 6-GU first-acquisition halo, while the
	# formal 15-GU disengage envelope remains available for threat pursuit.
	var distance_gu := Fixture.to_ground(attacker.global_position).distance_to(Fixture.to_ground(cold.global_position))
	check(cold.passive_acquisition_extent_gu() == 6.0, "ordinary cold actor uses the approved 6-GU halo")
	check(distance_gu > cold.passive_acquisition_extent_gu() and distance_gu < 15.0, "remote attacker is outside halo but inside disengage envelope")
	_sleep(cold)
	var hp_before := cold.current_hp
	# This is the production resolved-damage entry with the real PlayerCharacter attacker
	# It must wake before any target search and retain the player in the existing
	# threat table, even when optional planning has zero budget.
	cold.take_damage(7, attacker, {"source_class": "direct", "damage_channel": "physical"}, {"release_id": "remote_physical_wakeup"})
	check(cold.current_hp == hp_before - 7, "remote physical damage commits positive HP loss")
	check(not cold._background_deep_sleeping, "positive remote damage leaves background sleep immediately")
	check(cold._threat_table.has(attacker.get_instance_id()), "real attacker is retained in the production threat table")
	check(cold._hc_damage_dirty, "damage wake marks immediate pursuit work dirty")
	check(cold.is_physics_processing(), "formal damage wake restores physics processing")
	# Zero optional allowance must defer rich target selection, not discard the
	# wake or turn the actor inert. The existing target remains null at this
	# point, but the actor is still a runnable combat participant.
	cold._retarget(1.0 / 60.0)
	var target_after_denial := is_instance_valid(cold.target)
	check(not target_after_denial, "optional denial does not invent a target or run rich planning")
	check(Budget.pursuit_process_snapshot().get("open_turns", -1) == 0, "denied damage wake closes its owner lease")
	check(cold._hc_owner_optional_budget_runnable(), "damage-woken actor remains runnable while optional planning is denied")
	var physical_denial_budget := Budget.pursuit_process_snapshot()
	var physical_denial_frame := FrameBudget.snapshot()
	FrameBudget.configure_for_tests(1200, _epoch, _clock)
	var physical_wait_frames := 0
	for _step: int in 60:
		await get_tree().physics_frame
		await get_tree().process_frame
		physical_wait_frames += 1
		if cold.target == attacker:
			break
		if not is_instance_valid(cold.target):
			cold._retarget(1.0 / 60.0)
			cold._owner_optional_budget_end()
	check(cold.target == attacker, "bounded recovery selects the real PlayerCharacter attacker")
	cold._owner_optional_budget_end()
	check(int(FrameBudget.snapshot().get("open_scopes", -1)) == 0, "physical wake closes all frame scopes")
	evidence["remote_physical"] = {
		"halo_gu": cold.passive_acquisition_extent_gu(),
		"attacker_distance_gu": distance_gu,
		"hp_before": hp_before,
		"hp_after": cold.current_hp,
		"sleep_after_damage": cold._background_deep_sleeping,
		"threat_has_attacker": cold._threat_table.has(attacker.get_instance_id()),
		"target_after_denial": target_after_denial,
		"target_after_recovery": cold.target == attacker,
		"budget": Budget.pursuit_process_snapshot(),
		"wait_frames": physical_wait_frames,
		"denial_budget": physical_denial_budget,
		"denial_frame": physical_denial_frame,
	}
	var fatal := _make_enemy(64, Vector2(8.0, 12.0), player)
	_sleep(fatal)
	fatal.take_damage(fatal.current_hp, player, {"source_class": "direct", "damage_channel": "physical"}, {"release_id": "fatal_remote_wakeup"})
	check(fatal.current_hp <= 0 and (fatal._dying or fatal._death_pending), "fatal remote damage follows the real death owner")
	check(not fatal._background_deep_sleeping, "fatal remote damage does not re-enter background sleep")
	_dispose_enemy(fatal)
	_dispose_enemy(cold)
	player.free()
	FrameBudget.reset_test_configuration()

func _test_remote_magic_and_ground_damage_wake_cold_enemy() -> void:
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	FrameBudget.configure_for_tests(0, _epoch, _clock)
	var player := _make_player(Vector2(16.0, 8.0))
	var magic_cold := _make_enemy(64, Vector2(8.0, 8.0), player)
	var magic_attacker: PlayerCharacter = player
	var magic_distance_gu := Fixture.to_ground(magic_attacker.global_position).distance_to(Fixture.to_ground(magic_cold.global_position))
	check(magic_distance_gu > magic_cold.passive_acquisition_extent_gu(), "remote magic source is outside the ordinary halo")
	_sleep(magic_cold)
	var magic_hp_before := magic_cold.current_hp
	# Player lightning/projectile resolution reaches EnemyActor through the
	# receiver's typed damage authority. The source class/channel witness is
	# retained here while the real attacker object drives _add_threat().
	magic_cold.take_damage(
		9,
		magic_attacker,
		{"source_class": "direct", "damage_channel": "magic_defense", "skill_id": "wizard.lightning"},
		{"release_id": "player_magic_receiver_wakeup", "skill_id": "wizard.lightning"},
	)
	check(magic_cold.current_hp == magic_hp_before - 9, "remote magic damage commits positive Enemy HP loss")
	check(not magic_cold._background_deep_sleeping, "remote magic damage leaves background sleep")
	check(magic_cold._threat_table.has(magic_attacker.get_instance_id()), "remote magic retains the actual attacker in threat")
	check(magic_cold._hc_damage_dirty, "remote magic marks immediate pursuit work dirty")
	check(magic_cold.is_physics_processing(), "formal magic damage wake restores physics processing")
	magic_cold._retarget(1.0 / 60.0)
	check(not is_instance_valid(magic_cold.target), "optional denial does not run rich magic retarget")
	check(magic_cold._hc_owner_optional_budget_runnable(), "magic-woken actor remains runnable while optional planning is denied")
	var magic_denial_budget := Budget.pursuit_process_snapshot()
	var magic_denial_frame := FrameBudget.snapshot()
	FrameBudget.configure_for_tests(1200, _epoch, _clock)
	var magic_wait_frames := 0
	for _step: int in 60:
		await get_tree().physics_frame
		await get_tree().process_frame
		magic_wait_frames += 1
		if magic_cold.target == magic_attacker:
			break
		if not is_instance_valid(magic_cold.target):
			magic_cold._retarget(1.0 / 60.0)
		magic_cold._owner_optional_budget_end()
	check(magic_cold.target == magic_attacker, "bounded magic recovery selects the real PlayerCharacter attacker")
	magic_cold._owner_optional_budget_end()
	check(int(FrameBudget.snapshot().get("open_scopes", -1)) == 0, "magic wake closes all frame scopes")
	evidence["remote_magic_receiver"] = {
		"damage_channel": "magic_defense",
		"skill_id": "wizard.lightning",
		"halo_gu": magic_cold.passive_acquisition_extent_gu(),
		"attacker_distance_gu": magic_distance_gu,
		"hp_before": magic_hp_before,
		"hp_after": magic_cold.current_hp,
		"sleep_after_damage": magic_cold._background_deep_sleeping,
		"threat_has_attacker": magic_cold._threat_table.has(magic_attacker.get_instance_id()),
		"target_after_recovery": magic_cold.target == magic_attacker,
		"wait_frames": magic_wait_frames,
		"denial_budget": magic_denial_budget,
		"denial_frame": magic_denial_frame,
	}
	_dispose_enemy(magic_cold)
	player.free()

	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	FrameBudget.configure_for_tests(0, _epoch, _clock)
	var dot_player := _make_player(Vector2(16.0, 8.0))
	var dot_cold := _make_enemy(64, Vector2(8.0, 8.0), dot_player)
	var dot_attacker: PlayerCharacter = dot_player
	_sleep(dot_cold)
	var dot_hp_before := dot_cold.current_hp
	# Ground/DOT damage is the formal no-struck receiver path. It still has
	# positive HP authority and must wake a dormant actor without synthesizing a
	# visual hit or bypassing the ordinary threat owner.
	dot_cold.take_ground_tick_damage(5, dot_attacker, {"source_class": "periodic", "damage_channel": "magic_defense"})
	check(dot_cold.current_hp == dot_hp_before - 5, "ground periodic damage commits positive Enemy HP loss")
	check(not dot_cold._background_deep_sleeping, "ground periodic damage leaves background sleep")
	check(dot_cold._threat_table.has(dot_attacker.get_instance_id()), "ground periodic damage retains the real attacker")
	check(dot_cold.visual == null or not dot_cold.visual.is_struck_action_active(), "ground periodic damage does not create a struck action")
	check(dot_cold._hc_damage_dirty, "ground periodic damage marks pursuit work dirty")
	check(dot_cold.is_physics_processing(), "formal ground damage wake restores physics processing")
	evidence["ground_periodic"] = {
		"hp_before": dot_hp_before,
		"hp_after": dot_cold.current_hp,
		"sleep_after_damage": dot_cold._background_deep_sleeping,
		"threat_has_attacker": dot_cold._threat_table.has(dot_attacker.get_instance_id()),
		"struck_active": dot_cold.visual != null and dot_cold.visual.is_struck_action_active(),
	}
	_dispose_enemy(dot_cold)
	dot_player.free()
	FrameBudget.reset_test_configuration()
