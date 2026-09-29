extends Node

## HC-MONSTER-COMBAT-R3 W6 (R3-07 acceptance): REAL combat admission census.
## No field pokes into presentation state: every round drives the real
## physics tick of a real actor (terrain + spatial index + projection), the
## real HC admission gate starts the attack, the real release record settles
## real damage on the player, and the parent identity chain must hold end to
## end across 20 consecutive admissions on each of the three large identities
## (238, 239, 76) and a small control (24).

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const SpatialIndexScript := preload("res://scripts/runtime_combat_spatial_index.gd")
const OpenTerrainFixture := preload("res://tests/helpers/monster_open_terrain_test_fixture.gd")

const MAP_ID := 9001
const ROUNDS := 20

var _index: SpatialIndexScript
var _serial := 1
var _failures: Array[String] = []


func _expect(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
		printerr("R3_REAL_ADMISSION: ", message)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(screen_px: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(screen_px)


func _ready() -> void:
	_run.call_deferred()


func _spawn(player: PlayerCharacter, monster_id: int, offset_gu: Vector2) -> EnemyActor:
	# docs/02 E: the admission gate is the L-inf box. The diagonal offset keeps
	# the ordinary channel inside the box while staying outside the spawn
	# grounding contact band (1.344 GU).
	var ground_position_gu := Vector2(16.5, 16.5) + offset_gu
	var serial := _serial
	_serial += 1
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(monster_id), player, false)
	enemy.configure_runtime_map_projection(
		MAP_ID,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground")
	)
	enemy.configure_terrain_navigation_context(OpenTerrainFixture.build(MAP_ID))
	enemy.configure_spatial_index(_index, serial)
	enemy.set_combat_position(_ground_to_screen(ground_position_gu), &"r3_real_admission_spawn")
	add_child(enemy)
	enemy.set_physics_process(false)
	_index.register(serial, MAP_ID, ground_position_gu, enemy.combat_radius_gu, serial, enemy)
	return enemy


func _admit_rounds(enemy: EnemyActor, player: PlayerCharacter, monster_id: int) -> void:
	var first_serial: int = enemy._attack_logic_serial
	var hp_before: int = player.current_hp
	var total_expected_damage := 0
	for round_index in ROUNDS:
		# A delayed release from the previous round settles through the REAL
		# pending lifecycle first (only the wait is compressed; the settle
		# itself is the production _hc_settle path).
		while enemy._pending_attack_time >= 0.0:
			enemy._pending_attack_time = minf(enemy._pending_attack_time, 1.0 / 60.0)
			# Only advance the pending lifecycle here; a full physics tick could
			# start the NEXT swing inside the settle loop and shift the serial
			# census by one round.
			enemy._update_pending_attack(1.0 / 60.0)
			# The body-action reserve is one commit per real engine frame
			# (T06). Manual ticks do not advance the engine frame, so each
			# round must cross a real physics frame before its admission.
			await get_tree().physics_frame
		# A combat-ready identity: clear the previous swing's cooldown and
		# pose so THIS round's real admission is the thing under test.
		enemy._attack_timer = 0.0
		enemy._hc_m30_attack_pose_remaining = 0.0
		enemy._hc_last_start_tick = -1
		# R2/R03: the source decision projects the owner game clock, so this
		# fixture advances the deterministic `_combat_action_time_s` by one
		# full interval per round. The real physics-frame await below already
		# rotates the per-tick decision identity, and the same-tick cache then
		# guarantees the settle loop and the admission tick share one evaluate.
		var cad = enemy._movement_cadence
		enemy._combat_action_time_s += (float(int(cad.walk_interval_ms)) + 1.0) / 1000.0
		var now_ms := int(enemy._combat_action_time_s * 1000.0)
		cad.walk_wait_locked = false
		cad.walk_tick_ms = now_ms - int(cad.walk_interval_ms) - 1
		# A freshly stamped wait tick would immediately re-lock the gate
		# (now - wait_tick <= wait interval), so park it in the past.
		cad.walk_wait_tick_ms = 0
		cad.last_evaluated_ms = now_ms - 1
		await get_tree().physics_frame
		enemy._physics_process(1.0 / 60.0)
		var record: Dictionary = enemy._last_hc_release_record
		var expected_serial := first_serial + round_index + 1
		_expect(
			enemy._attack_logic_serial == expected_serial,
			"%d round %d must bind serial %d (got %d)"
				% [monster_id, round_index, expected_serial, enemy._attack_logic_serial],
		)
		if record.is_empty():
			_expect(false, "%d round %d must archive a real release record" % [monster_id, round_index])
			return
		var parent_id: int = int(record.get("parent_action_id", -1))
		_expect(
			parent_id == enemy._attack_logic_serial,
			"%d round %d record parent id must equal the serial" % [monster_id, round_index],
		)
		_expect(
			enemy.visual.current_attack_action_id() == parent_id
				or enemy.visual._attack_remaining <= 0.0,
			"%d round %d visual must expose the same parent identity" % [monster_id, round_index],
		)
		_expect(
			enemy._audio_attack_sequence == parent_id,
			"%d round %d audio stream must bind the same identity" % [monster_id, round_index],
		)
		# Real settlement: a zero-delay melee settles in the same tick; a
		# delayed one settles through the pending loop of the next round. The
		# recorded damage must in every case really leave the player's HP.
		total_expected_damage += int(record.get("damage", 0))
		# Fast-forward the swing so the next round can admit again.
		enemy._advance_combat_action_clock(0.6)
		enemy.visual._advance_action_timers(0.6)
	# The final round's delayed release must also settle for real.
	while enemy._pending_attack_time >= 0.0:
		enemy._pending_attack_time = minf(enemy._pending_attack_time, 1.0 / 60.0)
		enemy._physics_process(1.0 / 60.0)
	var hp_lost := hp_before - player.current_hp
	# R3 W6: the census proves the REAL settlement chain (record -> settle ->
	# victim HP loss). The applied total goes through the production damage
	# formula, so it may be reduced below the raw roll sum; it can never
	# exceed it and must not be zero - the exact per-hit numbers are owned by
	# the combat-math tests, not by this lifecycle census.
	_expect(
		hp_lost > 0 and hp_lost <= total_expected_damage,
		"%d real settlement must apply real damage within the recorded total: recorded %d applied %d"
			% [monster_id, total_expected_damage, hp_lost],
	)


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_index = SpatialIndexScript.new()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.current_hp = 1000000
	player.max_hp = 1000000
	player.defense_min = 0
	player.defense_max = 0
	player.defense_buff = 0
	player.global_position = _ground_to_screen(Vector2(16.5, 16.5))
	await get_tree().process_frame

	for monster_id: int in [238, 239, 76, 24]:
		var enemy := _spawn(player, monster_id, Vector2(0.95, 0.95))
		await get_tree().process_frame
		enemy.target = player
		enemy._refresh_target_focus()
		_expect(
			enemy.combat_enabled and not enemy.has_meta("body_policy_rejected"),
			"fixture: identity %d must be a combat-enabled member" % monster_id,
		)
		await _admit_rounds(enemy, player, monster_id)
		enemy.queue_free()

	player.queue_free()
	if _failures.is_empty():
		print("R3_REAL_ADMISSION_CENSUS_PASS")
	get_tree().quit(0 if _failures.is_empty() else 1)
