extends Node

## Account/device presentation preferences, deliberately outside PlayerState.
## Music: user gain on Music bus. SFX: user gain in AudioRuntimeService only.
signal levels_changed(music: float, sfx: float)
signal save_failed(error_code: int)
const PATH := "user://audio_preferences_v2.cfg"
const TEMP := PATH + ".tmp"
const BACKUP := PATH + ".bak"
var storage_path := PATH
var music_volume := 1.0
var sfx_volume := 1.0
var dirty := false
var last_save_error := OK
var _sfx_services: Array[WeakRef] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# v1 had runtime bus toggles, not a proven persisted preference file.
	# Respect an already-muted bus on first migration; do not invent a file.
	music_volume = _initial_level(&"Music")
	sfx_volume = _initial_level(&"SFX")
	var saved := _read_valid(storage_path)
	if saved.is_empty():
		saved = _read_valid(storage_path + ".bak")
		if not saved.is_empty():
			dirty = true
	if not saved.is_empty():
		music_volume = float(saved["music"])
		sfx_volume = float(saved["sfx"])
	_apply()

func _initial_level(bus: StringName) -> float:
	var index := AudioServer.get_bus_index(bus)
	return 0.0 if index >= 0 and AudioServer.is_bus_mute(index) else 1.0

static func valid_level(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 1.0

func set_level(channel: String, value: Variant) -> bool:
	if channel not in ["music", "sfx"] or not valid_level(value):
		return false
	var next_level := float(value)
	var previous := music_volume if channel == "music" else sfx_volume
	if is_equal_approx(previous, next_level):
		return true
	if channel == "music":
		music_volume = next_level
	else:
		sfx_volume = next_level
	dirty = true
	_apply()
	levels_changed.emit(music_volume, sfx_volume)
	return true

func bind_sfx_service(service: Node) -> void:
	if not is_instance_valid(service) or not service.has_method("set_user_sfx_gain_linear") or not service.has_method("set_sfx_enabled"):
		return
	for reference: WeakRef in _sfx_services:
		if reference.get_ref() == service:
			_apply()
			return
	_sfx_services.append(weakref(service))
	_apply()

func _ensure_bus(bus_name: StringName) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, &"Master")
	return index

func _apply() -> void:
	var music := _ensure_bus(&"Music")
	var sfx := _ensure_bus(&"SFX")
	AudioServer.set_bus_volume_db(music, linear_to_db(music_volume) if music_volume > 0.0 else -80.0)
	AudioServer.set_bus_mute(music, music_volume <= 0.0)
	# Preserve the service's authored 0.5 project scale. Never apply the user
	# slider again on the SFX bus (which would incorrectly square its gain).
	AudioServer.set_bus_volume_db(sfx, 0.0)
	AudioServer.set_bus_mute(sfx, sfx_volume <= 0.0)
	for index in range(_sfx_services.size() - 1, -1, -1):
		var service := _sfx_services[index].get_ref() as Node
		if service == null:
			_sfx_services.remove_at(index)
			continue
		service.call("set_user_sfx_gain_linear", sfx_volume)
		service.call("set_sfx_enabled", sfx_volume > 0.0)

func _read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return {}
	# Same strict type contract as the writer: a true TYPE_INT 2. Reject
	# floats, strings, bools, arrays and dictionaries BEFORE any numeric
	# conversion so 2.9 can never truncate into a valid version.
	var version: Variant = config.get_value("meta", "version", null)
	if typeof(version) != TYPE_INT or version != 2:
		return {}
	var music: Variant = config.get_value("audio", "music_volume", null)
	var sfx: Variant = config.get_value("audio", "sfx_volume", null)
	if not valid_level(music) or not valid_level(sfx):
		return {}
	return {"music": float(music), "sfx": float(sfx)}

func flush() -> Error:
	if not dirty:
		return OK
	var config := ConfigFile.new()
	config.set_value("meta", "version", 2)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	var error := config.save(storage_path + ".tmp")
	if error != OK:
		return _fail(error)
	var written := _read_valid(storage_path + ".tmp")
	if written.is_empty() or not is_equal_approx(float(written["music"]), music_volume) or not is_equal_approx(float(written["sfx"]), sfx_volume):
		return _fail(ERR_FILE_CORRUPT)
	var main_path := ProjectSettings.globalize_path(storage_path)
	var temp_path := ProjectSettings.globalize_path(storage_path + ".tmp")
	var backup_path := ProjectSettings.globalize_path(storage_path + ".bak")
	var rotated := false
	if FileAccess.file_exists(storage_path):
		# Never overwrite a known-good backup with a corrupt primary.
		if not _read_valid(storage_path).is_empty():
			if FileAccess.file_exists(storage_path + ".bak"):
				error = DirAccess.remove_absolute(backup_path)
				if error != OK:
					return _fail(error)
			error = DirAccess.rename_absolute(main_path, backup_path)
			if error != OK:
				return _fail(error)
			rotated = true
		else:
			# Preserve bad data for diagnosis; do not delete an unvalidated file.
			var corrupt_path := main_path + ".corrupt." + str(Time.get_ticks_usec())
			error = DirAccess.rename_absolute(main_path, corrupt_path)
			if error != OK:
				return _fail(error)
	error = DirAccess.rename_absolute(temp_path, main_path)
	if error != OK:
		if rotated:
			var restore_error := DirAccess.rename_absolute(backup_path, main_path)
			if restore_error != OK:
				push_error("Audio preferences backup retained; restore failed: " + str(restore_error))
		return _fail(error)
	dirty = false
	last_save_error = OK
	return OK

func _fail(error: Error) -> Error:
	last_save_error = error
	dirty = true
	save_failed.emit(error)
	push_warning("音量设置尚未保存，原设置/备份仍保留。错误码：" + str(error))
	return error

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		flush()

func _exit_tree() -> void:
	flush()
