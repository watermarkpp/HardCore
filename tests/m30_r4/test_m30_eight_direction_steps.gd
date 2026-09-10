extends Node
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Sampler := preload("res://tests/m30_r4_r1/r1_lab_sampler.gd")
const MONSTER_ID: int = 64
var failures: int = 0
var checks: int = 0
var _sampler: Node

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("M30STEPS_R1 " + label)

func _point(monster: EnemyActor) -> Vector2:
	return monster.spatial_index_position()

func _find_open_center(probe: EnemyActor) -> Vector2:
	# Independent preflight BEFORE movement. A failed approach is never relabelled
	# as terrain. Bounded search in the formal map; no terrain or masks are edited.
	for ring: int in range(9):
		for y: int in range(-ring, ring + 1):
			for x: int in range(-ring, ring + 1):
				if maxi(absi(x), absi(y)) != ring:
					continue
				var center: Vector2 = Fixture.FIXTURE_GROUND_POSITION + Vector2(x, y) * 2.0
				if not probe._hc_point_walkable(center):
					continue
				var clear: bool = true
				for d: int in range(8):
					var direction: Vector2 = Vector2.from_angle(TAU * float(d) / 8.0)
					for i: int in range(5):
						var point: Vector2 = center + direction * (1.5 + 0.125 * float(i))
						if not probe._hc_point_walkable(point) or not probe._hc_world_between(center, point):
							clear = false
							break
					if not clear:
						break
				if clear:
					return center
	return Vector2.INF

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	MonsterVisual.set_synchronous_loading_for_tests(false)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await Fixture.wait_for_formal_world(self, game, "m30_steps_r1")
	MonsterVisual.set_synchronous_loading_for_tests(false)
	_sampler = Sampler.new()
	add_child(_sampler)
	for value: Node in get_tree().get_nodes_in_group("enemies"):
		value.queue_free()
	await _sampler.after_visual
	await _sampler.after_visual
	var caster: PlayerCharacter = game.player
	caster.max_hp = 999999
	caster.current_hp = caster.max_hp
	var probe: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(MONSTER_ID), game._canonical_ground_gu_to_screen_px(Fixture.FIXTURE_GROUND_POSITION), false, -1.0, {"respawn_enabled": false, "spawn_slot_id": "test:r1_preflight"})
	check(is_instance_valid(probe), "preflight actor must exist")
	if not is_instance_valid(probe):
		get_tree().quit(1)
		return
	probe.set_physics_process(false)
	var center: Vector2 = _find_open_center(probe)
	if not center.is_finite():
		print("M30_EIGHT_DIRECTION_STEPS_BLOCKED reason=no_verified_open_8way_fixture")
		get_tree().quit(2)
		return
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(center))
	probe.set_combat_position(game._canonical_ground_gu_to_screen_px(center + Vector2(2, 0)), &"r1_prefetch")
	var deadline: int = Time.get_ticks_msec() + 8000
	while not probe.visual.uses_final_art() and Time.get_ticks_msec() < deadline:
		await _sampler.after_visual
	check(probe.visual.uses_final_art(), "real atlas must be applied before 8way visual test")
	if not probe.visual.uses_final_art():
		get_tree().quit(1)
		return
	probe.queue_free()
	await _sampler.after_visual
	await _sampler.after_visual
	var completed: int = 0
	for d: int in range(8):
		var start: Vector2 = center + Vector2.from_angle(TAU * float(d) / 8.0) * 2.0
		var monster: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(MONSTER_ID), game._canonical_ground_gu_to_screen_px(start), false, -1.0, {"respawn_enabled": false, "spawn_slot_id": "test:r1_8way:%d" % d})
		check(is_instance_valid(monster), "direction %d must spawn" % d)
		if not is_instance_valid(monster):
			continue
		check(_point(monster).distance_to(start) < 0.015, "direction %d spawn must not be silently relocated" % d)
		var preferred: float = monster._hc_preferred(caster)
		var walks: int = 0
		var attacks: int = 0
		var last_phase: float = 0.0
		var last_distance: float = 0.0
		var reached: bool = false
		var deadline_dir: int = Time.get_ticks_msec() + 7000
		while Time.get_ticks_msec() < deadline_dir:
			await _sampler.after_visual
			if not is_instance_valid(monster):
				break
			var snap: Dictionary = monster.visual.hc_m30_motion_snapshot()
			check(int(snap["visual_process_frame"]) == Engine.get_process_frames(), "direction %d sample follows visual update" % d)
			var distance: float = float(snap["actual_distance_gu"])
			var phase: float = float(snap["walk_phase"])
			var cycle: float = float(snap["reference_cycle_gu"])
			if distance > last_distance and cycle > 0.0:
				var expected: float = fposmod(last_phase + (distance - last_distance) / cycle, 1.0)
				var error: float = absf(expected - phase)
				check(minf(error, 1.0 - error) < 0.001, "direction %d real-distance phase continuity" % d)
			elif distance == last_distance:
				check(is_equal_approx(phase, last_phase), "direction %d no phase advance at rest" % d)
			last_phase = phase
			last_distance = distance
			if str(snap["state"]) == "walk":
				walks += 1
				var count: int = MonsterAnimationPolicy.frame_count(monster.visual.active_resources, &"walk")
				check(count > 0 and int(snap["frame"]) == mini(count - 1, int(floor(phase * float(count)))), "direction %d frame matches actual atlas count" % d)
			elif str(snap["state"]) == "attack":
				attacks += 1
			if _point(monster).distance_to(center) <= preferred + 0.015:
				reached = true
				break
		check(is_instance_valid(monster) and reached, "direction %d reaches preferred distance" % d)
		check(walks >= 2, "direction %d has at least two rendered walk samples, no vacuous PASS" % d)
		check(attacks >= 1, "direction %d has readable outer attack" % d)
		if reached and walks >= 2 and attacks >= 1:
			completed += 1
		print("M30STEPS_R1_EVIDENCE dir=%d walk_samples=%d attack_samples=%d distance_gu=%.6f" % [d, walks, attacks, last_distance])
		if is_instance_valid(monster):
			monster.queue_free()
		await _sampler.after_visual
		await _sampler.after_visual
	check(completed == 8, "all eight directions must complete; no pass-by-skip")
	print("M30_EIGHT_DIRECTION_STEPS_%s completed=%d/8 checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", completed, checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _ready() -> void:
	_run.call_deferred()
