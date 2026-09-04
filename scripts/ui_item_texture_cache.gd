class_name UIItemTextureCache
extends RefCounted

static var _textures: Dictionary = {}
static var _threaded_paths: Dictionary = {}
static var _sync_miss_count := 0


static func texture_for(record: Dictionary, field := "inventoryIcon") -> Texture2D:
	var art: Variant = record.get("art", {})
	if not art is Dictionary:
		return null
	var source: Variant = art.get(field, {})
	var path := str(source.get("path", "")) if source is Dictionary else str(source)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return texture_at_path(path)


static func texture_at_path(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if _textures.has(path):
		return _textures[path] as Texture2D
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
	for raw_path: Variant in paths:
		var path := str(raw_path)
		if path.is_empty() or _textures.has(path) or _threaded_paths.has(path) or not ResourceLoader.exists(path):
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


static func clear_for_test() -> void:
	_textures.clear()
	_threaded_paths.clear()
	_sync_miss_count = 0
