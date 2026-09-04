extends "res://scripts/game_root.gd"

const SpatialIndex := preload("res://scripts/runtime_combat_spatial_index.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const SpellGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const RuntimeDiagnosticsScript := preload("res://scripts/runtime_diagnostics.gd")

const RUNTIME_MAP_ID := 910001
const FIXTURE_COUNT := 96
const RANDOM_PARITY_SAMPLES := 10000
const CELL_SEQUENCE: Array[Vector2i] = [Vector2i(30, 0), Vector2i(0, 30)]
const SPECIAL_GROUND_POSITIONS: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(1.0, 0.0),
	Vector2(2.0, 0.0),
	Vector2(3.99, 0.0),
	Vector2(4.01, 0.0),
	Vector2(-1.0, 0.0),
	Vector2(0.0, 1.0),
	Vector2(0.0, 2.0),
	Vector2(30.0, 0.0),
	Vector2(0.0, 30.0),
	Vector2(30.0, 3.0),
	Vector2(0.0, 33.0),
	Vector2(-3.99, 0.0),
	Vector2(-4.01, 0.0),
	Vector2(1.5, 0.6),
	Vector2(2.0, -0.6),
	Vector2(-1.5, 0.6),
	Vector2(-2.0, -0.6),
	Vector2(0.75, 1.5),
	Vector2(-0.75, 1.5),
]

var _fixture: Array[EnemyActor] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var setting_keys: Array[StringName] = [
		&"hardcore/debug/diagnostics/enabled",
		&"hardcore/debug/diagnostics/performance",
		&"hardcore/debug/diagnostics/device_lab_performance",
	]
	var previous_settings: Dictionary = {}
	for key: StringName in setting_keys:
		previous_settings[key] = ProjectSettings.get_setting(key, false)
		ProjectSettings.set_setting(key, false)
	RuntimeDiagnosticsScript.set_device_lab_performance_enabled(false)
	RuntimeDiagnosticsScript.refresh_performance_gate()
	assert(
		not RuntimeDiagnosticsScript.performance_enabled(),
		"the behavior fixture must start with every performance setting disabled",
	)
	# Device Lab/test code explicitly opens the measurement window. The ordinary
	# PlayerState test mode below must not open the group-scan escape hatch.
	RuntimeDiagnosticsScript.set_device_lab_performance_enabled(true)
	assert(RuntimeDiagnosticsScript.performance_enabled())
	RuntimeDiagnosticsScript.reset_performance_window()
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	current_map_id = RUNTIME_MAP_ID
	reference_audit_mode = false
	set_aoe_reference_fallback_for_test(false)
	assert(not _aoe_reference_fallback_allowed())

	_run_pure_index_parity_samples()
	var production := _run_real_game_root_pass(false)
	var reference := _run_real_game_root_pass(true)
	_assert_pass_parity(production, reference)
	assert(
		int(production.get("group_scans", -1)) == 0,
		"production GameRoot resolvers must not scan the enemies group",
	)
	assert(
		int(reference.get("group_scans", 0)) > 0,
		"reference pass must exercise the explicit legacy group authority",
	)

	PlayerState.test_mode = previous_test_mode
	reference_audit_mode = false
	set_aoe_reference_fallback_for_test(false)
	RuntimeDiagnosticsScript.set_device_lab_performance_enabled(false)
	for key: StringName in setting_keys:
		ProjectSettings.set_setting(key, previous_settings[key])
	RuntimeDiagnosticsScript.refresh_performance_gate()
	print(
		"GAME_ROOT_R3X2_BEHAVIOR_PARITY_PASS samples=%d production_group_scans=%d reference_group_scans=%d"
		% [
			RANDOM_PARITY_SAMPLES,
			int(production.get("group_scans", 0)),
			int(reference.get("group_scans", 0)),
		]
	)
	get_tree().quit(0)


