extends Node

## HC-MONSTER-COMBAT-R1 Task 9: desktop headless crowd-scale sampling probe.
##
## Spawns 10/20/30 real pursuing monsters around a live player and drives full
## per-frame AI+motion equivalents, sampling the wall-clock cost of a whole
## frame-equivalent per scale step. This is a sampling deliverable, not a
## device benchmark: device frames are NOT_RUN by design (no emulator/APK in
## this package). Budgets are deliberately loose full-frame guards; the sampled
## numbers go into PERFORMANCE_RESULTS verbatim.


const OpenTerrainFixture := preload("res://tests/helpers/monster_open_terrain_test_fixture.gd")
const SpatialIndexScript := preload("res://scripts/runtime_combat_spatial_index.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const MAP_ID := 1
const FRAME_EQUIVALENTS := 60
const SCALES := [10, 20, 30]


var _index: SpatialIndexScript


func _ready() -> void:
	_run.call_deferred()


func _ground_to_screen(ground_gu: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(ground_gu)


func _screen_to_ground(screen_px: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(screen_px)


func _spawn_ring(player: PlayerCharacter, count: int, start_serial: int) -> Array[EnemyActor]:
	var enemies: Array[EnemyActor] = []
	for index in range(count):
		var angle := TAU * float(index) / float(maxi(count, 1))
		var ground_position_gu := Vector2(16.5, 16.5) + Vector2.from_angle(angle) * 3.5
		var position: Vector2 = _ground_to_screen(ground_position_gu)
		var serial := start_serial + index
		var enemy := EnemyActor.new()
		enemy.setup({"monsterId": 18, "name": "r1_perf_%d" % serial, "hp": 10}, player, false)
		enemy.configure_runtime_map_projection(MAP_ID, Callable(self, "_ground_to_screen"), Callable(self, "_screen_to_ground"))
		enemy.configure_terrain_navigation_context(OpenTerrainFixture.build(MAP_ID))
		enemy.configure_spatial_index(_index, serial)
		enemy.set_combat_position(position, &"r1_perf_spawn")
		add_child(enemy)
		enemy.set_physics_process(false)
		_index.register(serial, MAP_ID, ground_position_gu, enemy.combat_radius_gu, serial, enemy)
		enemies.append(enemy)
	return enemies


func _sample_scale(player: PlayerCharacter, count: int, start_serial: int) -> Dictionary:
	var enemies := _spawn_ring(player, count, start_serial)
	# Deterministic pursuing workload: the shared target grid throttles idle
	# acquisition (a separate correctness concern), so the probe pins the
	# pursuit target directly, mirroring the dense stage of the crowd test.
	for enemy: EnemyActor in enemies:
		enemy.target = player
	# Let one frame settle the pursuit state, then sample.
	for enemy: EnemyActor in enemies:
		enemy._physics_process(1.0 / 60.0)
	var frame_costs_usec: Array[int] = []
	for frame in range(FRAME_EQUIVALENTS):
		var frame_start := Time.get_ticks_usec()
		for enemy: EnemyActor in enemies:
			enemy._physics_process(1.0 / 60.0)
		frame_costs_usec.append(Time.get_ticks_usec() - frame_start)
	var total := 0
	var max_cost := 0
	for cost in frame_costs_usec:
		total += cost
		max_cost = maxi(max_cost, cost)
	var pursuing := 0
	for enemy: EnemyActor in enemies:
		if enemy.target == player:
			pursuing += 1
	for enemy: EnemyActor in enemies:
		enemy.free()
	var avg_ms := float(total) / 1000.0 / float(FRAME_EQUIVALENTS)
	var max_ms := float(max_cost) / 1000.0
	var result := {
		"scale": count,
		"frame_equivalents": FRAME_EQUIVALENTS,
		"pursuing_targets": pursuing,
		"avg_frame_equivalent_ms": snappedf(avg_ms, 0.001),
		"max_frame_equivalent_ms": snappedf(max_ms, 0.001),
	}
	print(
		"HC_PERF_STAGE n=%d pursuing=%d avg_frame_ms=%.3f max_frame_ms=%.3f" % [
			count, pursuing, avg_ms, max_ms,
		]
	)
	return result


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_index = SpatialIndexScript.new()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.current_hp = 1000000
	player.max_hp = 1000000
	player.global_position = _ground_to_screen(Vector2(16.5, 16.5))

	var samples: Array = []
	var serial := 1
	for scale: int in SCALES:
		samples.append(_sample_scale(player, scale, serial))
		serial += scale * 4
		await get_tree().process_frame

	for sample: Dictionary in samples:
		assert(int(sample["pursuing_targets"]) >= int(sample["scale"]) / 2, "sampling lost target acquisition: %s" % sample)
		assert(float(sample["avg_frame_equivalent_ms"]) > 0.0, "sampling produced no measurable cost")
		# Loose full-frame guard: a whole 30-monster frame-equivalent must stay
		# inside one 33 ms frame on the desktop runner. This is a regression
		# guard, not a device claim.
		assert(float(sample["avg_frame_equivalent_ms"]) < 33.0, "crowd frame-equivalent budget blown: %s" % sample)

	print("HC_MONSTER_CROWD_SCALE_PERF_PASS")
	get_tree().quit()
