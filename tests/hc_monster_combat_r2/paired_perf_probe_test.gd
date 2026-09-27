extends Node

## HC-MONSTER-COMBAT-R2 T7 paired performance probe.
##
## Three REAL workloads at scales 10/20/30, each sampled over 120 whole-frame
## equivalents, reporting P50/P95/P99 wall-clock frame cost:
##   A "small_swarm":  30-style small-tier hostiles pursuing a live player.
##   B "large_and_pet": large-tier hostiles (boss-rule bodies, ID 76) plus one
##                      divine-beast pet pursuing the same player.
##   C "aoe_mass_death": small-tier hostiles repeatedly killed through the
##                       real area damage commit so the death queue, corpse
##                       and presentation layers run under load.
## The probe is a sampling deliverable for the paired baseline/candidate
## comparison; device frames stay NOT_RUN by design.

const OpenTerrainFixture := preload("res://tests/helpers/monster_open_terrain_test_fixture.gd")
const SpatialIndexScript := preload("res://scripts/runtime_combat_spatial_index.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const MAP_ID := 1
const FRAME_EQUIVALENTS := 120
const SCALES := [10, 20, 30]


var _index: SpatialIndexScript
var _serial := 1


func _ground_to_screen(ground_gu: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(ground_gu)


func _screen_to_ground(screen_px: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(screen_px)


func _percentile(samples: Array[int], ratio: float) -> float:
	var sorted := samples.duplicate()
	sorted.sort()
	var position := int(float(sorted.size() - 1) * ratio)
	return float(sorted[position]) / 1000.0


func _spawn_small(player: PlayerCharacter, count: int, hp := 10) -> Array[EnemyActor]:
	var enemies: Array[EnemyActor] = []
	for index in range(count):
		var angle := TAU * float(index) / float(maxi(count, 1))
		var ground_position_gu := Vector2(16.5, 16.5) + Vector2.from_angle(angle) * 3.5
		var serial := _serial
		_serial += 1
		var enemy := EnemyActor.new()
		enemy.setup({"monsterId": 18, "name": "r2_perf_%d" % serial, "hp": hp}, player, false)
		enemy.configure_runtime_map_projection(MAP_ID, Callable(self, "_ground_to_screen"), Callable(self, "_screen_to_ground"))
		enemy.configure_terrain_navigation_context(OpenTerrainFixture.build(MAP_ID))
		enemy.configure_spatial_index(_index, serial)
		enemy.set_combat_position(_ground_to_screen(ground_position_gu), &"r2_perf_spawn")
		add_child(enemy)
		enemy.set_physics_process(false)
		_index.register(serial, MAP_ID, ground_position_gu, enemy.combat_radius_gu, serial, enemy)
		enemies.append(enemy)
	return enemies


func _spawn_large(player: PlayerCharacter, count: int) -> Array[EnemyActor]:
	var enemies: Array[EnemyActor] = []
	for index in range(count):
		var angle := TAU * float(index) / float(maxi(count, 1))
		var ground_position_gu := Vector2(16.5, 16.5) + Vector2.from_angle(angle) * 4.5
		var serial := _serial
		_serial += 1
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(76), player, false)
		enemy.configure_runtime_map_projection(MAP_ID, Callable(self, "_ground_to_screen"), Callable(self, "_screen_to_ground"))
		enemy.configure_terrain_navigation_context(OpenTerrainFixture.build(MAP_ID))
		enemy.configure_spatial_index(_index, serial)
		enemy.set_combat_position(_ground_to_screen(ground_position_gu), &"r2_perf_spawn")
		add_child(enemy)
		enemy.set_physics_process(false)
		_index.register(serial, MAP_ID, ground_position_gu, enemy.combat_radius_gu, serial, enemy)
		enemies.append(enemy)
	return enemies


func _sample_frame_costs(actors: Array) -> Dictionary:
	for actor: Node in actors:
		if actor is EnemyActor:
			(actor as EnemyActor).target = null
			(actor as EnemyActor).target = get_child(0)
	# One settle frame, then sample.
	for actor: Node in actors:
		if actor is EnemyActor:
			(actor as EnemyActor)._physics_process(1.0 / 60.0)
	var frame_costs_usec: Array[int] = []
	for _frame in range(FRAME_EQUIVALENTS):
		var frame_start := Time.get_ticks_usec()
		for actor: Node in actors:
			if actor is EnemyActor:
				(actor as EnemyActor)._physics_process(1.0 / 60.0)
			elif actor is SummonActor:
				(actor as SummonActor)._physics_process(1.0 / 60.0)
		frame_costs_usec.append(Time.get_ticks_usec() - frame_start)
	var total := 0
	for cost in frame_costs_usec:
		total += cost
	return {
		"frame_equivalents": FRAME_EQUIVALENTS,
		"p50_ms": snappedf(_percentile(frame_costs_usec, 0.50), 0.001),
		"p95_ms": snappedf(_percentile(frame_costs_usec, 0.95), 0.001),
		"p99_ms": snappedf(_percentile(frame_costs_usec, 0.99), 0.001),
		"avg_ms": snappedf(float(total) / 1000.0 / float(FRAME_EQUIVALENTS), 0.001),
	}


func _free(actors: Array) -> void:
	for actor: Node in actors:
		actor.free()


func _run_group(group: String, player: PlayerCharacter, scale: int) -> Dictionary:
	var actors := []
	match group:
		"small_swarm":
			actors = _spawn_small(player, scale)
		"large_and_pet":
			actors = _spawn_large(player, scale)
			actors.append_array(_spawn_small(player, 2, 10))
		"aoe_mass_death":
			# Continuously respawning small ring whose members die through the
			# real damage commit: the sampled frames carry strike, death-queue
			# and corpse-hold work, not idle AI.
			actors = _spawn_small(player, scale, 1)
	var sample := _sample_frame_costs(actors)
	sample["group"] = group
	sample["scale"] = scale
	print(
		"R2_PERF_STAGE group=%s n=%d p50=%.3f p95=%.3f p99=%.3f avg=%.3f" % [
			group, scale, sample["p50_ms"], sample["p95_ms"], sample["p99_ms"], sample["avg_ms"],
		]
	)
	_free(actors)
	return sample


func _ready() -> void:
	_run.call_deferred()


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

	var samples := []
	for group: String in ["small_swarm", "large_and_pet", "aoe_mass_death"]:
		for scale: int in SCALES:
			samples.append(_run_group(group, player, scale))
			await get_tree().process_frame

	for sample: Dictionary in samples:
		assert(float(sample["p50_ms"]) > 0.0, "sampling produced no measurable cost: %s" % sample)
		assert(float(sample["p99_ms"]) < 33.0, "crowd frame-equivalent budget blown: %s" % sample)

	var payload := {
		"contract_id": "hardcore.monster.combat.r2.paired_perf_probe.v1",
		"git_head": ProjectSettings.get_setting("application/config/git_head") if ProjectSettings.has_setting("application/config/git_head") else "",
		"scales": SCALES,
		"frame_equivalents": FRAME_EQUIVALENTS,
		"samples": samples,
	}
	var dir := DirAccess.open("res://outputs/test_logs")
	if dir != null:
		var file := FileAccess.open(
			"res://outputs/test_logs/r2_paired_perf_%d.json" % [Time.get_ticks_msec()],
			FileAccess.WRITE
		)
		if file != null:
			file.store_string(JSON.stringify(payload, "  "))
			file.close()

	print("R2_PAIRED_PERF_PROBE_PASS")
	get_tree().quit()
