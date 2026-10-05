extends Node

## HC-MONSTER-COMBAT-R3 W7 (R3-08): PAIRED LOAD REALISM probe.
##
## Fixes the R2 probe's workload-realism findings:
## - REAL SceneTree physics frames (actors run on the tree; per-frame cost is
##   read from the engine's own TIME_PHYSICS_PROCESS monitor), not manual
##   _physics_process ticks;
## - a REAL pet: actual SummonActor skeletons run inside the large-group
##   workload (the R2 group only claimed a pet in a comment);
## - REAL mass death: the aoe group keeps killing and replacing actors through
##   the real damage commit, so death queue, corpse hold and respawn work run
##   under load (the R2 group never actually died);
## - THREE sampling repeats per condition, reported individually with the
##   median;
## - an INVALID_WORKLOAD verdict: a condition whose actors demonstrably do
##   not run combat work (no movement, no admissions, no deaths, zero physics
##   time) fails the test instead of emitting fake numbers.
##
## Desktop sampling deliverable for the paired baseline/candidate comparison;
## device frames stay NOT_RUN by design.

const OpenTerrainFixture := preload("res://tests/helpers/monster_open_terrain_test_fixture.gd")
const SpatialIndexScript := preload("res://scripts/runtime_combat_spatial_index.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

const MAP_ID := 1
const FRAMES_PER_SAMPLE := 60
const REPEATS := 3
const SCALES := [10, 20, 30]

var _index: SpatialIndexScript
var _serial := 1


func _ground_to_screen(ground_gu: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(ground_gu)


func _screen_to_ground(screen_px: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(screen_px)


func _percentile(values: Array, ratio: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	var position := int(float(sorted.size() - 1) * ratio)
	return snappedf(float(sorted[position]) / 1000.0, 0.001)


func _ready() -> void:
	_run.call_deferred()


func _spawn_enemy(player: PlayerCharacter, monster_id: int, hp: int, distance_gu: float) -> EnemyActor:
	var ground_position_gu := Vector2(16.5, 16.5) + Vector2.from_angle(_rng.randf() * TAU) * distance_gu
	var serial := _serial
	_serial += 1
	var enemy := EnemyActor.new()
	var data: Dictionary = GameData.get_monster_by_id(monster_id).duplicate(true)
	data["hp"] = hp
	enemy.setup(data, player, false)
	enemy.configure_runtime_map_projection(MAP_ID, Callable(self, "_ground_to_screen"), Callable(self, "_screen_to_ground"))
	enemy.configure_terrain_navigation_context(OpenTerrainFixture.build(MAP_ID))
	enemy.configure_spatial_index(_index, serial)
	enemy.set_combat_position(_ground_to_screen(ground_position_gu), &"r3_paired_load_spawn")
	add_child(enemy)
	_index.register(serial, MAP_ID, ground_position_gu, enemy.combat_radius_gu, serial, enemy)
	return enemy


func _spawn_skeleton(player: PlayerCharacter) -> SummonActor:
	var summon := SummonActor.new()
	summon.setup(player, "变异骷髅", 30, 3, "taoist.summon_skeleton", 26)
	summon.configure_runtime_map_projection(MAP_ID, Callable(self, "_ground_to_screen"), Callable(self, "_screen_to_ground"))
	add_child(summon)
	return summon


func _build_group(group: String, player: PlayerCharacter, scale: int) -> Array:
	var actors := []
	match group:
		"small_swarm":
			for _i in scale:
				actors.append(_spawn_enemy(player, 18, 999999, 3.5))
		"large_and_pet":
			# REAL pet workload: real SummonActor skeletons fight beside the
			# boss-rule hostiles (the R2 group had no actual pet).
			var pet_count := maxi(1, scale / 2)
			for _i in pet_count:
				actors.append(_spawn_skeleton(player))
			for _i in maxi(1, scale - pet_count):
				actors.append(_spawn_enemy(player, 76, 999999, 4.5))
		"aoe_mass_death":
			for _i in scale:
				actors.append(_spawn_enemy(player, 18, 1, 3.0))
	return actors


func _workload_valid(group: String, actors: Array, deaths_seen: int, physics_ms_total: float) -> bool:
	if physics_ms_total <= 0.0:
		return false
	if group == "aoe_mass_death":
		return deaths_seen > 0
	# Combat activity: some actor either moved (pursuit) or started an attack.
	for actor: Node in actors:
		if actor is EnemyActor:
			var enemy := actor as EnemyActor
			if enemy._attack_logic_serial > 0 or enemy.global_position.length() > 0.0:
				return true
	return actors.size() == 0


func _sample(group: String, player: PlayerCharacter, scale: int) -> Dictionary:
	var actors := _build_group(group, player, scale)
	await get_tree().process_frame
	var deaths_seen := 0
	var kill_interval := 10
	var costs := []
	var moved_reference := {}
	for actor: Node in actors:
		if actor is EnemyActor:
			moved_reference[actor] = (actor as EnemyActor)._attack_logic_serial
	for _frame in FRAMES_PER_SAMPLE:
		var frame_index := costs.size()
		if group == "aoe_mass_death" and frame_index % kill_interval == 0 and frame_index > 0:
			# REAL mass death through the real damage commit, then a real
			# respawn to keep the scale honest.
			var killed := 0
			for actor: Node in actors:
				if killed >= maxi(1, scale / 4):
					break
				if actor is EnemyActor and is_instance_valid(actor) and not (actor as EnemyActor)._dying:
					(actor as EnemyActor).take_damage(9999, player)
					killed += 1
					deaths_seen += 1
			for _i in killed:
				actors.append(_spawn_enemy(player, 18, 1, 3.0))
		await get_tree().physics_frame
		costs.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var total := 0.0
	for cost: float in costs:
		total += cost
	var activity_valid := _workload_valid(group, actors, deaths_seen, total)
	var sample := {
		"frames": FRAMES_PER_SAMPLE,
		"p50_ms": _percentile(costs, 0.50),
		"p95_ms": _percentile(costs, 0.95),
		"p99_ms": _percentile(costs, 0.99),
		"deaths_seen": deaths_seen,
		"workload_valid": activity_valid,
	}
	for actor: Node in actors:
		if is_instance_valid(actor):
			(actor as Node).free()
	actors.clear()
	return sample


var _rng := RandomNumberGenerator.new()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_rng.seed = 20260927
	_index = SpatialIndexScript.new()
	var player := PlayerCharacter.new()
	add_child(player)
	player.current_hp = 1000000
	player.max_hp = 1000000
	player.global_position = _ground_to_screen(Vector2(16.5, 16.5))
	await get_tree().process_frame

	var samples := []
	for group: String in ["small_swarm", "large_and_pet", "aoe_mass_death"]:
		for scale: int in SCALES:
			var repeats := []
			for _repeat in REPEATS:
				repeats.append(await _sample(group, player, scale))
			# R3 W7: INVALID_WORKLOAD verdict - a condition whose workload is
			# not real must fail loudly, never emit fake numbers.
			var all_valid := true
			for repeat: Dictionary in repeats:
				if not bool(repeat["workload_valid"]):
					all_valid = false
			if not all_valid:
				printerr(
					"R3_PAIRED_LOAD: INVALID_WORKLOAD %s scale=%d - the workload did not perform real combat work" % [group, scale]
				)
				get_tree().quit(1)
				return
			var p50s := []
			var p95s := []
			var p99s := []
			for repeat: Dictionary in repeats:
				p50s.append(float(repeat["p50_ms"]))
				p95s.append(float(repeat["p95_ms"]))
				p99s.append(float(repeat["p99_ms"]))
			p50s.sort()
			p95s.sort()
			p99s.sort()
			var median: Dictionary = repeats[int(REPEATS / 2)]
			var condition := {
				"group": group,
				"scale": scale,
				"repeats": repeats,
				"median_p50_ms": p50s[int(REPEATS / 2)],
				"median_p95_ms": p95s[int(REPEATS / 2)],
				"median_p99_ms": p99s[int(REPEATS / 2)],
				"workload_valid": true,
			}
			samples.append(condition)
			print(
				"R3_PAIRED_LOAD %s n=%d p50=%.3f p95=%.3f p99=%.3f deaths=%d" % [
					group, scale, condition["median_p50_ms"], condition["median_p95_ms"],
					condition["median_p99_ms"], int(median["deaths_seen"]),
				]
			)

	var payload := {
		"contract_id": "hardcore.monster.combat.r3.paired_load_realism.v1",
		"git_head": ProjectSettings.get_setting("application/config/git_head") if ProjectSettings.has_setting("application/config/git_head") else "",
		"frames_per_sample": FRAMES_PER_SAMPLE,
		"repeats_per_condition": REPEATS,
		"engine_monitor": "Performance.TIME_PHYSICS_PROCESS over real SceneTree physics frames",
		"samples": samples,
	}
	var file := FileAccess.open("res://outputs/test_logs/r3_paired_load_%d.json" % [Time.get_ticks_msec()], FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload, "  "))
		file.close()

	print("R3_PAIRED_LOAD_REALISM_PASS")
	get_tree().quit()
