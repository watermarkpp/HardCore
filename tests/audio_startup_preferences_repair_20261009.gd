extends Node

## Cold-start regression for the v108 audio symptom. This intentionally uses
## the real AudioPreferences and AudioRuntimeService scripts, but writes only
## under a test-owned user:// directory. No production preference is touched.

const AudioPreferencesScript := preload("res://scripts/audio_preferences.gd")
const AudioServiceScript := preload("res://scripts/audio_runtime_service.gd")
const TEST_ROOT := "user://audio_startup_preferences_repair_20261009"

var _bus_state: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_ROOT))
	_capture_bus(&"Music")
	_capture_bus(&"SFX")
	await _assert_cold_defaults_and_real_service_gain()
	await _assert_saved_zero_is_intentional()
	await _assert_saved_nonzero_and_same_value_reapply()
	_cleanup()
	print("AUDIO_STARTUP_PREFERENCES_REPAIR_PASS")
	get_tree().quit(0)


func _capture_bus(bus_name: StringName) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, &"Master")
	_bus_state[bus_name] = {
		"index": index,
		"muted": AudioServer.is_bus_mute(index),
		"volume_db": AudioServer.get_bus_volume_db(index),
	}


func _set_bus(bus_name: StringName, muted: bool, volume_db: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	assert(index >= 0, "fixture bus missing: %s" % bus_name)
	AudioServer.set_bus_volume_db(index, volume_db)
	AudioServer.set_bus_mute(index, muted)


func _write_cfg(path: String, music: float, sfx: float) -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", 2)
	config.set_value("audio", "music_volume", music)
	config.set_value("audio", "sfx_volume", sfx)
	assert(config.save(path) == OK, "fixture config write failed: %s" % path)


func _new_preferences(path: String) -> Node:
	var prefs: Node = AudioPreferencesScript.new()
	prefs.storage_path = path
	add_child(prefs)
	return prefs


func _new_service() -> Node:
	var service: Node = AudioServiceScript.new()
	add_child(service)
	return service


func _drop(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()
		await get_tree().process_frame


func _assert_cold_defaults_and_real_service_gain() -> void:
	var path := TEST_ROOT + "/missing.cfg"
	_set_bus(&"Music", true, -80.0)
	_set_bus(&"SFX", true, -80.0)
	var prefs := _new_preferences(path)
	assert(is_equal_approx(float(prefs.music_volume), 1.0), "missing config must default Music to 1.0")
	assert(is_equal_approx(float(prefs.sfx_volume), 1.0), "missing config must default SFX to 1.0")
	assert(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")), "cold default must unmute Music")
	assert(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")), "cold default must unmute SFX")

	var service := _new_service()
	await get_tree().process_frame
	prefs.call("bind_sfx_service", service)
	assert(bool(service.call("is_sfx_enabled")), "rebinding the real service must preserve enabled SFX")
	var player := service.get("npc_voice_player") as AudioStreamPlayer
	assert(player != null, "real service must create the NPC player")
	assert(float(player.volume_db) > -80.0, "real player gain must be audible after cold default")
	await _drop(service)
	await _drop(prefs)


func _assert_saved_zero_is_intentional() -> void:
	var path := TEST_ROOT + "/saved_zero.cfg"
	_write_cfg(path, 0.0, 0.0)
	_set_bus(&"Music", false, 0.0)
	_set_bus(&"SFX", false, 0.0)
	var prefs := _new_preferences(path)
	assert(is_zero_approx(float(prefs.music_volume)), "saved Music zero must remain zero")
	assert(is_zero_approx(float(prefs.sfx_volume)), "saved SFX zero must remain zero")
	assert(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")), "saved Music zero must mute Music")
	assert(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")), "saved SFX zero must mute SFX")
	await _drop(prefs)


func _assert_saved_nonzero_and_same_value_reapply() -> void:
	var path := TEST_ROOT + "/saved_nonzero.cfg"
	_write_cfg(path, 0.55, 0.66)
	_set_bus(&"Music", true, -80.0)
	_set_bus(&"SFX", true, -80.0)
	var prefs := _new_preferences(path)
	assert(is_equal_approx(float(prefs.music_volume), 0.55), "saved Music level must load exactly")
	assert(is_equal_approx(float(prefs.sfx_volume), 0.66), "saved SFX level must load exactly")
	assert(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")), "saved nonzero Music must unmute Music")
	assert(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")), "saved nonzero SFX must unmute SFX")

	var service := _new_service()
	await get_tree().process_frame
	prefs.call("bind_sfx_service", service)
	assert(bool(service.call("is_sfx_enabled")), "saved nonzero SFX must enable the service")
	_set_bus(&"SFX", true, -80.0)
	prefs.call("bind_sfx_service", service)
	assert(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")), "rebinding must reapply saved SFX state")
	_set_bus(&"SFX", true, -80.0)
	assert(bool(prefs.call("set_level", "sfx", 0.66)), "same-value SFX slider request must be accepted")
	assert(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")), "same-value SFX request must repair a muted bus")
	await _drop(service)
	await _drop(prefs)


func _cleanup() -> void:
	for bus_name: StringName in [&"Music", &"SFX"]:
		var state: Dictionary = _bus_state.get(bus_name, {})
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0 and not state.is_empty():
			AudioServer.set_bus_volume_db(index, float(state.get("volume_db", 0.0)))
			AudioServer.set_bus_mute(index, bool(state.get("muted", false)))
	_remove_recursive(ProjectSettings.globalize_path(TEST_ROOT))


func _remove_recursive(absolute_path: String) -> void:
	var dir := DirAccess.open(absolute_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry not in [".", ".."]:
			var child := absolute_path.path_join(entry)
			if dir.current_is_dir():
				_remove_recursive(child)
			else:
				dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(absolute_path)
