extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

## Production damage consumers and official life/map APIs at actual admission.
func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	Observer.recording_enabled = true
	for pair: Array in [[24, "skeleton"], [76, "skeleton"], [238, "divine_beast"]]:
		await _body_pair(int(pair[0]), str(pair[1]), false)
	await _body_pair(76, "skeleton", true)
	for change: String in ["revive", "target_map", "source_map", "target_free"]:
		await _admitted_lifecycle(change)
	Observer.recording_enabled = false
	FileAccess.open("res://outputs/test_logs/r4_body_multitarget_lifecycle.json", FileAccess.WRITE).store_string(JSON.stringify({"rows": rows, "failures": failures}, "  "))
	print("R4_BODY_MULTITARGET_LIFECYCLE_PASS" if failures.is_empty() else "R4_BODY_MULTITARGET_LIFECYCLE_FAIL " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _make_player(ground: Vector2) -> void:
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.position = _ground_to_screen(ground)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 10000
	player.current_hp = player.max_hp

func _body_pair(mid: int, pet_kind: String, multi: bool) -> void:
	Observer.reset()
	# Target-cell footprints are centred on rounded integer GU, not floor cells.
	var center := Vector2(16, 16) if multi else CENTER
	_make_player(center + Vector2(-0.39 if multi else -0.9, 0))
	var pet := SummonActor.new()
	var skill := "taoist.summon_skeleton" if pet_kind == "skeleton" else "taoist.summon_divine_beast"
	pet.setup(player, "骷髅" if pet_kind == "skeleton" else "神兽", 30, 3, skill, 50, 7)
	pet.configure_runtime_map_projection(MAP_ID, _ground_to_screen, _screen_to_ground)
	pet.configure_spatial_index(index)
	pet.set_meta("zone_generation", 1)
	pet.position = _ground_to_screen(center + Vector2(0.39 if multi else 0, 0))
	add_child(pet)
	pet.set_physics_process(false)
	pet.max_hp = 10000
	pet.current_hp = pet.max_hp
	# Shared target discovery has a production 250ms refresh period. Wait for
	# real time rather than clearing that cache for the fixture.
	await get_tree().create_timer(0.3).timeout
	var actor := _spawn(mid, center + Vector2(-1.5 if multi else 1.46, 0))
	var target: Node2D = player if multi else pet
	var radius := pet.combat_radius_gu
	var shape: CollisionShape2D = pet.get_node_or_null("CollisionShape2D")
	_check(shape != null and shape.shape is ConvexPolygonShape2D, "%d:%s:pet_shape_missing" % [mid, pet_kind])
	if shape != null and shape.shape is ConvexPolygonShape2D:
		for vertex: Vector2 in (shape.shape as ConvexPolygonShape2D).points:
			_check(absf(_screen_to_ground(vertex).length() - radius) < 0.00001, "pet_shape_radius_mismatch")
	var hp_before := pet.current_hp
	var accepted := actor._hc_try_start(target)
	_check(accepted, "%d:%s:legal_body_pair_rejected:%s" % [mid, pet_kind, actor._hc_last_reason])
	actor.set_physics_process(true)
	await get_tree().create_timer(0.65).timeout
	actor.set_physics_process(false)
	var audit := Verifier.audit_releases(Observer.admissions, Observer.events, Observer.terminal_events, actor.get_instance_id(), Observer.deliveries, Observer.overflowed)
	_check(audit.failures.is_empty(), "%d:%s:body_pair_audit=%s" % [mid, pet_kind, audit.failures])
	_check(not Observer.deliveries.is_empty(), "%d:%s:no_delivery" % [mid, pet_kind])
	if multi:
		_check(Observer.deliveries.size() == 2, "mixed_real_multi_target_not_two")
		var targets: Dictionary = {}
		for child: Dictionary in Observer.deliveries:
			targets[int(child.victim_instance_id)] = true
		_check(targets.has(player.get_instance_id()) and targets.has(pet.get_instance_id()), "mixed_wrong_actual_targets")
	rows.append({"monster_id": mid, "pet": pet_kind, "multi": multi, "accepted": accepted,
		"player_ground": _screen_to_ground(player.global_position), "pet_ground": _screen_to_ground(pet.global_position),
		"pet_live": actor._special_delivery_target_is_live(pet), "pet_inside": actor._snapshot_intersects_target(actor._last_attack_footprint_snapshot, pet),
		"enemy_radius_gu": actor.combat_radius_gu, "pet_radius_gu": radius, "pet_hp_delta": hp_before - pet.current_hp,
		"starts": Observer.admissions.duplicate(true), "deliveries": Observer.deliveries.duplicate(true),
		"events": Observer.events.duplicate(true), "terminals": Observer.terminal_events.duplicate(true), "audit": audit})
	index.unregister(actor.spatial_actor_runtime_id)
	actor.free()
	pet.free()
	player.free()
	await get_tree().physics_frame

func _admitted_lifecycle(change: String) -> void:
	Observer.reset()
	_make_player(CENTER)
	var actor := _spawn(238, CENTER + Vector2(1.4, 0))
	var mutation_count := [0]
	actor.test_attack_admission_hook = func(_record: Dictionary) -> void:
		mutation_count[0] += 1
		_change_lifecycle(change, actor)
	var accepted := actor._hc_try_start(player)
	_check(accepted and mutation_count[0] == 1, change + ":not_actual_admission")
	actor.test_attack_admission_hook = Callable()
	var hp_before := player.current_hp if is_instance_valid(player) else -1
	await get_tree().create_timer(0.65).timeout
	_check(not is_instance_valid(player) or player.current_hp == hp_before, change + ":stale_release_changed_new_life_hp")
	var audit := Verifier.audit_releases(Observer.admissions, Observer.events, Observer.terminal_events, actor.get_instance_id(), Observer.deliveries, Observer.overflowed)
	_check(audit.failures.is_empty(), change + ":lifecycle_audit=" + str(audit.failures))
	_check(Observer.terminal_events.size() == 1 and Observer.deliveries.is_empty(), change + ":expected_one_real_rejection")
	rows.append({"case": change, "starts": Observer.admissions.duplicate(true), "deliveries": Observer.deliveries.duplicate(true),
		"events": Observer.events.duplicate(true), "terminals": Observer.terminal_events.duplicate(true), "audit": audit})
	index.unregister(actor.spatial_actor_runtime_id)
	actor.free()
	if is_instance_valid(player):
		player.free()
	await get_tree().physics_frame

func _change_lifecycle(change: String, actor: EnemyActor) -> void:
	var original_epoch := player.combat_epoch
	match change:
		"revive":
			player.take_damage(20000, false)
			_check(player._dead, "revive:death_not_reached")
			player.complete_death_revival()
			_check(not player._dead and player.combat_epoch > original_epoch, "revive:new_life_not_reached")
		"target_map":
			_check(player.begin_combat_transition("r4-map-transition"), "target_map:transition_not_started")
			player.set_meta("runtime_map_id", MAP_ID + 1)
			player.set_meta("zone_generation", 2)
			_check(player.finish_combat_transition("r4-map-transition"), "target_map:transition_not_finished")
		"source_map":
			actor.configure_runtime_map_projection(MAP_ID + 1, _ground_to_screen, _screen_to_ground)
		"target_free":
			player.free()