func _run_pure_index_parity_samples() -> void:
	var index := SpatialIndex.new()
	var actors: Array[EnemyActor] = []
	for actor_index: int in range(FIXTURE_COUNT):
		var enemy := EnemyActor.new()
		enemy.current_hp = 100
		enemy.max_hp = 100
		enemy.combat_radius_gu = 0.4
		enemy.global_position = Vector2(
			float((actor_index % 16) - 8) * 1.25,
			float(int(actor_index / 16) - 3) * 1.25,
		)
		actors.append(enemy)
		index.register(
			actor_index + 1,
			RUNTIME_MAP_ID,
			enemy.global_position,
			enemy.combat_radius_gu,
			actor_index + 1,
			enemy,
		)
	var context := Snapshot.make_local_delta_context(
		Callable(GroundUnitSpace, "ground_delta_gu_to_screen_delta_px")
	)
	var random := RandomNumberGenerator.new()
	random.seed = 0x52_33_58_32
	for sample_index: int in range(RANDOM_PARITY_SAMPLES):
		var shape_index := random.randi_range(0, 3)
		var snapshot: Dictionary
		var query_is_segment := false
		var segment_start := Vector2.ZERO
		var segment_end := Vector2.ZERO
		var segment_radius := 0.0
		if shape_index == 0:
			var center := Vector2(
				random.randf_range(-12.0, 12.0),
				random.randf_range(-8.0, 8.0),
			)
			snapshot = Snapshot.create_circle(
				"r3x2.random.circle",
				"sample:%d" % sample_index,
				center,
				random.randf_range(0.2, 5.0),
				16,
				context,
			)
		elif shape_index == 1:
			var origin := Vector2(
				random.randf_range(-12.0, 12.0),
				random.randf_range(-8.0, 8.0),
			)
			var direction := Vector2(
				random.randf_range(-1.0, 1.0),
				random.randf_range(-1.0, 1.0),
			).normalized()
			if direction.length_squared() <= 0.000001:
				direction = Vector2.RIGHT
			snapshot = Snapshot.create_directed_rectangle(
				"r3x2.random.rectangle",
				"sample:%d" % sample_index,
				origin,
				direction,
				random.randf_range(0.2, 6.0),
				random.randf_range(0.2, 3.0),
				0.0,
				0.0,
				0.0,
				"",
				context,
			)
		elif shape_index == 2:
			var cells: Array[Vector2i] = [
				Vector2i(random.randi_range(-10, 10), random.randi_range(-6, 6)),
				Vector2i(random.randi_range(-10, 10), random.randi_range(-6, 6)),
			]
			snapshot = Snapshot.create_cell_union(
				"r3x2.random.cells",
				"sample:%d" % sample_index,
				Vector2.ZERO,
				cells,
				context,
			)
		else:
			query_is_segment = true
			segment_start = Vector2(
				random.randf_range(-12.0, 12.0),
				random.randf_range(-8.0, 8.0),
			)
			var segment_direction := Vector2(
				random.randf_range(-1.0, 1.0),
				random.randf_range(-1.0, 1.0),
			).normalized()
			if segment_direction.length_squared() <= 0.000001:
				segment_direction = Vector2.RIGHT
			segment_end = segment_start + segment_direction * random.randf_range(0.2, 6.0)
			segment_radius = random.randf_range(0.1, 2.0)
			snapshot = Snapshot.create_swept_capsule_path(
				"r3x2.random.swept",
				"sample:%d" % sample_index,
				segment_start,
				segment_end,
				segment_radius,
				8,
				"",
				-1,
				context,
			)
		var candidates: Array = []
		if query_is_segment:
			index.query_enemy_nodes_segment_into(
				RUNTIME_MAP_ID,
				segment_start,
				segment_end,
				segment_radius,
				candidates,
			)
		else:
			var aabb := Snapshot.ground_aabb(snapshot)
			index.query_enemy_nodes_aabb_into(
				RUNTIME_MAP_ID,
				aabb.get("bounds_ground_gu", Rect2()),
				candidates,
			)
		var broadphase_ids := _exact_fixture_ids(snapshot, candidates)
		var naive_ids := _exact_fixture_ids(snapshot, actors)
		assert(
			broadphase_ids == naive_ids,
			"random broadphase parity failed at sample %d: %s != %s"
			% [sample_index, broadphase_ids, naive_ids],
		)
	for enemy: EnemyActor in actors:
		enemy.free()
	index.clear_map(RUNTIME_MAP_ID)


