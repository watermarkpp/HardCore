extends Node

## M30-R4 acceptance: 8-direction 2.0 -> 1.5 GU short steps through the real
## melee pipeline. Judged on walk-state phase continuity: the walk phase may
## wrap only after ~one full cycle_gu of accumulated real distance; a walk
## frame 0 is legal only while phase < 1/frame_count. Attack-pose samples
## (state != walk) are excluded because the attack animation legitimately
## starts at its own frame 0 on the same physics tick as a movement settle.
## Directions whose 2 GU corridor is authored terrain barely move and are
## counted as skipped (at least five directions must walk).

const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")

const MONSTER_ID := 64
const DIRECTIONS := 8
const PROBE_TICKS := 480

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


func _cycle_estimate(monster: EnemyActor) -> float:
	var snapshot: Dictionary = monster.visual.hc_m30_motion_snapshot()
	return maxf(0.4, float(snapshot["reference_cycle_gu"]))


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
	var skipped_blocked := 0
	for direction_index: int in range(DIRECTIONS):
		var angle := TAU * float(direction_index) / float(DIRECTIONS)
		var start_ground: Vector2 = center_ground + Vector2.RIGHT.rotated(angle) * 2.0
		var start_px: Vector2 = game._canonical_ground_gu_to_screen_px(start_ground)
		var monster: EnemyActor = game._spawn_enemy(
			GameData.get_monster_by_id(MONSTER_ID),
			start_px,
			false,
			-1.0,
			{"respawn_enabled": false, "spawn_slot_id": "test:m30_steps_%d" % direction_index},
		)
		check(monster != null and monster.monster_id == MONSTER_ID, "direction %d must spawn monster 64" % direction_index)
		if monster == null:
			continue
		preferred = monster._hc_preferred(caster)
		var walk_phases: Array[float] = []
		var walk_distances: Array[float] = []
		var walk_frames: Array[int] = []
		var previous_ground: Vector2 = _ground_of(monster)
		var moving := false
		var attack_samples := 0
		for tick: int in range(PROBE_TICKS):
			await get_tree().physics_frame
			if not is_instance_valid(monster):
				break
			var ground: Vector2 = _ground_of(monster)
			if ground == Vector2.INF:
				continue
			var moved: float = ground.distance_to(previous_ground)
			previous_ground = ground
			if ground.distance_to(center_ground) <= preferred + 0.05:
				break
			if moved > 0.001:
				moving = true
				var snapshot: Dictionary = monster.visual.hc_m30_motion_snapshot()
				if str(snapshot["state"]) == "walk":
					walk_phases.append(float(snapshot["walk_phase"]))
					walk_distances.append(float(snapshot["actual_distance_gu"]))
					walk_frames.append(int(snapshot["frame"]))
				else:
					attack_samples += 1
			if tick == PROBE_TICKS / 2 and not moving:
				break
		var total_gu: float = float(monster.visual.hc_m30_motion_snapshot()["actual_distance_gu"])
		if not moving or total_gu < 0.35:
			skipped_blocked += 1
			evidence.append(
				"dir=%d authored terrain limits the approach (moved=%.3f GU), skipped" % [direction_index, total_gu]
			)
			monster.take_damage(999999, caster, {"source": "m30_steps_test"})
			monster.queue_free()
			await get_tree().process_frame
			continue
		var reached: float = _ground_of(monster).distance_to(center_ground)
		check(
			reached <= preferred + 0.1,
			"direction %d must reach preferred contact (reached=%.3f preferred=%.3f)" % [direction_index, reached, preferred],
		)
		# Phase continuity: a decrease is only legal as a cycle wrap, which
		# must land on a multiple of cycle_gu in accumulated distance (within
		# one sample's movement, ~0.1 GU).
		var phase_violations := 0
		var cycle_gu: float = _cycle_estimate(monster)
		for sample_index: int in range(1, walk_phases.size()):
			var drop: float = walk_phases[sample_index - 1] - walk_phases[sample_index]
			if drop > 0.05:
				var remainder: float = fmod(walk_distances[sample_index], cycle_gu)
				if remainder > 0.12 and remainder < cycle_gu - 0.12:
					phase_violations += 1
		check(phase_violations == 0, "direction %d walk phase must not reset without a full cycle" % direction_index)
		# Walk frame 0 is legal only while phase < 1/frame_count.
		var frame_violations := 0
		for sample_index: int in range(walk_frames.size()):
			if walk_frames[sample_index] == 0 and walk_phases[sample_index] >= 1.0 / 6.0:
				frame_violations += 1
		check(frame_violations == 0, "direction %d walk animation must not replay frame 0 mid-cycle" % direction_index)
		evidence.append(
			"dir=%d samples=%d attack_samples=%d phases=[%.3f..%.3f] total_gu=%.3f reached=%.3f preferred=%.3f cycle=%.3f"
			% [direction_index, walk_phases.size(), attack_samples,
				walk_phases[0] if walk_phases.size() > 0 else -1.0,
				walk_phases[walk_phases.size() - 1] if walk_phases.size() > 0 else -1.0,
				total_gu, reached, preferred, cycle_gu]
		)
		monster.take_damage(999999, caster, {"source": "m30_steps_test"})
		monster.queue_free()
		await get_tree().process_frame
	check(skipped_blocked <= 3, "at least five directions must have an open corridor (skipped=%d)" % skipped_blocked)
	print("M30_EIGHT_DIRECTION_STEPS_%s checks=%d failures=%d preferred=%.3f skipped=%d" % [
		"PASS" if failures == 0 else "FAIL", checks, failures, preferred, skipped_blocked,
	])
	for line: String in evidence:
		print("M30STEPS_EVIDENCE " + line)
	get_tree().quit(0 if failures == 0 else 1)


func _ready() -> void:
	_run.call_deferred()
