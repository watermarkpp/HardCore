extends Node

const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")

const MONSTER_ID := 64
const DIRECTIONS := 8

var checks: int = 0
var failures: int = 0
var evidence: Array[String] = []


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("M30STEPS FAIL: " + label)


func _ground_of(monster: EnemyActor) -> Vector2:
	var result: Dictionary = monster.try_screen_position_px_to_ground_position_gu(monster.global_position)
	return result.get("value", Vector2.INF) if bool(result.get("success", false)) else Vector2.INF


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await Fixture.wait_for_formal_world(self, game, "m30_steps")
	var caster: PlayerCharacter = game.player
	caster.max_hp = 999999
	caster.current_hp = caster.max_hp
	var center_ground: Vector2 = Fixture.FIXTURE_GROUND_POSITION
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(center_ground))
	var preferred: float = -1.0
	for direction_index: int in range(DIRECTIONS):
		var angle := TAU * float(direction_index) / float(DIRECTIONS)
		var offset := Vector2.RIGHT.rotated(angle) * 2.0
		var start_ground: Vector2 = center_ground + offset
		var monster: EnemyActor = game._spawn_enemy(
			GameData.get_monster_by_id(MONSTER_ID),
			game._canonical_ground_gu_to_screen_px(start_ground),
			false,
			-1.0,
			{"respawn_enabled": false, "spawn_slot_id": "test:m30_steps_%d" % direction_index},
		)
		check(monster != null and monster.monster_id == MONSTER_ID, "direction %d must spawn monster 64" % direction_index)
		if monster == null:
			continue
		preferred = monster._hc_preferred(caster)
		var seen_phases: Array[float] = []
		var seen_frames: Array[int] = []
		var previous_ground: Vector2 = _ground_of(monster)
		var moving := false
		for tick: int in range(150):
			await get_tree().physics_frame
			if not is_instance_valid(monster):
				break
			var ground: Vector2 = _ground_of(monster)
			if ground == Vector2.INF:
				continue
			var moved: float = ground.distance_to(previous_ground)
			previous_ground = ground
			if moved > 0.001:
				moving = true
				var snapshot: Dictionary = monster.visual.hc_m30_motion_snapshot()
				seen_phases.append(float(snapshot["walk_phase"]))
				seen_frames.append(int(snapshot["frame"]))
			if ground != Vector2.INF and ground.distance_to(center_ground) <= preferred + 0.05:
				break
		var final_snapshot: Dictionary = monster.visual.hc_m30_motion_snapshot()
		var total_gu: float = float(final_snapshot["actual_distance_gu"])
		var reached: float = _ground_of(monster).distance_to(center_ground)
		check(moving, "direction %d must actually walk" % direction_index)
		check(
			reached <= preferred + 0.1,
			"direction %d must reach preferred contact (reached=%.3f preferred=%.3f)" % [direction_index, reached, preferred],
		)
		check(
			total_gu >= 0.35,
			"direction %d must accumulate real GU distance (%.3f)" % [direction_index, total_gu],
		)
		# One 0.5 GU approach cannot wrap a full walk cycle (cycle_gu is far
		# larger), so the walk phase must be non-decreasing while moving, and
		# frame 0 is legal only as the very first moving sample.
		var phase_monotonic := true
		for sample_index: int in range(1, seen_phases.size()):
			if seen_phases[sample_index] + 0.0001 < seen_phases[sample_index - 1]:
				phase_monotonic = false
		check(phase_monotonic, "direction %d walk phase must not reset mid-approach" % direction_index)
		var zero_after_start := 0
		for sample_index: int in range(1, seen_frames.size()):
			if seen_frames[sample_index] == 0:
				zero_after_start += 1
		check(
			zero_after_start == 0,
			"direction %d must not replay frame 0 across short steps (%d samples)" % [direction_index, seen_frames.size()],
		)
		evidence.append(
			"dir=%d phases=%s frames=%s total_gu=%.3f reached=%.3f preferred=%.3f" % [
				direction_index, str(seen_phases), str(seen_frames), total_gu, reached, preferred,
			]
		)
		monster.take_damage(999999, caster, {"source": "m30_steps_test"})
		monster.queue_free()
		await get_tree().process_frame
	print("M30_EIGHT_DIRECTION_STEPS_%s checks=%d failures=%d preferred=%.3f" % [
		"PASS" if failures == 0 else "FAIL", checks, failures, preferred,
	])
	for line: String in evidence:
		print("M30STEPS_EVIDENCE " + line)
	get_tree().quit(0 if failures == 0 else 1)


func _ready() -> void:
	_run.call_deferred()
