extends Node

const EnemyActorScript := preload("res://scripts/enemy.gd")
const FrameBudget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const Ground := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://tests/helpers/monster_open_terrain_test_fixture.gd")
const AttackTiming := preload("res://scripts/monster_attack_timing.gd")
const HCDecisionBudget := preload("res://scripts/monster_ai_package/decision_budget.gd")

var failures: Array[String] = []
var _budget_epoch := 0
var _budget_clock := 0

func _ready() -> void:
	_run.call_deferred()

func _budget_epoch_value() -> int:
	return _budget_epoch

func _budget_clock_value() -> int:
	return _budget_clock

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _project(value: Vector2) -> Vector2:
	return Ground.ground_delta_gu_to_screen_delta_px(value)

func _stage_debug(actor: EnemyActor) -> Dictionary:
	return {
		"process_frame": Engine.get_process_frames(),
		"physics_frame": Engine.get_physics_frames(),
		"fake_epoch": _budget_epoch,
		"fake_clock": _budget_clock,
		"frame_remaining_usec": FrameBudget.remaining_usec(),
		"scope": actor._hc_pursuit_budget_scope(),
		"runnable": actor._hc_owner_optional_budget_runnable(),
		"token": actor._owner_optional_budget_token,
		"reused": actor._owner_optional_budget_reused,
		"last_owner_tick": actor._owner_decision_last_physics_tick,
		"granted_owner_tick": actor._owner_decision_granted_physics_tick,
		"next_owner_time_s": actor._owner_decision_next_time_s,
		"stage_due": actor._boss_stage_search_due(),
		"stage_legal": actor._boss_stage_search_action_legal(),
		"dormant": actor.dormant,
		"target_id": actor.target.get_instance_id() if is_instance_valid(actor.target) else 0,
		"last_denial": HCDecisionBudget.pursuit_process_last_denial(),
		"budget": HCDecisionBudget.pursuit_process_snapshot(),
	}

func _boss(monster_id: int, player: PlayerCharacter) -> EnemyActor:
	var boss := EnemyActor.new()
	boss.setup(GameData.get_monster_by_id(monster_id).duplicate(true), player, true)
	boss.configure_runtime_map_projection(
		1,
		Callable(self, "_project"),
		Ground.screen_delta_px_to_ground_delta_gu,
	)
	boss.configure_terrain_navigation_context(Terrain.build(1))
	boss.global_position = _project(Terrain.CENTER_GROUND_GU)
	boss.target = player
	add_child(boss)
	boss.set_physics_process(false)
	return boss

func _ordinary(player: PlayerCharacter) -> EnemyActor:
	var actor := EnemyActor.new()
	actor.setup(GameData.get_monster_by_id(64).duplicate(true), player, false)
	actor.configure_runtime_map_projection(
		1,
		Callable(self, "_project"),
		Ground.screen_delta_px_to_ground_delta_gu,
	)
	actor.configure_terrain_navigation_context(Terrain.build(1))
	actor.global_position = _project(Terrain.CENTER_GROUND_GU)
	actor.target = player
	add_child(actor)
	actor.set_physics_process(false)
	return actor

