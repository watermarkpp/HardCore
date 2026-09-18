extends RefCounted

## Exact-ID presentation sources. ResourceLoader owns background decoding;
## combat never waits for a texture and never changes a damage transaction.
const MANIFEST := "res://assets/data/monster_attack_overlay_sources_v2.json"
const CACHE_BUDGET := 48 * 1024 * 1024
const MAX_IN_FLIGHT := 2
static var _data: Dictionary = {}
static var _requested: Dictionary = {}
static var _textures: Dictionary = {}
static var _queue: Array[String] = []
static var _last_use: Dictionary = {}
static var _resident_bytes := 0
static var _last_poll_frame := -1
## Separated overlay-channel counters (perf-smoothness-r1 Phase A, PERF-01):
## this cache owns ONLY special-attack overlay frames. The monster BODY
## atlases live in MonsterVisualStreamingCoordinator and must never be
## inferred from these numbers.
static var _loads := 0
static var _evictions := 0

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if parsed is Dictionary: _data = parsed
	return _data

static func profile_for_id(monster_id: int) -> Dictionary:
	var key := str(data().get("profile_by_monster_id", {}).get(str(monster_id), ""))
	if monster_id == 224: key = "cow_king"
	return data().get("profiles", {}).get(key, {})

static func request_profile(profile: Dictionary, direction := 0) -> void:
	var count := int(profile.get("frame_count", profile.get("frames_per_direction", 0)))
	var records: Array = profile.get("frames", [])
	for index in range(direction * count, mini((direction + 1) * count, records.size())):
		request(str(records[index].path))

static func request(path: String) -> void:
	if _textures.has(path) or _requested.has(path) or _queue.has(path): return
	_queue.append(path)

static func poll() -> void:
	var frame := Engine.get_process_frames()
	if frame == _last_poll_frame: return
	_last_poll_frame = frame
	for path: String in _requested.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var loaded := ResourceLoader.load_threaded_get(path) as Texture2D
			_requested.erase(path)
			if loaded == null: continue
			_loads += 1
			var bytes := loaded.get_width() * loaded.get_height() * 4
			while _resident_bytes + bytes > CACHE_BUDGET and not _textures.is_empty():
				var oldest := str(_textures.keys()[0])
				for key: String in _textures:
					if int(_last_use[key]) < int(_last_use[oldest]): oldest = key
				var old: Texture2D = _textures[oldest]
				_resident_bytes -= old.get_width() * old.get_height() * 4
				_textures.erase(oldest)
				_last_use.erase(oldest)
				_evictions += 1
			_textures[path] = loaded
			_last_use[path] = frame
			_resident_bytes += bytes
		elif status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			_requested.erase(path)
	while _requested.size() < MAX_IN_FLIGHT and not _queue.is_empty():
		var path: String = _queue.pop_front()
		if ResourceLoader.load_threaded_request(path, "Texture2D") == OK:
			_requested[path] = true

static func texture(path: String) -> Texture2D:
	poll()
	if _textures.has(path):
		_last_use[path] = Engine.get_process_frames()
		return _textures[path]
	# A currently drawn frame goes ahead of speculative direction prefetches.
	# Keep the same two-request limit; combat never joins the loader thread.
	if not _requested.has(path):
		_queue.erase(path)
		_queue.push_front(path)
	return null


static func resident_texture_count() -> int:
	# FRAME-STALL diagnostics: how many monster OVERLAY frame textures are
	# resident. Read by the GameRoot long-frame probe; no behavioral effect.
	# Prefer diagnostics() at new call sites: this count says nothing about
	# the monster body atlases owned by the streaming coordinator.
	return _textures.size()


## Separated overlay-channel diagnostics (perf-smoothness-r1 Phase A).
## Read-only facts: entries, resident bytes, queue state and lifetime
## load/eviction totals for THIS overlay cache only.
static func diagnostics() -> Dictionary:
	return {
		"entries": _textures.size(),
		"resident_bytes": _resident_bytes,
		"requested": _requested.size(),
		"queued": _queue.size(),
		"loads": _loads,
		"evictions": _evictions,
	}
