extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

## Real ordinary ID24 admission, the existing exact admission callback seam,
## and real physics/body-action clock. No timing/stat/pending writes. Current
## ordinary IDs settle immediately; the callback exercises movement/lifecycle
## between the accepted geometry and that same formal HP delivery.
func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	Observer.recording_enabled = true
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	await _committed_case()
	_range_case()
	for change: String in ["combat_epoch", "generation"]:
		_lifecycle_case(change)
	Observer.recording_enabled = false
	FileAccess.open("res://outputs/test_logs/committed_melee_action.json", FileAccess.WRITE).store_string(JSON.stringify({"schema": "committed_melee_action_v2", "rows": rows, "failures": failures}, "  "))
	player.free()
	print("COMMITTED_MELEE_ACTION_PASS" if failures.is_empty() else "COMMITTED_MELEE_ACTION_FAIL " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _committed_case() -> void:
	Observer.reset()
	var actor := _spawn(24, CENTER + Vector2(0.98, 0.98))
	var start := actor.global_position
	var hp_before := player.current_hp
	var frozen: Array = [{}]
	var wall: Array = [null]
	actor.test_attack_admission_hook = func(record: Dictionary) -> void:
		frozen[0] = record
		player.global_position = _ground_to_screen(CENTER + Vector2(5, 5))
		var body := StaticBody2D.new()
		body.collision_layer = WorldSpatialRules.WORLD_MASK
		body.collision_mask = 0
		body.position = _ground_to_screen(CENTER + Vector2(2, 2))
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 4.0
		shape.shape = circle
		body.add_child(shape)
		add_child(body)
		wall[0] = body
	var accepted := actor._hc_try_start(player)
	actor.test_attack_admission_hook = Callable()
	_check(accepted and actor._source176_ordinary_melee(), "ordinary real admission missing")
	_check(bool(frozen[0].get("ordinary_committed", false)) and frozen[0].has("admission_footprint"), "frozen admission missing")
	_check(player.current_hp < hp_before and Observer.deliveries.size() == 1 and Observer.events.size() == 1, "accepted hit lost after target moved")
	var hp_after := player.current_hp
	actor._hc_settle(actor._last_hc_release_record)
	_check(player.current_hp == hp_after and Observer.events.size() == 1, "duplicate committed settlement")
	actor.set_physics_process(true)
	var held_frames := 0
	for tick in range(180):
		await get_tree().physics_frame
		if not actor._attack_action_active:
			break
		held_frames += 1
		_check(actor.global_position == start, "pursuit resumed before action finished")
		_check(actor._last_hc_release_record.get("parent_action_id") == frozen[0].get("parent_action_id"), "parent action changed during animation")
	_check(held_frames > 0 and not actor._attack_action_active, "full action window not observed")
	wall[0].queue_free()
	var resumed := false
	for tick in range(240):
		await get_tree().physics_frame
		if actor.global_position.distance_to(start) > 0.01:
			resumed = true
			break
	actor.set_physics_process(false)
	_check(resumed, "pursuit did not resume after action finished")
	rows.append({"case": "ordinary_committed", "accepted": accepted, "held_frames": held_frames, "resumed": resumed, "hp_before": hp_before, "hp_after": hp_after, "admission": frozen[0], "events": Observer.events.duplicate(true)})
	_cleanup(actor)

func _range_case() -> void:
	Observer.reset()
	player.global_position = _ground_to_screen(CENTER)
	var actor := _spawn(24, CENTER + Vector2(1.2, 1.2))
	var hp_before := player.current_hp
	_check(not actor._hc_try_start(player) and actor._hc_last_reason == "OUT_OF_RANGE", "initial geometry gate bypassed")
	_check(actor._hc_starts == 0 and player.current_hp == hp_before, "rejected start consumed HP/action")
	rows.append({"case": "range", "reason": actor._hc_last_reason})
	_cleanup(actor)

func _lifecycle_case(change: String) -> void:
	Observer.reset()
	player.global_position = _ground_to_screen(CENTER)
	var actor := _spawn(24, CENTER + Vector2(0.98, 0.98))
	var hp_before := player.current_hp
	actor.test_attack_admission_hook = func(_record: Dictionary) -> void:
		if change == "combat_epoch":
			player.begin_combat_transition("committed-melee")
		else:
			player.set_meta("zone_generation", 2)
	_check(actor._hc_try_start(player), change + ":real admission missing")
	actor.test_attack_admission_hook = Callable()
	_check(player.current_hp == hp_before and Observer.events.is_empty() and Observer.terminal_events.size() == 1, change + ":stale delivery damaged")
	rows.append({"case": change, "hp_unchanged": player.current_hp == hp_before, "terminals": Observer.terminal_events.duplicate(true)})
	if change == "combat_epoch":
		player.finish_combat_transition("committed-melee")
	else:
		player.set_meta("zone_generation", 1)
	_cleanup(actor)

func _cleanup(actor: EnemyActor) -> void:
	index.unregister(actor.spatial_actor_runtime_id)
	actor.free()