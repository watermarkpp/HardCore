extends Node

## HC-MONSTER-COMBAT-R3 W1: the real admission point allocates the parent
## action identity BEFORE the release record exists, and the record, the
## presentation and the audio stream all carry that one identity.

var _failures: Array[String] = []

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const SpatialIndexScript := preload("res://scripts/runtime_combat_spatial_index.gd")
const OpenTerrainFixture := preload("res://tests/helpers/monster_open_terrain_test_fixture.gd")

const MAP_ID := 9001

var _index: SpatialIndexScript
var _serial := 1


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(screen_px: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(screen_px)


func _expect(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
		printerr("R3_PARENT_RELEASE_IDENTITY: ", message)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = _ground_to_screen(Vector2(16.5, 16.5))
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(24), player, false)
	_index = SpatialIndexScript.new()
	var serial := _serial
	_serial += 1
	enemy.configure_runtime_map_projection(
		MAP_ID,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground")
	)
	enemy.configure_terrain_navigation_context(OpenTerrainFixture.build(MAP_ID))
	enemy.configure_spatial_index(_index, serial)
	var ground_position_gu := Vector2(16.5, 16.5) + Vector2(0, 1.499)
	enemy.set_combat_position(_ground_to_screen(ground_position_gu), &"r3_parent_identity_spawn")
	add_child(enemy)
	enemy.set_physics_process(false)
	_index.register(serial, MAP_ID, ground_position_gu, enemy.combat_radius_gu, serial, enemy)
	enemy.set_meta("spawn_position", enemy.global_position)
	enemy.set_meta("safe_zones", [])
	enemy.target = player
	await get_tree().process_frame
	enemy._refresh_target_focus()
	# Fixture: a combat-ready identity (no inherited cooldown, no pending pose).
	enemy._attack_timer = 0.0
	enemy._hc_m30_attack_pose_remaining = 0.0
	enemy._pending_attack_time = -1.0
	enemy._hc_last_start_tick = -1
	assert(enemy.combat_enabled, "fixture: identity 24 must be combat enabled")

	# Real admission through the production HC entry with a live target.
	var game_time_before: float = enemy._combat_action_time_s
	enemy._combat_action_time_s = 7.5
	var started: bool = enemy._hc_try_start(player)
	_expect(started, "admission must start against a live adjacent target")
	if not started:
		get_tree().quit(1)
		return

	var record: Dictionary = enemy._last_hc_release_record
	_expect(not record.is_empty(), "admission must archive its release record")
	if record.is_empty():
		get_tree().quit(1)
		return
	var parent_id: int = int(record.get("parent_action_id", -1))
	_expect(parent_id > 0, "release record must carry a parent action id")
	_expect(
		parent_id == enemy._attack_logic_serial,
		"record parent id %d must equal the enemy serial %d"
			% [parent_id, enemy._attack_logic_serial],
	)
	_expect(
		int(record.get("parent_source_life", -2)) == enemy._attack_action_source_life,
		"record parent source life must match the allocated action",
	)
	_expect(
		int(record.get("parent_generation", -2)) == enemy._attack_action_generation,
		"record parent generation must match the allocated action",
	)
	_expect(
		absf(float(record.get("parent_start_game_time_s", -1.0)) - 7.5) < 0.0001,
		"record start game time must be the combat clock at admission",
	)
	_expect(
		enemy._attack_action_start_time_s >= game_time_before,
		"action start must not predate the combat clock",
	)
	_expect(
		enemy.visual.current_attack_action_id() == parent_id,
		"presentation must expose the same parent action id",
	)
	_expect(
		enemy._audio_attack_sequence == parent_id,
		"audio stream must bind the same parent action id",
	)
	_expect(
		enemy.visual._combat_clock_s.is_valid(),
		"presentation must be bound to the owner combat clock",
	)
	# One identity owns both the pending record and the visible action.
	_expect(
		enemy.visual._attack_action_id == int(record.get("parent_action_id", 0)),
		"visual action id and release parent id must be one identity",
	)

	enemy.queue_free()
	player.queue_free()
	if _failures.is_empty():
		print("R3_PARENT_RELEASE_IDENTITY_PASS")
	get_tree().quit(0 if _failures.is_empty() else 1)
