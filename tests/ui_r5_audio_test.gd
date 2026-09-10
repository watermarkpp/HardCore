extends Node
const Preferences := preload("res://scripts/audio_preferences.gd")
var failures: Array[String] = []
var checks := 0

class FakeSFX:
	extends Node
	var gain := 1.0
	var enabled := true
	func set_user_sfx_gain_linear(value: float) -> bool:
		gain = value
		return true
	func set_sfx_enabled(value: bool) -> void:
		enabled = value

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var directory := "user://ui_r5_audio_test_" + str(Time.get_ticks_usec())
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	expect(error == OK, "isolated test directory")
	var path := directory + "/preferences.cfg"
	var prefs := Preferences.new()
	prefs.storage_path = path
	add_child(prefs)
	var service := FakeSFX.new()
	add_child(service)
	prefs.bind_sfx_service(service)
	expect(not prefs.set_level("music", "0.5"), "string input rejected")
	expect(not prefs.set_level("music", true), "boolean input rejected for v2")
	expect(not prefs.set_level("music", NAN), "NaN rejected")
	expect(not prefs.set_level("sfx", -0.1), "negative gain rejected")
	expect(not prefs.set_level("sfx", 1.1), "out of range gain rejected")
	expect(not prefs.set_level("unknown", 0.4), "unknown channel rejected")
	prefs.set_level("music", 0.31)
	prefs.set_level("sfx", 0.42)
	expect(prefs.dirty and not FileAccess.file_exists(path), "preview does not write per movement")
	expect(is_equal_approx(service.gain, 0.42), "raw user gain reaches existing service")
	expect(is_zero_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))), "SFX bus does not apply gain again")
	expect(prefs.flush() == OK, "first save")
	expect(not prefs.dirty, "saved state clean")
	var first := FileAccess.get_file_as_bytes(path)
	prefs.set_level("music", 0.72)
	prefs.set_level("sfx", 0.64)
	expect(prefs.flush() == OK, "second save")
	expect(FileAccess.get_file_as_bytes(path + ".bak") == first, "backup contains previous exact file")
	var saved := FileAccess.get_file_as_bytes(path)
	prefs._fail(ERR_CANT_CREATE)
	expect(prefs.dirty and prefs.last_save_error == ERR_CANT_CREATE, "injected save failure stays dirty")
	expect(FileAccess.get_file_as_bytes(path) == saved, "failure state does not overwrite saved bytes")
	expect(prefs.flush() == OK, "retry succeeds")
	prefs.set_level("sfx", 0.0)
	expect(not service.enabled and is_zero_approx(service.gain), "0% is mute")
	prefs.set_level("sfx", 1.0)
	prefs.bind_sfx_service(service)
	expect(service.enabled and is_equal_approx(service.gain, 1.0), "rebind is idempotent")
	prefs.set_level("music", 0.72)
	prefs.set_level("sfx", 0.64)
	prefs.flush()
	prefs.queue_free()
	await get_tree().process_frame
	var restored := Preferences.new()
	restored.storage_path = path
	add_child(restored)
	expect(is_equal_approx(restored.music_volume, 0.72) and is_equal_approx(restored.sfx_volume, 0.64), "reload uses numeric persisted levels")
	# Semantic corruption (valid CFG syntax but invalid version) avoids engine
	# parser errors, while exercising the actual backup recovery implementation.
	var invalid := ConfigFile.new()
	invalid.set_value("meta", "version", 99)
	invalid.save(path)
	restored.queue_free()
	await get_tree().process_frame
	var recovered := Preferences.new()
	recovered.storage_path = path
	add_child(recovered)
	expect(recovered.dirty, "backup recovery marks repaired primary for saving")
	expect(recovered.flush() == OK, "recovered preference persists safely")
	expect(not recovered._read_valid(path).is_empty(), "recovered main is validated")
	recovered.queue_free()
	service.queue_free()
	await get_tree().process_frame
	AudioPreferences._apply()
	for failure: String in failures:
		push_error("UI_R5_AUDIO: " + failure)
	print("UI_R5_AUDIO_%s checks=%d failures=%d evidence=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size(), directory])
	get_tree().quit(0 if failures.is_empty() else 1)
