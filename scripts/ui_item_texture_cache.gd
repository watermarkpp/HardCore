class_name UIItemTextureCache
extends RefCounted

static var _textures: Dictionary = {}
static var _threaded_paths: Dictionary = {}
static var _sync_miss_count := 0
static var _headless_prefetch_load_count := 0
static var _headless_prefetch_failures: Dictionary = {}
# Allows the dedicated contract test to exercise the unchanged async branch.
static var _test_force_threaded_prefetch := false


static func texture_for_item(item_ref: Variant, field := "inventoryIcon") -> Texture2D:
	return texture_at_path(GameData.get_item_art_path(item_ref, field))


static func texture_for(record: Dictionary, field := "inventoryIcon") -> Texture2D:
	var art: Variant = record.get("art", {})
	if not art is Dictionary:
		return null
	var source: Variant = art.get(field, {})
	var path := str(source.get("path", "")) if source is Dictionary else str(source)
	if path.is_empty():
		return null
	return texture_at_path(path)


static func texture_at_path(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path] as Texture2D
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if _use_headless_serial_prefetch() and _headless_prefetch_failures.has(path):
		return null
	if _threaded_paths.has(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
		var threaded_texture := ResourceLoader.load_threaded_get(path) as Texture2D
		_threaded_paths.erase(path)
		if threaded_texture != null:
			_textures[path] = threaded_texture
			return threaded_texture
	_sync_miss_count += 1
	var texture := load(path) as Texture2D
	if texture != null:
		_textures[path] = texture
	return texture


static func request_threaded_paths(paths: Array) -> int:
	var requested := 0
	var serial_test_load := _use_headless_serial_prefetch()
	for raw_path: Variant in paths:
		var path := str(raw_path)
		if path.is_empty() or _textures.has(path) or _threaded_paths.has(path):
			continue
		if serial_test_load:
			if _headless_prefetch_failures.has(path):
				continue
			var texture: Texture2D = ResourceLoader.load(path) as Texture2D if ResourceLoader.exists(path) else null
			_headless_prefetch_load_count += 1
			if texture == null:
				_headless_prefetch_failures[path] = true
			else:
				_textures[path] = texture
				requested += 1
			continue
		if not ResourceLoader.exists(path):
			continue
		var error := ResourceLoader.load_threaded_request(path, "Texture2D", false)
		if error == OK:
			_threaded_paths[path] = true
			requested += 1
	return requested


static func poll_threaded_paths() -> int:
	var ready := 0
	for path: String in _threaded_paths.keys().duplicate():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var texture := ResourceLoader.load_threaded_get(path) as Texture2D
			if texture != null:
				_textures[path] = texture
			_threaded_paths.erase(path)
			ready += 1
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			_threaded_paths.erase(path)
	return ready


static func threaded_pending_count() -> int:
	return _threaded_paths.size()


static func sync_miss_count() -> int:
	return _sync_miss_count


static func headless_prefetch_diagnostics() -> Dictionary:
	return {"load_count": _headless_prefetch_load_count, "failure_count": _headless_prefetch_failures.size()}


static func _use_headless_serial_prefetch() -> bool:
	return DisplayServer.get_name() == "headless" and not _test_force_threaded_prefetch


static func clear_for_test() -> void:
	_textures.clear()
	_threaded_paths.clear()
	_sync_miss_count = 0
	_headless_prefetch_load_count = 0
	_headless_prefetch_failures.clear()
	_test_force_threaded_prefetch = false
