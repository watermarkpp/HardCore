extends Node

## Fresh production actors, real admission entry and engine physics delivery.
## No cooldown/pending/clock reset and no manual presentation starts.
const GU := preload("res://scripts/ground_unit_space.gd")
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")
const Terrain := preload("res://tests/helpers/monster_open_terrain_test_fixture.gd")
const Observer := preload("res://scripts/damage_ledger_observer.gd")
const Verifier := preload("res://tests/hc_monster_combat_r4/damage_attribution_verifier.gd")
const Body := preload("res://scripts/actor_body_policy.gd")
const MAP_ID := 9001
const CENTER := Vector2(16.5, 16.5)
var index := Index.new()
var player: PlayerCharacter
var serial := 0
var failures: Array = []
var rows: Array = []

class CollisionRevision extends Node:
	var revision := 0
	func environment_collision_revision() -> int:
		return revision

func _ready() -> void:
	_run.call_deferred()

func _ground_to_screen(p: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(p)

func _screen_to_ground(p: Vector2) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(p)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _spawn(mid: int, position: Vector2) -> EnemyActor:
	serial += 1
	var actor := EnemyActor.new()
	actor.setup(GameData.get_monster_by_id(mid), player, false)
	actor.set_meta("safe_zones", [])
	actor.set_meta("zone_generation", 1)
	actor.configure_runtime_map_projection(MAP_ID, _ground_to_screen, _screen_to_ground)
	actor.configure_terrain_navigation_context(Terrain.build(MAP_ID))
	actor.configure_spatial_index(index, serial)
	actor.set_combat_position(_ground_to_screen(position), &"d3_fixture_spawn")
	actor.set_meta("spawn_position", actor.global_position)
	add_child(actor)
	actor.set_physics_process(false)
	index.register(serial, MAP_ID, position, actor.combat_radius_gu, serial, actor)
	return actor

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	Observer.recording_enabled = true
	for mid: int in [24, 76, 238, 239]:
		for direction_index in range(8):
			var direction := Vector2.from_angle(TAU * float(direction_index) / 8.0)
			for distance: float in [1.499, 1.500, 1.501]:
				await _boundary_case(mid, direction_index, direction, distance)
	await _physical_wall_case()
	Observer.recording_enabled = false
	var evidence := {"schema": "r4_d3_real_admission_v1", "rows": rows, "failures": failures}
	FileAccess.open("res://outputs/test_logs/r4_d3_boundary.json", FileAccess.WRITE).store_string(JSON.stringify(evidence, "  "))
	player.queue_free()
	await get_tree().process_frame
	print("R4_D3_BOUNDARY_PASS" if failures.is_empty() else "R4_D3_BOUNDARY_FAIL " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _boundary_case(mid: int, direction_index: int, direction: Vector2, distance: float) -> void:
	Observer.reset()
	var actor := _spawn(mid, CENTER + direction * distance)
	var source_id := actor.get_instance_id()
	var label := "%d/direction%d/%.3f" % [mid, direction_index, distance]
	_check(actor.combat_enabled and actor.spatial_actor_runtime_id > 0, label + ":formal_actor_missing")
	var expected_radius := Body.tier_screen_radius_px(Body.TIER_SMALL if mid == 24 else Body.TIER_LARGE)
	_check(is_equal_approx(actor.collision_radius_px, expected_radius), label + ":body_radius_drift")
	var hp_before := player.current_hp
	var starts_before := actor._hc_starts
	var accepted := actor._hc_try_start(player)
	_check(accepted == (distance <= 1.500), label + ":admission_boundary_wrong reason=" + actor._hc_last_reason)
	if accepted:
		_check(actor._hc_starts == starts_before + 1, label + ":start_count_wrong")
		_check(actor.visual.current_attack_action_id() == actor._attack_logic_serial, label + ":body_parent_identity_wrong")
		_check(actor._audio_attack_sequence == actor._attack_logic_serial, label + ":audio_parent_identity_wrong")
		actor.set_physics_process(true)
		var deadline := Time.get_ticks_msec() + 1000
		while Time.get_ticks_msec() < deadline:
			await get_tree().physics_frame
			var pending_audit := Verifier.audit_releases(Observer.admissions, Observer.events, Observer.terminal_events, source_id, Observer.deliveries, Observer.overflowed)
			if pending_audit.failures.is_empty():
				break
		actor.set_physics_process(false)
		var audit := Verifier.audit_releases(Observer.admissions, Observer.events, Observer.terminal_events, source_id, Observer.deliveries, Observer.overflowed)
		_check(audit.failures.is_empty(), label + ":settlement=" + str(audit.failures))
		_check(Observer.admissions.size() == 1, label + ":extra_admission")
	else:
		_check(actor._hc_starts == starts_before and actor._attack_timer == 0.0, label + ":rejection_consumed_cooldown")
		_check(player.current_hp == hp_before and Observer.admissions.is_empty(), label + ":rejected_attack_wrote_hp")
	rows.append({"monster_id": mid, "direction": direction_index, "distance_gu": distance, "accepted": accepted,
		"reason": actor._hc_last_reason, "starts": Observer.admissions.duplicate(true), "deliveries": Observer.deliveries.duplicate(true),
		"events": Observer.events.duplicate(true), "terminals": Observer.terminal_events.duplicate(true),
		"body_radius_gu": actor.combat_radius_gu, "body_radius_px": actor.collision_radius_px,
		"body_action_id": actor.visual.current_attack_action_id(), "audio_action_id": actor._audio_attack_sequence})
	index.unregister(actor.spatial_actor_runtime_id)
	actor.free()
	await get_tree().physics_frame

func _physical_wall_case() -> void:
	Observer.reset()
	var actor := _spawn(24, CENTER + Vector2(1.4, 0.0))
	var provider := CollisionRevision.new()
	add_child(provider)
	actor.environment_blocker = provider
	var wall := StaticBody2D.new()
	wall.collision_layer = WorldSpatialRules.WORLD_MASK
	wall.collision_mask = 0
	wall.position = _ground_to_screen(CENTER + Vector2(0.7, 0.0))
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(8, 100)
	collider.shape = shape
	wall.add_child(collider)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(actor._hc_access(player, 0.0, true) == "WORLD_BLOCKED", "physical_wall:not_blocked")
	_check(not actor._hc_try_start(player) and actor._hc_starts == 0, "physical_wall:illegal_admission")
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	provider.revision += 1
	_check(actor._hc_access(player, 0.0, true) == "CLEAR", "physical_wall:removal_not_visible")
	var accepted := actor._hc_try_start(player)
	_check(accepted, "physical_wall:clear_does_not_admit")
	actor.set_physics_process(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	actor.set_physics_process(false)
	var audit := Verifier.audit_releases(Observer.admissions, Observer.events, Observer.terminal_events, actor.get_instance_id(), Observer.deliveries, Observer.overflowed)
	_check(audit.failures.is_empty(), "physical_wall:settlement=" + str(audit.failures))
	rows.append({"case": "physical_wall_remove", "accepted": accepted, "starts": Observer.admissions.duplicate(true),
		"deliveries": Observer.deliveries.duplicate(true), "events": Observer.events.duplicate(true), "terminals": Observer.terminal_events.duplicate(true)})
	index.unregister(actor.spatial_actor_runtime_id)
	actor.free()
	provider.free()