func _run_real_game_root_pass(use_reference_authority: bool) -> Dictionary:
	_clear_fixture()
	reference_audit_mode = use_reference_authority
	set_aoe_reference_fallback_for_test(use_reference_authority)
	_combat_spatial_index = null if use_reference_authority else SpatialIndex.new()
	_build_fixture()
	# Ignore actor construction counters; this window covers only the six formal
	# GameRoot resolver entries and their shared damage calls.
	RuntimeDiagnosticsScript.reset_performance_window()
	_rng.seed = 0x52_33_58_32
	var origin_ground_gu := Vector2.ZERO
	var origin_screen_px := _canonical_ground_gu_to_screen_px(origin_ground_gu)
	var forward_screen_px := (
		_canonical_ground_gu_to_screen_px(Vector2.RIGHT) - origin_screen_px
	)
	var context := _canonical_snapshot_absolute_context(origin_ground_gu)
	var circle_snapshot := Snapshot.create_circle(
		"wizard.fireball",
		"r3x2:fireball",
		origin_ground_gu,
		4.0,
		32,
		context,
	)
	var apply_hit := _apply_canonical_spell_damage(
		"wizard.fireball",
		7,
		origin_screen_px,
		forward_screen_px,
		"area_damage",
		null,
		[],
		{"radius_gu": 4.0, "maximum_targets": -1},
		{},
		circle_snapshot,
	)
	var apply_ids := _fixture_ids_with_hp_change()
	var legacy_hit := _damage_enemies(
		origin_screen_px,
		forward_screen_px,
		1,
		true,
		4.0,
		false,
		"",
	)
	var line_unlimited := _line_target_ids(-1)
	var line_zero := _line_target_ids(0)
	var line_two := _line_target_ids(2)
	var union_unlimited := _cell_target_ids(-1, true)
	var union_zero := _cell_target_ids(0, true)
	var union_one := _cell_target_ids(1, true)
	var per_cell_unlimited := _cell_target_ids(-1, false)
	var per_cell_zero := _cell_target_ids(0, false)
	var per_cell_one := _cell_target_ids(1, false)
	var normal := _fixture_ids(
		_physical_primary_targets(origin_screen_px, forward_screen_px, "normal")
	)
	var fire := _fixture_ids(
		_physical_primary_targets(origin_screen_px, forward_screen_px, "fire")
	)
	var thrust_primary := _physical_primary_targets(
		origin_screen_px,
		forward_screen_px,
		"thrust",
	)
	var thrust := _fixture_ids(thrust_primary)
	var thrust_secondary := _fixture_ids(
		_thrust_secondary_targets(
			origin_screen_px,
			forward_screen_px,
			thrust_primary,
		)
	)
	var half_moon_primary := _physical_primary_targets(
		origin_screen_px,
		forward_screen_px,
		"half_moon",
	)
	var half_moon := _fixture_ids(half_moon_primary)
	var half_moon_secondary := _fixture_ids(
		_half_moon_secondary_targets(
			origin_screen_px,
			forward_screen_px,
			half_moon_primary,
		)
	)
	var hp: Array[int] = []
	var death_pending: Array[bool] = []
	for enemy: EnemyActor in _fixture:
		hp.append(enemy.current_hp)
		death_pending.append(bool(enemy._death_pending))
	var result := {
		"apply_hit": apply_hit,
		"apply_ids": apply_ids,
		"legacy_hit": legacy_hit,
		"line_unlimited": line_unlimited,
		"line_zero": line_zero,
		"line_two": line_two,
		"union_unlimited": union_unlimited,
		"union_zero": union_zero,
		"union_one": union_one,
		"per_cell_unlimited": per_cell_unlimited,
		"per_cell_zero": per_cell_zero,
		"per_cell_one": per_cell_one,
		"normal": normal,
		"fire": fire,
		"thrust": thrust,
		"thrust_secondary": thrust_secondary,
		"half_moon": half_moon,
		"half_moon_secondary": half_moon_secondary,
		"hp": hp,
		"death_pending": death_pending,
		"next_rng": _rng.randi(),
		"group_scans": RuntimeDiagnosticsScript.performance_counter(
			&"aoe_full_enemy_group_scans"
		),
	}
	_clear_fixture()
	return result


func _line_target_ids(maximum_targets: int) -> Array[int]:
	var origin_ground_gu := Vector2.ZERO
	var origin_screen_px := _canonical_ground_gu_to_screen_px(origin_ground_gu)
	var aim_ground_gu := origin_ground_gu + Vector2(5.0, 0.0)
	var direction_screen_px := (
		_canonical_ground_gu_to_screen_px(aim_ground_gu) - origin_screen_px
	)
	var strip := SpellGeometry.continuous_line_strip_ground_gu(
		origin_ground_gu,
		aim_ground_gu,
		direction_screen_px,
		5.0,
		1.0,
		"wizard.hellfire",
		"r3x2:line:%d" % maximum_targets,
		5.0,
		5.0,
		"",
		_canonical_snapshot_absolute_context(origin_ground_gu),
	)
	var snapshot: Dictionary = strip.get("skill_footprint_snapshot", {})
	return _fixture_ids(_canonical_spell_geometry_targets(
		"wizard.hellfire",
		[],
		{"maximum_targets": maximum_targets},
		strip,
		snapshot,
	))


func _cell_target_ids(maximum_targets: int, union_shape: bool) -> Array[int]:
	var origin_ground_gu := Vector2.ZERO
	var context := _canonical_snapshot_absolute_context(origin_ground_gu)
	var release_id := "r3x2:%s:%d" % ["union" if union_shape else "per_cell", maximum_targets]
	var snapshot: Dictionary
	if union_shape:
		snapshot = Snapshot.create_cell_union(
			"wizard.hell_lightning",
			release_id,
			origin_ground_gu,
			CELL_SEQUENCE,
			context,
		)
	else:
		# Raw compatibility cells deliberately sit far apart. The wide circle is
		# only the conservative union AABB; the cell loop remains authoritative.
		snapshot = Snapshot.create_circle(
			"wizard.hell_lightning",
			release_id,
			origin_ground_gu,
			32.0,
			32,
			context,
		)
	return _fixture_ids(_canonical_spell_geometry_targets(
		"wizard.hell_lightning",
		CELL_SEQUENCE,
		{
			"maximum_targets": maximum_targets,
			"radius_grid_steps": 32,
		},
		{},
		snapshot,
	))