func _player() -> PlayerCharacter:
	var player := PlayerCharacter.new()
	player.max_hp = 10000
	player.current_hp = player.max_hp
	player.max_mp = 0
	player.current_mp = 0
	player.defense_min = 0
	player.defense_max = 0
	player.damage_reduction = 0.0
	player.global_position = _project(Terrain.CENTER_GROUND_GU + Vector2(1.0, 0.0))
	add_child(player)
	player.set_physics_process(false)
	return player

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.computed_stats["anti_magic_points"] = 0
	PlayerState.computed_stats["magic_defense_min"] = 0
	PlayerState.computed_stats["magic_defense_max"] = 0
	EnemyActorScript.configure_owner_decision_interval_for_test(300)
	EnemyActorScript.configure_owner_optional_budget_for_test(true)
	await _check_active_visual_grant()
	await _check_boss_no_target_grant()
	await _check_224_optional_denial_does_not_block_attack()
	await _check_124_area_release_contract()
	await _check_160_summon_deadline_contract()
	EnemyActorScript.configure_owner_optional_budget_for_test(false)
	EnemyActorScript.configure_owner_decision_interval_for_test(0)
	FrameBudget.reset_test_configuration()
	var result := {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"failures": failures,
		"contract": "boss_optional_owner_budget_20261009",
		"source_sha256": FileAccess.get_sha256("res://scripts/enemy.gd"),
		"budget_sha256": FileAccess.get_sha256("res://scripts/monster_ai_package/decision_budget.gd"),
		"tested_ids": [224, 124, 160],
		"optional_interval_ms": 300,
		"frame_budget_zero_case": "executed",
	}
	var result_path := "res://outputs/test_logs/crowd_boss_optional_budget_contract_20261009.json"
	var result_file := FileAccess.open(result_path, FileAccess.WRITE)
	if result_file != null:
		result_file.store_string(JSON.stringify(result))
		result_file.close()
	print("HC_TEST_BOSS_OPTIONAL_BUDGET_RESULT=" + JSON.stringify(result))
	print("HC_TEST_BOSS_OPTIONAL_BUDGET_PASS" if failures.is_empty() else "HC_TEST_BOSS_OPTIONAL_BUDGET_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_active_visual_grant() -> void:
	var player := _player()
	var actor := _ordinary(player)
	actor.set_physics_process(true)
	EnemyActorScript.configure_attack_visual_policy_for_test(false, true)
	actor._attack_action_active = true
	actor._attack_action_start_time_s = actor._combat_action_time_s
	var granted := actor._owner_decision_window_due()
	_expect(granted, "ordinary active visual override must pass the owner-window scope witness")
	actor._owner_optional_budget_end()
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame

func _check_boss_no_target_grant() -> void:
	var player := _player()
	var boss := _boss(160, player)
	# Directly invoke the synchronous stage callback below. Keep the actor's
	# automatic physics lane frozen so zero-budget denial cannot be served
	# between the denial and recovery assertions.
	boss.set_physics_process(false)
	boss._threat_table.clear()
	boss._hc_damage_dirty = false
	# Establish the authored legal stage-maintenance state explicitly. The
	# cold-stage contract is not a dormant/stone-wake test; those gates are
	# covered by the formal Boss regression suite.
	boss.dormant = false
	boss._burrowed = false
	boss._boss_warning = 0.0
	boss._area_attack_warning = 0.0
	boss._area_magic_warning = 0.0
	boss._summon_warning = 0.0
	boss._attack_action_active = false
	boss._pending_attack_time = -1.0
	player.global_position = _project(Terrain.CENTER_GROUND_GU + Vector2(100.0, 100.0))
	boss.target = null
	boss.primary_target = null
	var search: Dictionary = boss.boss_rule.get("targetSearch", {})
	var without_target_s := float(search.get("withoutTargetMs", 0)) / 1000.0
	boss._boss_search_clock_anchor_s = boss._combat_action_time_s - without_target_s
	boss._boss_health_stage = 5
	boss.current_hp = 1
	var summon_observed := {"count": 0}
	boss.summon_requested.connect(func(_enemy: EnemyActor, _ids: Array, count: int, _max_active: int) -> void:
		summon_observed["count"] += count
	)
	var denied_anchor := boss._boss_search_clock_anchor_s
	_budget_epoch += 1
	_budget_clock += 1
	FrameBudget.configure_for_tests(0, Callable(self, "_budget_epoch_value"), Callable(self, "_budget_clock_value"))
	boss._owner_decision_last_physics_tick = -1
	print("HC_TEST_BOSS160_STAGE_DEBUG_BEFORE_DENIAL=" + JSON.stringify(_stage_debug(boss)))
	boss._retarget(0.0)
	var denied_stats: Dictionary = boss.pursuit_process_budget_diagnostics()
	print("HC_TEST_BOSS160_STAGE_DEBUG_AFTER_DENIAL=" + JSON.stringify(_stage_debug(boss)))
	_expect(is_equal_approx(boss._boss_search_clock_anchor_s, denied_anchor), "Boss no-target stage must keep its authored anchor when optional budget is denied")
	_expect(int(summon_observed["count"]) == 0, "Boss no-target stage must not summon while optional FrameBudget allowance is zero")
	_expect(int(denied_stats.get("owner_budget_denied", 0)) >= 1, "Boss no-target stage denial must be recorded as owner budget denial")
	# FrameBudget's fake epoch callbacks do not advance HCDecisionBudget's
	# Engine.get_process_frames() epoch; cross one real process frame before retry.
	await get_tree().process_frame
	FrameBudget.configure_for_tests(100000, Callable(self, "_budget_epoch_value"), Callable(self, "_budget_clock_value"))
	_budget_epoch += 1
	_budget_clock += 1
	# The synchronous owner caller is temporarily foreground for the recovery
	# admission. Freeze it immediately after the call so no automatic physics
	# callback can consume the recovered stage between assertions.
	boss.set_physics_process(true)
	boss._owner_decision_last_physics_tick = -1
	print("HC_TEST_BOSS160_STAGE_DEBUG_BEFORE_RECOVERY=" + JSON.stringify(_stage_debug(boss)))
	boss._retarget(0.0)
	boss.set_physics_process(false)
	# The synchronous callback's production finally boundary closes the lease
	# before any later FrameBudget reset or fixture cleanup.
	boss._owner_optional_budget_end()
	_expect(not is_instance_valid(boss.target), "Boss no-target stage service must remain a no-target maintenance case")
	var service_anchor := boss._boss_search_clock_anchor_s
	var service_stats: Dictionary = boss.pursuit_process_budget_diagnostics()
	print("HC_TEST_BOSS160_STAGE_DEBUG_AFTER_RECOVERY=" + JSON.stringify(_stage_debug(boss)))
	_expect(is_equal_approx(service_anchor, boss._combat_action_time_s), "Boss no-target authored stage service must advance its own stage clock")
	_expect(int(summon_observed["count"]) > 0, "Boss no-target stage service must emit its formal summon exactly once after permit recovery")
	_expect(int(service_stats.get("owner_decision_served", 0)) >= 1, "Boss no-target stage service must record its completed optional owner service")
	var due_count := int(service_stats.get("owner_decision_due", 0))
	var summon_count_after_service := int(summon_observed["count"])
	boss._combat_action_time_s += 0.01
	boss._owner_decision_last_physics_tick = -1
	boss._retarget(0.01)
	var wait_stats: Dictionary = boss.pursuit_process_budget_diagnostics()
	_expect(int(wait_stats.get("owner_decision_due", 0)) == due_count, "Boss no-target service must not regrant on the next not-due physics")
	_expect(int(summon_observed["count"]) == summon_count_after_service, "Boss no-target service must not repeat before its authored stage deadline")
	FrameBudget.reset_test_configuration()
	boss.queue_free()
	player.queue_free()
	await get_tree().process_frame

	# Regression: the authored no-target stage clock is still before its 1 s
	# boundary. A cold Boss must remain passive until that authored boundary;
	# it must not create a player-search owner request.
	var early_player := _player()
	var early_boss := _boss(160, early_player)
	early_boss.set_physics_process(false)
	early_boss._threat_table.clear()
	early_boss._hc_damage_dirty = false
	early_boss.dormant = false
	early_boss._burrowed = false
	early_boss._boss_warning = 0.0
	early_boss._area_attack_warning = 0.0
	early_boss._area_magic_warning = 0.0
	early_boss._summon_warning = 0.0
	early_boss._attack_action_active = false
	early_boss._pending_attack_time = -1.0
	early_player.global_position = _project(Terrain.CENTER_GROUND_GU + Vector2(100.0, 100.0))
	early_boss.target = null
	early_boss.primary_target = null
	early_boss._boss_search_clock_anchor_s = early_boss._combat_action_time_s
	_expect(not early_boss._boss_stage_search_due(), "160 no-target owner regression must begin before authored stage deadline")
	early_boss._owner_decision_last_physics_tick = -1
	var early_next_deadline := early_boss._owner_decision_next_time_s
	var early_stats_before: Dictionary = early_boss.pursuit_process_budget_diagnostics()
	print("HC_TEST_BOSS160_STAGE_DEBUG_EARLY_BEFORE=" + JSON.stringify(_stage_debug(early_boss)))
	early_boss._retarget(0.0)
	var early_stats_after: Dictionary = early_boss.pursuit_process_budget_diagnostics()
	print("HC_TEST_BOSS160_STAGE_DEBUG_EARLY_AFTER=" + JSON.stringify(_stage_debug(early_boss)))
	_expect(not is_instance_valid(early_boss.target), "160 early no-target owner service must keep target null")
	_expect(early_boss._owner_decision_next_time_s == early_next_deadline, "160 early no-target passive state must not consume an owner deadline")
	_expect(
		int(early_stats_after.get("owner_decision_due", 0)) == int(early_stats_before.get("owner_decision_due", 0)),
		"160 early no-target passive state must not grant player-search service",
	)
	early_boss._owner_optional_budget_end()
	early_boss.queue_free()
	early_player.queue_free()
	await get_tree().process_frame

func _check_224_optional_denial_does_not_block_attack() -> void:
	var player := _player()
	player.global_position = _project(Terrain.CENTER_GROUND_GU + Vector2(2.0, 0.0))
	var boss := _boss(224, player)
	boss.set_physics_process(true)
	boss.take_damage(1, player)
	var hp_before := player.current_hp
	_budget_epoch += 1
	_budget_clock += 1
	FrameBudget.configure_for_tests(0, Callable(self, "_budget_epoch_value"), Callable(self, "_budget_clock_value"))
	var due := boss._owner_decision_window_due()
	_expect(not due, "224 optional owner window must be denied at zero FrameBudget")
	var denial := boss.pursuit_process_budget_diagnostics()
	_expect(int(denial.get("owner_budget_denied", 0)) >= 1, "224 denial must be recorded as owner optional denial")
	# Keep optional budget at zero through the real physics/release condition.
	# The attack lane is separate from owner maintenance and must still settle HP.
	boss._physics_process(0.01)
	boss._physics_process(0.21)
	var target_magic_release_id := str(boss.last_magic_attack_resolution.get("release_id", ""))
	_expect(
		target_magic_release_id.contains(":target_magic:release:")
			and int(boss.last_magic_attack_resolution.get("source_monster_id", -1)) == 224
			and str(boss.last_magic_attack_resolution.get("damage_channel", "")) == "magic_defense"
			and bool(boss.last_magic_attack_resolution.get("success", false)),
		"224 target magic must retain its formal release receipt and magic channel",
	)
	_expect(player.current_hp < hp_before, "224 target magic must settle HP despite maintenance denial")
	print("HC_TEST_BOSS224_ACTUAL=" + JSON.stringify({
		"rule": boss.attack_delivery_rule,
		"target_offset": boss._ground_delta_gu_between_screen_positions(boss.global_position, player.global_position),
		"resolution": boss.last_magic_attack_resolution,
		"boss_dormant": boss.dormant,
		"boss_target_id": boss.target.get_instance_id() if is_instance_valid(boss.target) else 0,
	}))
	FrameBudget.reset_test_configuration()
	boss.queue_free()
	player.queue_free()
	await get_tree().process_frame

func _check_124_area_release_contract() -> void:
	var player := _player()
	var boss := _boss(124, player)
	boss.set_physics_process(true)
	var hp_before := player.current_hp
	_budget_epoch += 1
	_budget_clock += 1
	FrameBudget.configure_for_tests(0, Callable(self, "_budget_epoch_value"), Callable(self, "_budget_clock_value"))
	for _tick in range(12):
		boss._physics_process(0.1)
		if not boss.last_magic_attack_resolution.is_empty():
			break
	FrameBudget.reset_test_configuration()
	_expect(
		str(boss.last_magic_attack_resolution.get("delivery_kind", "")) == "area_magic",
		"124 must retain the formal area-magic delivery path",
	)
	_expect(player.current_hp < hp_before, "124 area release must settle actual HP on its authored release")
	_expect(
		str(boss._area_magic_footprint_snapshot.get("range_shape", "")) == "chebyshev_axis_aligned_square_exclusive",
		"124 area release must preserve the frozen authored footprint",
	)
	print("HC_TEST_BOSS124_ACTUAL=" + JSON.stringify({
		"rule": boss.attack_delivery_rule,
		"area_warning": boss._area_magic_warning,
		"resolution": boss.last_magic_attack_resolution,
		"area_magic_footprint": boss._area_magic_footprint_snapshot,
		"last_footprint": boss._last_attack_footprint_snapshot,
		"boss_dormant": boss.dormant,
		"boss_burrowed": boss._burrowed,
	}))
	boss.queue_free()
	player.queue_free()
	await get_tree().process_frame

func _check_160_summon_deadline_contract() -> void:
	var player := _player()
	var boss := _boss(160, player)
	boss.set_physics_process(true)
	var summon_count := 0
	boss.summon_requested.connect(func(_enemy: EnemyActor, _ids: Array, count: int, _max_active: int) -> void:
		summon_count += count
	)
	# Compare against the canonical timing actually bound by Enemy.setup, not a
	# pre-binding GameData wrapper whose shape may differ from behavior_profile.
	var canonical_timing: Dictionary = boss.behavior_profile.get("timing", {})
	var canonical_interval_s := float(AttackTiming.effective_interval_ms(canonical_timing.get("attackIntervalMs", 0))) / 1000.0
	_expect(is_equal_approx(boss._boss_base_attack_interval, canonical_interval_s), "160 attack interval must match canonical timing")
	print("HC_TEST_BOSS160_ACTUAL=" + JSON.stringify({
		"raw_timing": canonical_timing,
		"effective_interval_s": canonical_interval_s,
		"boss_interval_s": boss._boss_base_attack_interval,
		"rule": boss.boss_rule,
		"boss_dormant": boss.dormant,
	}))
	var search: Dictionary = boss.boss_rule.get("targetSearch", {})
	var with_target_s := float(search.get("withTargetMs", 0)) / 1000.0
	var without_target_s := float(search.get("withoutTargetMs", 0)) / 1000.0
	var anchor := boss._boss_search_clock_anchor_s
	boss._boss_search_clock_anchor_s = boss._combat_action_time_s - with_target_s
	_expect(boss._boss_stage_search_due(), "160 with-target stage search must honor canonical deadline")
	boss.target = null
	boss._boss_search_clock_anchor_s = boss._combat_action_time_s - without_target_s
	_expect(boss._boss_stage_search_due(), "160 no-target stage search must honor canonical deadline")
	boss._boss_search_clock_anchor_s = anchor
	boss.target = player
	for _tick in range(10):
		boss._physics_process(0.1)
	_expect(summon_count == 0, "160 must not summon before the canonical search boundary")
	boss.queue_free()
	player.queue_free()
	await get_tree().process_frame
