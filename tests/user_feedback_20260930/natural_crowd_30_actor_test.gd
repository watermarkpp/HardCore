extends Node2D

## Natural 30-actor behavior contract. No target/cadence/clock/attack-timer
## writes: target acquisition and attack admission are production-owned.
const F := preload("res://tests/helpers/monster_open_terrain_test_fixture.gd")
const GU := preload("res://scripts/ground_unit_space.gd")
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")
const MAP_ID := 9010
const CENTER := Vector2(16.5, 16.5)
const ACTOR_COUNT := 30
const MAX_FRAMES := 1200

var index := Index.new()
var player: PlayerCharacter
var actors: Array[EnemyActor] = []
var failures: Array[String] = []
var serial := 0
var initial_positions: Dictionary = {}
var target_frames: Dictionary = {}
var first_move_frames: Dictionary = {}
var admission_count := 0
var actual_motion: Dictionary = {}
var previous_positions: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	await get_tree().physics_frame
	player.set_physics_process(false)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	var context := F.build(MAP_ID)
	_check(bool(context.get("valid", false)), "formal open terrain context invalid")
	for i in ACTOR_COUNT:
		var angle := TAU * float(i) / float(ACTOR_COUNT)
		var radius := 3.6 + float(i % 3) * 0.35
		var actor := _spawn_natural(context, CENTER + Vector2.from_angle(angle) * radius)
		actors.append(actor)
	await get_tree().physics_frame
	for actor: EnemyActor in actors:
		actor.set_physics_process(true)
	var target_seen := 0
	var moved := 0
	var completed_frame := -1
	for frame in MAX_FRAMES:
		await get_tree().physics_frame
		target_seen = 0
		moved = 0
		for actor: EnemyActor in actors:
			if not is_instance_valid(actor):
				continue
			if actor.target == player:
				target_seen += 1
				if not target_frames.has(actor.spatial_actor_runtime_id):
					target_frames[actor.spatial_actor_runtime_id] = frame
			var current := _ground(actor)
			var owner_id := actor.get_instance_id()
			if previous_positions.has(owner_id):
				actual_motion[owner_id] = float(actual_motion.get(owner_id, 0.0)) + current.distance_to(previous_positions[owner_id])
			previous_positions[owner_id] = current
			var initial: Vector2 = initial_positions.get(actor.get_instance_id(), current)
			if initial.distance_to(CENTER) - current.distance_to(CENTER) > 0.5:
				moved += 1
				if not first_move_frames.has(actor.spatial_actor_runtime_id):
					first_move_frames[actor.spatial_actor_runtime_id] = frame
		var ready_attackers := 0
		for actor: EnemyActor in actors:
			if is_instance_valid(actor) and actor._hc_access(player) == "CLEAR":
				ready_attackers += 1
		if _behavior_complete(target_seen, moved, ready_attackers):
			completed_frame = frame
			break
	_check(target_seen == ACTOR_COUNT, "not all actors acquired the player naturally")
	_check(player.current_hp < player.max_hp, "30-actor natural engagement produced no HP damage")
	_check(admission_count > 0, "natural damage had no production attack admission")
	var clear_attackers := 0
	var blocked_at_end := 0
	var sectors: Dictionary = {}
	var actor_rows: Array[Dictionary] = []
	for actor: EnemyActor in actors:
		if not is_instance_valid(actor):
			continue
		if actor._hc_access(player) == "CLEAR":
			clear_attackers += 1
		else:
			blocked_at_end += 1
		var delta := _ground(actor) - _ground(player)
		if delta.length_squared() > 0.01:
			sectors[int(floorf((atan2(delta.y, delta.x) + PI) / TAU * 8.0))] = true
		actor_rows.append({"runtime_actor_id": actor.spatial_actor_runtime_id,
			"actual_motion_gu": actual_motion.get(actor.get_instance_id(), 0.0),
			"target_frame": target_frames.get(actor.spatial_actor_runtime_id, -1),
			"first_move_frame": first_move_frames.get(actor.spatial_actor_runtime_id, -1),
			"position": str(_ground(actor)), "access": actor._hc_access(player),
			"reason": actor._hc_last_reason, "attack_starts": actor._hc_starts})
	_validate_progress(moved, clear_attackers, sectors)
	var evidence := {"actor_count": ACTOR_COUNT, "target_seen": target_seen,
		"moved": moved, "clear_attackers": clear_attackers,
		"approach_sectors": sectors.size(), "player_hp": player.current_hp,
		"completed_frame": completed_frame, "admission_count": admission_count,
		"blocked_at_end": blocked_at_end,
		"actors": actor_rows,
		"failures": failures}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/test_logs"))
	var file := FileAccess.open(_evidence_path(), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(evidence, "  "))
	for actor: EnemyActor in actors:
		if is_instance_valid(actor):
			index.unregister(actor.spatial_actor_runtime_id)
			actor.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame
	print(_test_marker(), "PASS" if failures.is_empty() else "FAIL", " ", evidence)
	get_tree().quit(0 if failures.is_empty() else 1)

func _behavior_complete(target_seen: int, moved: int, ready_attackers: int) -> bool:
	return target_seen == ACTOR_COUNT and moved == ACTOR_COUNT and ready_attackers >= 5 and player.current_hp < player.max_hp

func _validate_progress(moved: int, clear_attackers: int, sectors: Dictionary) -> void:
	_check(moved == ACTOR_COUNT, "an actor with an open initial approach did not move toward the player")
	_check(clear_attackers >= 5, "natural crowd did not reach five fresh legal surrounding attack positions")
	_check(sectors.size() >= 2, "natural crowd did not form multiple approach directions")

func _evidence_path() -> String:
	return "res://outputs/test_logs/natural_crowd_30_actor.json"

func _test_marker() -> String:
	return "NATURAL_CROWD_30_ACTOR_"

func _spawn_natural(context: Dictionary, ground: Vector2) -> EnemyActor:
	serial += 1
	var actor := EnemyActor.new()
	actor.setup(GameData.get_monster_by_id(89), player, false)
	actor.set_meta("safe_zones", [])
	actor.set_meta("zone_generation", 1)
	actor.configure_runtime_map_projection(MAP_ID,
		Callable(self, "_ground_to_screen"), Callable(self, "_screen_to_ground"))
	actor.configure_terrain_navigation_context(context)
	actor.configure_spatial_index(index, serial)
	actor.set_combat_position(_ground_to_screen(ground), &"natural_crowd_spawn")
	add_child(actor)
	actor.set_physics_process(false)
	index.register(serial, MAP_ID, _ground(actor), actor.combat_radius_gu, serial,
		actor, Callable(actor, "spatial_index_position"))
	actor.test_attack_admission_hook = Callable(self, "_observe_attack_admission").bind(actor)
	initial_positions[actor.get_instance_id()] = _ground(actor)
	return actor

func _observe_attack_admission(_record: Dictionary, actor: EnemyActor) -> void:
	admission_count += 1
	_check(actor._hc_access(player) == "CLEAR", "production attack admission bypassed fresh target access")

func _ground_to_screen(value: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(value)

func _screen_to_ground(value: Vector2) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(value)

func _ground(node: Node2D) -> Vector2:
	return _screen_to_ground(node.global_position)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