func _build_fixture() -> void:
	_fixture.clear()
	var screen_to_ground := Callable(self, "_canonical_screen_px_to_ground_gu")
	var ground_to_screen := Callable(self, "_canonical_ground_gu_to_screen_px")
	for fixture_index: int in range(FIXTURE_COUNT):
		var enemy := EnemyActor.new()
		enemy.name = "R3X2Fixture_%03d" % fixture_index
		enemy.monster_id = 38
		enemy.monster_data = {
			"monster_id": 38,
			"anti_magic_points": 0,
			"mdefMin": 0,
			"mdefMax": 0,
		}
		enemy.display_name = enemy.name
		enemy.max_hp = 1000
		enemy.current_hp = 7 if fixture_index == 0 else 1000
		enemy.primary_target = null
		enemy.global_position = _canonical_ground_gu_to_screen_px(
			_fixture_ground_position(fixture_index)
		)
		enemy.set_process(false)
		enemy.set_physics_process(false)
		add_child(enemy)
		enemy.set_process(false)
		enemy.set_physics_process(false)
		enemy.current_hp = 7 if fixture_index == 0 else 1000
		enemy.max_hp = 1000
		enemy.combat_radius_gu = 0.4
		enemy.set_meta("r3x2_fixture_id", fixture_index)
		enemy.set_meta("spawn_serial", fixture_index + 1)
		enemy.configure_runtime_map_projection(
			RUNTIME_MAP_ID,
			ground_to_screen,
			screen_to_ground,
		)
		if _combat_spatial_index != null:
			enemy.configure_spatial_index(
				_combat_spatial_index,
				fixture_index + 1,
			)
			enemy.set_combat_position(
				enemy.global_position,
				&"r3x2_fixture_spawn",
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
	if fixture_index < SPECIAL_GROUND_POSITIONS.size():
		return SPECIAL_GROUND_POSITIONS[fixture_index]
	var column := fixture_index % 12
	var row := int(fixture_index / 12)
	return Vector2(
		float(column - 6) * 0.75,
		float(row - 4) * 0.75,
	)


func _clear_fixture() -> void:
	if _combat_spatial_index != null and is_instance_valid(_combat_spatial_index):
		_combat_spatial_index.clear_map(RUNTIME_MAP_ID)
	var children: Array[Node] = []
	for child: Node in get_children():
		if child is EnemyActor:
			children.append(child)
	for child: Node in children:
		child.free()
	_fixture.clear()


func _fixture_ids(targets: Array[EnemyActor]) -> Array[int]:
	var result: Array[int] = []
	for enemy: EnemyActor in targets:
		if is_instance_valid(enemy):
			result.append(int(enemy.get_meta("r3x2_fixture_id", -1)))
	return result


func _fixture_ids_with_hp_change() -> Array[int]:
	var result: Array[int] = []
	for fixture_index: int in range(_fixture.size()):
		var enemy := _fixture[fixture_index]
		var initial_hp := 7 if fixture_index == 0 else 1000
		if enemy.current_hp != initial_hp:
			result.append(int(enemy.get_meta("r3x2_fixture_id", -1)))
	return result


func _exact_fixture_ids(snapshot: Dictionary, candidates: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in candidates:
		if not value is EnemyActor:
			continue
		var enemy := value as EnemyActor
		if Snapshot.intersects_target_combat_footprint_ground_gu(
			snapshot,
			enemy.global_position,
			enemy.combat_radius_gu,
		):
			result.append(int(enemy.get_instance_id()))
	return result


func _assert_pass_parity(production: Dictionary, reference: Dictionary) -> void:
	for key: String in [
		"apply_hit",
		"apply_ids",
		"legacy_hit",
		"line_unlimited",
		"line_zero",
		"line_two",
		"union_unlimited",
		"union_zero",
		"union_one",
		"per_cell_unlimited",
		"per_cell_zero",
		"per_cell_one",
		"normal",
		"fire",
		"thrust",
		"thrust_secondary",
		"half_moon",
		"half_moon_secondary",
		"hp",
		"death_pending",
		"next_rng",
	]:
		assert(
			production.get(key) == reference.get(key),
			"GameRoot production/reference mismatch for %s: %s != %s"
			% [key, production.get(key), reference.get(key)],
		)
