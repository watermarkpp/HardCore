extends "res://scripts/game_root.gd"

const SpatialIndex := preload("res://scripts/runtime_combat_spatial_index.gd")
const SpellTargetLockPolicy := preload("res://scripts/skills/spell_target_lock_policy.gd")
const WarriorMeleeGeometry := preload("res://scripts/skills/warrior_melee_geometry.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const RuntimeDiagnostics := preload("res://scripts/runtime_diagnostics.gd")

const RUNTIME_MAP_ID := 910001
const FIXTURE_COUNT := 96
const TARGET_SCAN_FUNCTIONS: Array[String] = [
	"_attack_lock_candidates",
	"_spell_lock_candidates",
	"_refresh_target_highlights",
	"_select_wild_rush_target",
	"_wild_rush_has_dynamic_blocker",
	"_canonical_target_context",
	"_canonical_summon_position_is_valid",
	"_find_valid_random_teleport_position",
	"_melee_candidate_diagnostics",
]

var _fixture: Array[EnemyActor] = []
var _failed := false
var _failure_messages: Array[String] = []
var _previous_test_mode := false


func _ready() -> void:
	# This scene owns only the resolver fixture.  Do not let GameRoot's normal
	# bootstrap/process loop mutate or tear down actors while the parity checks
	# exercise the formal target entrypoints.
	set_process(false)
	set_physics_process(false)
	_run.call_deferred()


func _run() -> void:
	_previous_test_mode = PlayerState.test_mode
	PlayerState.test_mode = true
	PlayerState.profession = "战士"
	PlayerState.level = 50
	PlayerState.learned_skills = {}
	PlayerState.recalculate_stats()
	current_map_id = RUNTIME_MAP_ID
	_zone_generation = 1
	_begin_safe_zone_context(RUNTIME_MAP_ID)
	_active_safe_zones.clear()
	reference_audit_mode = false
	set_aoe_reference_fallback_for_test(false)
	background = WorldBackground.new()
	background.zone_name = "比奇郊外"
	background.zone_data = {"mapId": 4}
	_combat_spatial_index = SpatialIndex.new()
	player = PlayerCharacter.new()
	player.name = "R3X6FixturePlayer"
	player.global_position = _canonical_ground_gu_to_screen_px(Vector2.ZERO)
	player.set_process(false)
	player.set_physics_process(false)
	add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.global_position = _canonical_ground_gu_to_screen_px(Vector2.ZERO)
	_build_fixture()

	_test_structural_gates()
	_test_index_order_and_lifecycle()
	_test_target_lock_parity()
	_test_wild_rush_contract()
	_test_canonical_context_and_summon_occupancy()
	_test_highlight_delta()
	_test_fail_closed_without_index()
	await _test_death_unregister_and_map_clear()

	_cleanup_fixture()
	PlayerState.test_mode = _previous_test_mode
	RuntimeDiagnostics.set_device_lab_performance_enabled(false)
	RuntimeDiagnostics.refresh_performance_gate()
	if _failed:
		push_error(
			"GAME_ROOT_R3X6_TARGETING_BROADPHASE_FAIL: %s"
			% "; ".join(_failure_messages)
		)
		get_tree().quit(1)
		return
	print(
		"GAME_ROOT_R3X6_TARGETING_BROADPHASE_PASS actors=%d stable_order=spawn_serial "
		% FIXTURE_COUNT
	)
	get_tree().quit(0)


func _build_fixture() -> void:
	for fixture_index: int in range(FIXTURE_COUNT):
		var enemy := EnemyActor.new()
		enemy.name = "R3X6Fixture_%03d" % fixture_index
		enemy.setup(
			{
				"monster_id": 38,
				"name": enemy.name,
				"hp": 1000,
				"attackMin": 1,
				"attackMax": 1,
				"level": 1,
				"agility": 0,
				"defMin": 0,
				"defMax": 0,
			},
			player,
			false,
		)
		# The fixture is a target-query fixture, not a live AI actor.  Clearing
		# primary_target before _ready also avoids spawn-overlap correction moving
		# the deliberately authored boundary positions.
		enemy.primary_target = null
		enemy.set_meta("r3x6_fixture_id", fixture_index)
		enemy.set_meta("spawn_serial", fixture_index + 1)
		enemy.set_meta("zone_generation", _zone_generation)
		enemy.configure_runtime_map_projection(
		RUNTIME_MAP_ID,
		Callable(self, "_canonical_ground_gu_to_screen_px"),
		Callable(self, "_canonical_screen_px_to_ground_gu"),
		)
		enemy.configure_spatial_index(
		_combat_spatial_index,
		fixture_index + 1,
		)
		enemy.global_position = _canonical_ground_gu_to_screen_px(
		_fixture_ground_position(fixture_index)
		)
		add_child(enemy)
		enemy.set_process(false)
		enemy.set_physics_process(false)
		enemy.set_combat_position(
		_canonical_ground_gu_to_screen_px(_fixture_ground_position(fixture_index)),
		&"r3x6_fixture_spawn",
		)
		_combat_spatial_index.register(
			fixture_index + 1,
			RUNTIME_MAP_ID,
			_fixture_ground_position(fixture_index),
			enemy.combat_radius_gu,
			fixture_index + 1,
			enemy,
			Callable(enemy, "spatial_index_position"),
		)
		_fixture.append(enemy)


func _fixture_ground_position(fixture_index: int) -> Vector2:
	var special: Array[Vector2] = [
		Vector2(1.20, 0.0),
		Vector2(-1.20, 0.0),
		Vector2(3.00, 0.0),
		Vector2(3.00, 2.00),
		Vector2(6.00, 0.0),
		Vector2(9.50, 0.0),
		Vector2(12.01, 0.0),
		Vector2(0.0, 1.30),
		Vector2(0.0, -1.30),
		Vector2(2.50, 2.00),
		Vector2(-2.50, 2.00),
		Vector2(20.0, 20.0),
	]
	if fixture_index < special.size():
		return special[fixture_index]
	var column := (fixture_index - special.size()) % 12
	var row := int((fixture_index - special.size()) / 12)
	return Vector2(
		40.0 + float(column) * 4.0,
		40.0 + float(row) * 4.0,
	)


func _move_enemy(enemy: EnemyActor, ground_position_gu: Vector2) -> void:
	if not is_instance_valid(enemy):
		return
	enemy.set_combat_position(
		_canonical_ground_gu_to_screen_px(ground_position_gu),
		&"r3x6_fixture_move",
	)


func _register_enemy(enemy: EnemyActor) -> void:
	if not is_instance_valid(enemy) or not _target_spatial_enemy_is_current(enemy):
		return
	var serial := int(enemy.get_meta("spawn_serial", -1))
	if serial <= 0:
		return
	_combat_spatial_index.register(
		serial,
		RUNTIME_MAP_ID,
		_canonical_screen_px_to_ground_gu(enemy.global_position),
		enemy.combat_radius_gu,
		serial,
		enemy,
		Callable(enemy, "spatial_index_position"),
	)


func _current_group_enemies() -> Array[EnemyActor]:
	var result: Array[EnemyActor] = []
	for raw_value: Variant in get_tree().get_nodes_in_group("enemies"):
		if not raw_value is EnemyActor:
			continue
		var enemy := raw_value as EnemyActor
		if _target_spatial_enemy_is_current(enemy):
			result.append(enemy)
	result.sort_custom(func(a: EnemyActor, b: EnemyActor) -> bool:
		return int(a.get_meta("spawn_serial", 0)) < int(b.get_meta("spawn_serial", 0))
	)
	return result


func _enemy_ids(enemies: Array[EnemyActor]) -> Array[int]:
	var result: Array[int] = []
	for enemy: EnemyActor in enemies:
		if is_instance_valid(enemy):
			result.append(int(enemy.get_meta("r3x6_fixture_id", -1)))
	return result


func _group_aabb_reference(bounds_ground_gu: Rect2) -> Array[EnemyActor]:
	var result: Array[EnemyActor] = []
	var radius := 0.5
	if not _fixture.is_empty() and is_instance_valid(_fixture[0]):
		radius = _fixture[0].combat_radius_gu
	var expanded := Rect2(
		bounds_ground_gu.position - Vector2.ONE * radius,
		bounds_ground_gu.size + Vector2.ONE * radius * 2.0,
	)
	for enemy: EnemyActor in _current_group_enemies():
		if expanded.has_point(_canonical_screen_px_to_ground_gu(enemy.global_position)):
			result.append(enemy)
	return result


func _query_aabb(bounds_ground_gu: Rect2) -> Array[EnemyActor]:
	var output: Array[EnemyActor] = []
	_combat_spatial_index.query_enemy_nodes_aabb_into(
		RUNTIME_MAP_ID,
		bounds_ground_gu,
		output,
	)
	return output


func _test_structural_gates() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/game_root.gd")
	_expect(not source.is_empty(), "GameRoot source is readable")
	for function_name: String in TARGET_SCAN_FUNCTIONS:
		var body := _function_body(source, function_name)
		_expect(not body.is_empty(), "missing R3X6 target function %s" % function_name)
		_expect(
			not body.contains('get_nodes_in_group("enemies")'),
			"formal target function still scans enemies group: %s" % function_name,
		)
	_expect(
		source.contains("_target_spatial_query_aabb_into")
			and source.contains("_target_spatial_query_segment_into"),
		"GameRoot target consumers must share mapped broadphase helpers",
	)


func _test_index_order_and_lifecycle() -> void:
	_expect(_fixture.size() == FIXTURE_COUNT, "96 EnemyActor fixtures were not built")
	var query_bounds := Rect2(Vector2(-6.0, -6.0), Vector2(18.0, 18.0))
	var actual := _query_aabb(query_bounds)
	var expected := _group_aabb_reference(query_bounds)
	_expect(
		_enemy_ids(actual) == _enemy_ids(expected),
		"AABB candidates/order differ from stable group insertion order: %s != %s"
		% [_enemy_ids(actual), _enemy_ids(expected)],
	)
	var remote := _fixture[95]
	_move_enemy(remote, Vector2(2.25, 2.25))
	var moved := _query_aabb(query_bounds)
	_expect(moved.has(remote), "cross-bucket movement was not visible immediately")
	_move_enemy(remote, _fixture_ground_position(95))
	_expect(
		not _query_aabb(query_bounds).has(remote),
		"cross-bucket movement left a stale nearby candidate",
	)
	var saved_generation := _zone_generation
	_zone_generation += 1
	var generation_filtered: Array[EnemyActor] = []
	_expect(
		_target_spatial_query_aabb_into(query_bounds, generation_filtered)
			and generation_filtered.is_empty(),
		"stale zone generation was not fail-closed",
	)
	_zone_generation = saved_generation
	_begin_safe_zone_context(RUNTIME_MAP_ID)
	var map_count_before := _combat_spatial_index.registered_actor_count()
	_combat_spatial_index.clear_map(RUNTIME_MAP_ID)
	_expect(
		_combat_spatial_index.registered_actor_count() == 0
			and _query_aabb(query_bounds).is_empty(),
		"map clear retained spatial candidates",
	)
	for enemy: EnemyActor in _current_group_enemies():
		_register_enemy(enemy)
	_expect(
		_combat_spatial_index.registered_actor_count() == map_count_before,
		"respawn/register lifecycle did not restore all live actors",
	)


func _expected_lock_candidates(magic: bool) -> Array[EnemyActor]:
	var origin := _canonical_screen_px_to_ground_gu(player.global_position)
	var range_gu := (
		SpellTargetLockPolicy.LOCK_RANGE_GU
		if magic
		else ATTACK_LOCK_RANGE_GU
	)
	var ranked: Array[Dictionary] = []
	for enemy: EnemyActor in _current_group_enemies():
		var distance := GroundUnitSpace.distance_gu(
			origin,
			_canonical_screen_px_to_ground_gu(enemy.global_position),
		)
		if distance > range_gu + GroundUnitSpace.EPSILON_GU:
			continue
		ranked.append({
			"enemy": enemy,
			"distance_squared": distance * distance,
			"instance_id": enemy.get_instance_id(),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(
				float(a.get("distance_squared", INF)),
				float(b.get("distance_squared", INF))
			):
			return float(a.get("distance_squared", INF)) < float(b.get("distance_squared", INF))
		return int(a.get("instance_id", 0)) < int(b.get("instance_id", 0))
	)
	var result: Array[EnemyActor] = []
	for entry: Dictionary in ranked:
		result.append(entry.get("enemy") as EnemyActor)
	return result


func _test_target_lock_parity() -> void:
	_move_enemy(_fixture[5], Vector2(10.0, 0.0))
	_move_enemy(_fixture[6], Vector2(12.01, 0.0))
	var attack := _attack_lock_candidates()
	var spell := _spell_lock_candidates()
	_expect(
		_enemy_ids(attack) == _enemy_ids(_expected_lock_candidates(false)),
		"attack lock order/range differs from group authority",
	)
	_expect(
		_enemy_ids(spell) == _enemy_ids(_expected_lock_candidates(true)),
		"spell lock order/range differs from group authority",
	)
	_expect(attack.has(_fixture[5]) and not attack.has(_fixture[6]), "10 GU boundary changed")
	_expect(spell.has(_fixture[5]) and not spell.has(_fixture[6]), "12 GU boundary fixture was not isolated")
	_move_enemy(_fixture[5], _fixture_ground_position(5))
	_move_enemy(_fixture[6], _fixture_ground_position(6))


func _test_wild_rush_contract() -> void:
	_move_enemy(_fixture[0], Vector2(1.20, 0.0))
	_move_enemy(_fixture[1], Vector2(-1.20, 0.0))
	_move_enemy(_fixture[2], Vector2(3.00, 0.0))
	_move_enemy(_fixture[3], Vector2(3.00, 2.00))
	locked_target = _fixture[0]
	manual_target_lock = true
	_expect(
		_select_wild_rush_target() == _fixture[0],
		"valid locked wild-rush target did not have absolute priority",
	)
	_fixture[0].set_meta("immovable", true)
	_expect(
		_select_wild_rush_target() == null,
		"ineligible locked wild-rush target incorrectly fell back",
	)
	_fixture[0].set_meta("immovable", false)
	locked_target = null
	manual_target_lock = false
	_expect(
		_select_wild_rush_target() == _fixture[0],
		"equal-distance no-lock wild-rush order changed",
	)
	_move_enemy(_fixture[0], Vector2(1.50, 0.0))
	_move_enemy(_fixture[1], Vector2(-1.50, 0.0))
	_move_enemy(_fixture[7], Vector2(0.0, 1.50))
	_move_enemy(_fixture[8], Vector2(0.0, -1.50))
	_expect(
		_select_wild_rush_target() == null,
		"wild-rush 1.5 GU boundary became inclusive",
	)
	_move_enemy(_fixture[0], Vector2(1.20, 0.0))
	_move_enemy(_fixture[1], Vector2(-1.20, 0.0))
	_move_enemy(_fixture[7], _fixture_ground_position(7))
	_move_enemy(_fixture[8], _fixture_ground_position(8))
	locked_target = _fixture[0]
	_expect(
		_wild_rush_has_dynamic_blocker(
			_fixture[0],
			Vector2(1.20, 0.0),
			Vector2.RIGHT,
		),
		"dynamic blocker in the 3 GU corridor was missed",
	)
	_move_enemy(_fixture[2], Vector2(3.00, 2.00))
	_expect(
		not _wild_rush_has_dynamic_blocker(
			_fixture[0],
			Vector2(1.20, 0.0),
			Vector2.RIGHT,
		),
		"lateral actor outside the rush corridor blocked the charge",
	)
	_move_enemy(_fixture[2], _fixture_ground_position(2))
	_move_enemy(_fixture[3], _fixture_ground_position(3))
	locked_target = null
	manual_target_lock = false


func _test_canonical_context_and_summon_occupancy() -> void:
	_skill_cast_target = _fixture[0]
	magic_locked_target = _fixture[0]
	var definition := {
		"skill_id": "wizard.hellfire",
		"class": "wizard",
		"target": {"relation": "hostile", "mode": "single"},
		"geometry": {"shape": "single", "maximum_range_gu": 12.0},
	}
	var context: Dictionary = _canonical_target_context(
		definition,
		player.global_position,
		Vector2.RIGHT,
		false,
		"r3x6:context",
	)
	var raw_targets: Array = context.get("targets", [])
	var context_ids: Array[int] = []
	for raw_target: Variant in raw_targets:
		if raw_target is Dictionary:
			context_ids.append(int((raw_target as Dictionary).get("target_instance_id", 0)))
	var expected_context_ids: Array[int] = []
	for enemy: EnemyActor in _current_group_enemies():
		if GroundUnitSpace.distance_gu(
				Vector2.ZERO,
				_canonical_screen_px_to_ground_gu(enemy.global_position),
			) <= SpellTargetLockPolicy.LOCK_RANGE_GU + GroundUnitSpace.EPSILON_GU:
			expected_context_ids.append(enemy.get_instance_id())
	_expect(
		context_ids == expected_context_ids,
		"canonical hostile context target order differs from group authority",
	)
	var query_count_before := _combat_spatial_index.index_enemy_node_aabb_query_count
	var occupied := _canonical_summon_position_is_valid(Vector2(2.0, 0.0), 0.4, null)
	_expect(not occupied, "summon occupancy ignored a nearby indexed enemy")
	_expect(
		_combat_spatial_index.index_enemy_node_aabb_query_count > query_count_before,
		"summon occupancy did not use the enemy spatial broadphase",
	)
	_skill_cast_target = null
	magic_locked_target = null


func _test_highlight_delta() -> void:
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	RuntimeDiagnostics.refresh_performance_gate()
	RuntimeDiagnostics.reset_performance_window()
	_active_target_domain_magic = false
	locked_target = _fixture[0]
	magic_locked_target = null
	_refresh_target_highlights()
	var first_count := RuntimeDiagnostics.performance_counter(&"actor_redraw_requests")
	_refresh_target_highlights()
	_expect(
		RuntimeDiagnostics.performance_counter(&"actor_redraw_requests") == first_count,
		"same target refresh caused duplicate highlight redraws",
	)
	locked_target = _fixture[1]
	_refresh_target_highlights()
	var switched_count := RuntimeDiagnostics.performance_counter(&"actor_redraw_requests")
	_expect(switched_count >= first_count + 2, "target switch did not update both highlight deltas")
	_refresh_target_highlights()
	_expect(
		RuntimeDiagnostics.performance_counter(&"actor_redraw_requests") == switched_count,
		"unchanged switched target caused duplicate redraws",
	)
	locked_target = null
	_refresh_target_highlights()
	_expect(
		RuntimeDiagnostics.performance_counter(&"actor_redraw_requests") == switched_count + 1,
		"clearing target did not clear only the presented actor",
	)


func _test_fail_closed_without_index() -> void:
	var saved_index := _combat_spatial_index
	_combat_spatial_index = null
	var before_reason := projection_rejection_reason
	_expect(
		_attack_lock_candidates().is_empty()
			and projection_rejection_reason == &"target_spatial_index_unavailable",
		"missing combat index did not fail closed for target lock",
	)
	var teleport_origin := player.global_position
	_expect(
		_find_valid_random_teleport_position(teleport_origin) == teleport_origin,
		"teleport tried to use a missing target index",
	)
	_combat_spatial_index = saved_index
	projection_rejection_reason = before_reason


func _test_death_unregister_and_map_clear() -> void:
	var victim := _fixture[94]
	var registered_before := _combat_spatial_index.registered_actor_count()
	victim.take_damage(victim.current_hp)
	_expect(victim.current_hp == 0 and victim._death_pending, "lethal target did not enter death_pending")
	_expect(
		_combat_spatial_index.registered_actor_count() == registered_before - 1,
		"death boundary did not unregister the target immediately",
	)
	_expect(
		not _query_aabb(Rect2(Vector2(30.0, 30.0), Vector2(20.0, 20.0))).has(victim),
		"dead target remained a spatial candidate",
	)
	await get_tree().process_frame
	var replacement := _make_replacement_enemy(Vector2(36.0, 36.0), 200)
	_fixture.append(replacement)
	_expect(
		_combat_spatial_index.registered_actor_count() == registered_before,
		"replacement actor did not register after death/unregister",
	)
	_combat_spatial_index.clear_map(RUNTIME_MAP_ID)
	_expect(_query_aabb(Rect2(Vector2(-6.0, -6.0), Vector2(18.0, 18.0))).is_empty(), "clear_map leaked candidates")
	for enemy: EnemyActor in _current_group_enemies():
		_register_enemy(enemy)
	_expect(
		_combat_spatial_index.registered_actor_count() == _current_group_enemies().size(),
		"map clear/re-register did not preserve live actor set",
	)


func _make_replacement_enemy(ground_position_gu: Vector2, serial: int) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.name = "R3X6Replacement"
	enemy.setup(
		{
			"monster_id": 38,
			"name": enemy.name,
			"hp": 1000,
			"attackMin": 1,
			"attackMax": 1,
			"level": 1,
		},
		player,
		false,
	)
	enemy.primary_target = null
	enemy.set_meta("r3x6_fixture_id", serial)
	enemy.set_meta("spawn_serial", serial)
	enemy.set_meta("zone_generation", _zone_generation)
	enemy.configure_runtime_map_projection(
		RUNTIME_MAP_ID,
		Callable(self, "_canonical_ground_gu_to_screen_px"),
		Callable(self, "_canonical_screen_px_to_ground_gu"),
	)
	enemy.configure_spatial_index(_combat_spatial_index, serial)
	enemy.global_position = _canonical_ground_gu_to_screen_px(ground_position_gu)
	add_child(enemy)
	enemy.set_process(false)
	enemy.set_physics_process(false)
	enemy.set_combat_position(enemy.global_position, &"r3x6_replacement_spawn")
	_combat_spatial_index.register(
		serial,
		RUNTIME_MAP_ID,
		ground_position_gu,
		enemy.combat_radius_gu,
		serial,
		enemy,
		Callable(enemy, "spatial_index_position"),
	)
	return enemy


func _cleanup_fixture() -> void:
	if _combat_spatial_index != null:
		_combat_spatial_index.clear_map(RUNTIME_MAP_ID)
	for enemy: EnemyActor in _fixture:
		if is_instance_valid(enemy):
			enemy.free()
	_fixture.clear()
	if is_instance_valid(player):
		player.free()
	player = null
	if is_instance_valid(background):
		background.free()
	background = null
	_combat_spatial_index = null


func _function_body(source: String, function_name: String) -> String:
	var start := source.find("func %s" % function_name)
	if start < 0:
		return ""
	var body_start := source.find("\n", start)
	if body_start < 0:
		return ""
	var next_function := source.find("\nfunc ", body_start + 1)
	if next_function < 0:
		next_function = source.length()
	return source.substr(body_start + 1, next_function - body_start - 1)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	_failure_messages.append(message)
	return false
