extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

## Current contract for race 94 / monster 79 line_magic: this delivery is an
## AOE-style committed release. Victims are frozen and damaged synchronously
## at admission; the presentation may continue, but target movement afterwards
## cannot cancel or duplicate the already-consumed damage.
## The former delayed line-evasion contract is retained byte-for-byte under
## outputs/phone_crowd_local_20261008/retired_line_motion_contract/ as evidence.
const OUTPUT_PATH := "res://outputs/test_logs/r4_line_motion_evasion.json"

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	Observer.recording_enabled = true
	await _case_move_after_commit()
	await _case_move_along_line_after_commit()
	await _case_initially_out_of_range()
	Observer.recording_enabled = false
	FileAccess.open(OUTPUT_PATH, FileAccess.WRITE).store_string(JSON.stringify({"schema": "r4_line_aoe_commit_v1", "rows": rows, "failures": failures}, "  "))
	print("R4_LINE_AOE_COMMIT_PASS" if failures.is_empty() else "R4_LINE_AOE_COMMIT_FAIL " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _new_player(position_gu: Vector2) -> PlayerCharacter:
	var created := PlayerCharacter.new()
	created.set_meta("runtime_map_id", MAP_ID)
	created.set_meta("zone_generation", 1)
	created.position = _ground_to_screen(position_gu)
	add_child(created)
	created.set_physics_process(false)
	created.max_hp = 1000000
	created.current_hp = created.max_hp
	return created

func _wait_for_commit(actor: EnemyActor, timeout_ms := 2200) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Observer.admissions.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	return not Observer.admissions.is_empty()

func _commit_case(actor: EnemyActor, label: String, move_to: Vector2) -> void:
	var admitted := await _wait_for_commit(actor)
	_check(admitted, label + ":missing_real_admission")
	_check(actor._pending_attack_time < 0.0, label + ":line_release_still_pending")
	_check(Observer.events.size() == 1, label + ":admission_not_synchronously_consumed")
	var hp_after_commit := player.current_hp
	_check(hp_after_commit < player.max_hp, label + ":synchronous_release_did_not_reduce_hp")
	var frozen := actor._last_attack_footprint_snapshot.duplicate(true)
	player.global_position = _ground_to_screen(move_to)
	await get_tree().physics_frame
	await get_tree().physics_frame
	actor.set_physics_process(false)
	var current_gu := _screen_to_ground(player.global_position)
	var audit := Verifier.audit_releases(Observer.admissions, Observer.events, Observer.terminal_events, actor.get_instance_id(), Observer.deliveries, Observer.overflowed)
	_check(audit.failures.is_empty(), label + ":audit=" + str(audit.failures))
	_check(player.current_hp == hp_after_commit, label + ":movement_changed_committed_hp")
	_check(Observer.events.size() == 1, label + ":movement_added_duplicate_event")
	rows.append({"contract": "aoe_commit_synchronous", "case": label, "frozen_geometry": frozen, "release_current_player_ground_gu": current_gu, "pending_after_admission": actor._pending_attack_time, "starts": Observer.admissions.duplicate(true), "deliveries": Observer.deliveries.duplicate(true), "events": Observer.events.duplicate(true), "terminals": Observer.terminal_events.duplicate(true), "hp_after_commit": hp_after_commit, "hp_after_motion": player.current_hp, "audit": audit})

func _case_move_after_commit() -> void:
	Observer.reset()
	player = _new_player(Vector2(16.0, 16.0))
	var actor := _spawn(79, Vector2(14.0, 16.0))
	_check(str(actor.attack_delivery_rule.get("kind", "")) == "line_magic", "move:not_line_family")
	actor.set_physics_process(true)
	await _commit_case(actor, "move_after_commit", Vector2(16.0, 17.0))
	_cleanup_actor(actor)
	player.free()
	await get_tree().physics_frame

func _case_move_along_line_after_commit() -> void:
	Observer.reset()
	player = _new_player(Vector2(16.0, 16.0))
	var actor := _spawn(79, Vector2(14.0, 16.0))
	_check(str(actor.attack_delivery_rule.get("kind", "")) == "line_magic", "along:not_line_family")
	actor.set_physics_process(true)
	await _commit_case(actor, "move_along_line_after_commit", Vector2(17.0, 16.0))
	_cleanup_actor(actor)
	player.free()
	await get_tree().physics_frame

func _case_initially_out_of_range() -> void:
	Observer.reset()
	player = _new_player(Vector2(22.5, 16.0))
	var actor := _spawn(79, Vector2(14.0, 16.0))
	_check(str(actor.attack_delivery_rule.get("kind", "")) == "line_magic", "out_of_range:not_line_family")
	actor.set_physics_process(true)
	var admitted := await _wait_for_commit(actor)
	actor.set_physics_process(false)
	_check(not admitted, "out_of_range:unexpected_admission")
	_check(Observer.admissions.is_empty(), "out_of_range:admission_recorded")
	_check(Observer.events.is_empty(), "out_of_range:damage_event")
	_check(player.current_hp == player.max_hp, "out_of_range:hp_changed")
	rows.append({"contract": "aoe_commit_synchronous", "case": "initially_out_of_range", "release_current_player_ground_gu": _screen_to_ground(player.global_position), "starts": Observer.admissions.duplicate(true), "deliveries": Observer.deliveries.duplicate(true), "events": Observer.events.duplicate(true), "terminals": Observer.terminal_events.duplicate(true), "hp_after": player.current_hp})
	_cleanup_actor(actor)
	player.free()
	await get_tree().physics_frame

func _cleanup_actor(actor: EnemyActor) -> void:
	if actor.spatial_actor_runtime_id > 0:
		index.unregister(actor.spatial_actor_runtime_id)
	actor.free()
