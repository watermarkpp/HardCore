extends "res://tests/immediate_item_save_test.gd"

func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	var state := _new_state("warrior_toggle", 1)
	state.profession = "战士"
	var profile_path: String = state._profile_path("owner")
	var before := FileAccess.get_file_as_bytes(profile_path)
	var profile_signals: Array = []
	state.profile_changed.connect(func() -> void: profile_signals.append(true))
	var snapshot: Dictionary = state.warrior_runtime_state_for_restore()
	for i in 21:
		snapshot.toggles["warrior.thrusting"] = (i % 2 == 0)
		snapshot.toggles["warrior.half_moon"] = (i % 3 == 0)
		snapshot.toggles["warrior.fire_sword.auto_enabled"] = (i % 4 == 0)
		assert(state.apply_warrior_runtime_state(snapshot, true))
	assert(state.warrior_runtime_state_for_restore() == snapshot, "toggle did not apply immediately")
	assert(FileAccess.get_file_as_bytes(profile_path) == before, "warrior toggle performed synchronous file IO on the input path")
	assert(profile_signals.is_empty(), "warrior toggle broadcast unrelated full profile refresh")
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		state._process(0.0)
		if _read(state).warrior_runtime_state == snapshot and state._json_persistence.pending_count() == 0: break
		await get_tree().process_frame
	assert(_read(state).warrior_runtime_state == snapshot, "latest accepted toggle did not reach disk")
	snapshot.toggles["warrior.thrusting"] = true
	assert(state.apply_warrior_runtime_state(snapshot, true))
	state.free()
	assert(JSON.parse_string(FileAccess.get_file_as_string(profile_path)).warrior_runtime_state == snapshot, "lifecycle flush lost unpumped toggle")
	print("IMMEDIATE_WARRIOR_TOGGLE_SAVE_PASS")
	get_tree().quit(0)
