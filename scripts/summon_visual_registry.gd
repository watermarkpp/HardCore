class_name SummonVisualRegistry
extends RefCounted

const SUMMON_BASELINE_PATH := "res://assets/data/vanilla_176/taoist_summon_baseline.json"
const DIVINE_BEAST_MANIFEST_PATH := "res://assets/data/vanilla_176/divine_beast_animation.json"
const DIVINE_BEAST_CONTRACT_ID := "summon.visual.divine_beast.directional.v1"
const SERIAL_STREAMING_CONTRACT_ID := (
	"summon.visual.streaming.serial_idle_preview.v1"
)
const REQUIRED_ACTIONS: Array[String] = ["idle", "walk", "attack", "hit", "death"]

const REQUEST_READY := -1
const REQUEST_UNKNOWN := 0
const REQUEST_FAILED := -2

static var _profile_cache: Dictionary = {}
## Synchronous raw-file decode counter. Production must never increase it.
static var _sync_image_load_count := 0
static var _async_request_count := 0
static var _async_ready_count := 0
static var _async_failure_count := 0
static var _last_loaded_image_count := 0
static var _threaded_resource_request_count := 0
static var _threaded_resource_ready_count := 0
static var _main_thread_blocking_load_count := 0
static var _max_resources_finalized_in_one_poll := 0
static var _max_resources_in_flight_per_profile := 0

static var _request_serial := 0
static var _pending_requests: Dictionary = {}
static var _request_owners: Dictionary = {}
static var _failed_summon_ids: Dictionary = {}


## Synchronous API kept for deterministic callers/tests. Production summon
## actors must use request_profile()/poll_profile() so imported Texture2D
## resources are loaded by ResourceLoader's worker pool.
static func profile(summon_id: String) -> Dictionary:
	if _profile_cache.has(summon_id):
		return (_profile_cache[summon_id] as Dictionary).duplicate()
	var result := _load_sync_profile(summon_id)
	if result.is_empty():
		return {}
	_profile_cache[summon_id] = result
	return result.duplicate()


## Starts an idle-first serial imported-Texture2D stream for a summon profile
## and returns a request id. Returns REQUEST_READY when the profile is already
## cached and REQUEST_UNKNOWN when the plan is invalid.
static func request_profile(summon_id: String) -> int:
	if _profile_cache.has(summon_id):
		return REQUEST_READY
	if _failed_summon_ids.has(summon_id):
		return REQUEST_FAILED
	if _pending_requests.has(summon_id):
		return int(_pending_requests[summon_id].get("request_id", REQUEST_UNKNOWN))
	var plan := _build_load_plan(summon_id)
	if plan.is_empty():
		return REQUEST_UNKNOWN
	_request_serial += 1
	var request_id := _request_serial
	var resource_entries := _resource_entries_from_plan(plan)
	if resource_entries.is_empty():
		return REQUEST_UNKNOWN
	_pending_requests[summon_id] = {
		"request_id": request_id,
		"plan": plan,
		"resources": resource_entries,
		"textures": {},
		"finalized_count": 0,
		"active_resource_index": -1,
		"next_request_index": 0,
		"preview_profile": {},
	}
	_request_owners[request_id] = summon_id
	_async_request_count += 1
	if not _request_next_resource(summon_id):
		return REQUEST_FAILED
	return request_id


## Non-blocking readiness poll. It finalizes at most one already-loaded
## Texture2D per call, returns the assembled profile once all are ready,
## {} while loading, and
## {} for a finished-but-failed request (removed from the active request map).
static func poll_profile(request_id: int) -> Dictionary:
	if request_id <= REQUEST_UNKNOWN:
		return {}
	## Resolve the owner before reaping: a completed request is erased from
	## _request_owners, but its assembled profile is then available in the
	## cache and must be returned to this poller.
	var summon_id := str(_request_owners.get(request_id, ""))
	_poll_request_once(summon_id)
	if not summon_id.is_empty() and _profile_cache.has(summon_id):
		return (_profile_cache[summon_id] as Dictionary).duplicate()
	if _request_owners.has(request_id):
		return {}
	return {}


static func request_active(request_id: int) -> bool:
	return request_id > REQUEST_UNKNOWN and _request_owners.has(request_id)


static func preview_profile(request_id: int) -> Dictionary:
	var summon_id := str(_request_owners.get(request_id, ""))
	if summon_id.is_empty() or not _pending_requests.has(summon_id):
		return {}
	var preview: Dictionary = _pending_requests[summon_id].get(
		"preview_profile",
		{}
	)
	return preview.duplicate() if not preview.is_empty() else {}


## Advances each pending imported-resource request once. ResourceLoader owns
## its worker lifetime, so actor teardown never joins a custom thread.
static func reap_completed_requests() -> void:
	for summon_id: String in _pending_requests.keys():
		var ready_before := _threaded_resource_ready_count
		_poll_request_once(summon_id)
		if _threaded_resource_ready_count > ready_before:
			return


static func clear_cache_for_tests() -> void:
	_pending_requests.clear()
	_request_owners.clear()
	_failed_summon_ids.clear()
	_profile_cache = {}
	_sync_image_load_count = 0
	_async_request_count = 0
	_async_ready_count = 0
	_async_failure_count = 0
	_last_loaded_image_count = 0
	_threaded_resource_request_count = 0
	_threaded_resource_ready_count = 0
	_main_thread_blocking_load_count = 0
	_max_resources_finalized_in_one_poll = 0
	_max_resources_in_flight_per_profile = 0


static func async_diagnostics() -> Dictionary:
	return {
		"sync_image_load_count": _sync_image_load_count,
		"async_request_count": _async_request_count,
		"async_ready_count": _async_ready_count,
		"async_failure_count": _async_failure_count,
		"last_loaded_image_count": _last_loaded_image_count,
		"pending_request_count": _pending_requests.size(),
		"failed_profile_count": _failed_summon_ids.size(),
		"threaded_resource_request_count": _threaded_resource_request_count,
		"threaded_resource_ready_count": _threaded_resource_ready_count,
		"ready_count": _threaded_resource_ready_count,
		"main_thread_blocking_load_count": _main_thread_blocking_load_count,
		"max_resources_finalized_in_one_poll": _max_resources_finalized_in_one_poll,
		"max_resources_in_flight_per_profile": _max_resources_in_flight_per_profile,
		"streaming_contract_id": SERIAL_STREAMING_CONTRACT_ID,
	}


static func _request_next_resource(summon_id: String) -> bool:
	if not _pending_requests.has(summon_id):
		return false
	var entry: Dictionary = _pending_requests[summon_id]
	var resources: Array = entry.get("resources", [])
	var next_index := int(entry.get("next_request_index", 0))
	if next_index >= resources.size():
		return true
	var resource_entry: Dictionary = resources[next_index]
	var path := str(resource_entry.get("path", ""))
	var error := ResourceLoader.load_threaded_request(
		path,
		"Texture2D",
		false,
		ResourceLoader.CACHE_MODE_REUSE
	)
	if error != OK:
		_finish_request(int(entry.get("request_id", 0)), {
			"ok": false,
			"error": "threaded_request_failed:%s:%d" % [path, error],
			"loaded_image_count": int(entry.get("finalized_count", 0)),
		})
		return false
	entry["active_resource_index"] = next_index
	entry["next_request_index"] = next_index + 1
	_pending_requests[summon_id] = entry
	_threaded_resource_request_count += 1
	_max_resources_in_flight_per_profile = maxi(
		_max_resources_in_flight_per_profile,
		1
	)
	return true


static func _poll_request_once(summon_id: String) -> void:
	if not _pending_requests.has(summon_id):
		return
	var entry: Dictionary = _pending_requests[summon_id]
	var resources: Array = entry.get("resources", [])
	var textures: Dictionary = entry.get("textures", {})
	var active_index := int(entry.get("active_resource_index", -1))
	if active_index < 0 or active_index >= resources.size():
		return
	var finalized_this_poll := 0
	var resource_entry: Dictionary = resources[active_index]
	var resource_key := str(resource_entry.get("key", ""))
	var path := str(resource_entry.get("path", ""))
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_finish_request(int(entry.get("request_id", 0)), {
			"ok": false,
			"error": "threaded_resource_failed:%s:%d" % [path, status],
			"loaded_image_count": int(entry.get("finalized_count", 0)),
		})
		return
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		return
	var texture := ResourceLoader.load_threaded_get(path) as Texture2D
	if texture == null:
		_finish_request(int(entry.get("request_id", 0)), {
			"ok": false,
			"error": "threaded_resource_not_texture:%s" % path,
			"loaded_image_count": int(entry.get("finalized_count", 0)),
		})
		return
	textures[resource_key] = texture
	entry["textures"] = textures
	entry["finalized_count"] = int(entry.get("finalized_count", 0)) + 1
	entry["active_resource_index"] = -1
	if resource_key == "idle":
		entry["preview_profile"] = _build_idle_preview_profile(
			entry.get("plan", {}),
			texture
		)
	_pending_requests[summon_id] = entry
	_threaded_resource_ready_count += 1
	finalized_this_poll = 1
	_max_resources_finalized_in_one_poll = maxi(
		_max_resources_finalized_in_one_poll,
		finalized_this_poll
	)
	if int(entry.get("finalized_count", 0)) < resources.size():
		_request_next_resource(summon_id)
		return
	var profile := _build_profile_from_threaded_textures(
		entry.get("plan", {}),
		textures
	)
	_finish_request(int(entry.get("request_id", 0)), {
		"ok": not profile.is_empty(),
		"error": "" if not profile.is_empty() else "invalid_threaded_profile",
		"loaded_image_count": int(entry.get("finalized_count", 0)),
		"profile": profile,
	})


static func _build_idle_preview_profile(
	plan: Dictionary,
	idle_texture: Texture2D
) -> Dictionary:
	if plan.is_empty() or idle_texture == null:
		return {}
	var idle_frame_count := int(
		plan.get("frame_counts", {}).get("idle", 1)
	)
	var idle_frame_ms := int(plan.get("frame_ms", {}).get("idle", 200))
	var preview := {
		"contract_id": str(plan.get("contract_id", "")),
		"direction_mode": str(plan.get("direction_mode", "")),
		"frame_size": plan.get("frame_size", Vector2i.ZERO),
		"foot_anchor": plan.get("foot_anchor", Vector2i.ZERO),
		"actor_ground_offset": plan.get("actor_ground_offset", Vector2i.ZERO),
		"stable_body_top": int(plan.get("stable_body_top", 0)),
		"frame_counts": {},
		"frame_ms": {},
		"streaming_preview": true,
	}
	for action_name: String in REQUIRED_ACTIONS:
		preview[action_name] = idle_texture
		preview.frame_counts[action_name] = idle_frame_count
		preview.frame_ms[action_name] = idle_frame_ms
	preview.attack_release_frame_index = int(
		plan.get("attack_release_frame_index", 5)
	)
	preview.attack_release_ms = int(plan.get("attack_release_ms", 500))
	return preview


static func _finish_request(request_id: int, result: Dictionary) -> void:
	var summon_id := str(_request_owners.get(request_id, ""))
	if summon_id.is_empty():
		## Idempotent: a stale completed entry (e.g. after a test-injected
		## finish or a reaped request) must never double-count or rejoin.
		return
	_request_owners.erase(request_id)
	_pending_requests.erase(summon_id)
	_last_loaded_image_count = int(result.get("loaded_image_count", 0))
	if not bool(result.get("ok", false)):
		_async_failure_count += 1
		_failed_summon_ids[summon_id] = true
		return
	var profile: Dictionary = result.get("profile", {})
	if profile.is_empty():
		_async_failure_count += 1
		_failed_summon_ids[summon_id] = true
		return
	_async_ready_count += 1
	_profile_cache[summon_id] = profile

static func _build_profile_from_threaded_textures(
	plan: Dictionary,
	textures: Dictionary
) -> Dictionary:
	var profile := _build_action_profile_from_textures(plan, textures)
	if profile.is_empty():
		return {}
	var fire_path := str(plan.get("fire_path", ""))
	if fire_path.is_empty():
		return profile
	var fire_texture := textures.get("fire", null) as Texture2D
	var fire_expected: Vector2i = plan.get("fire_expected_size", Vector2i.ZERO)
	if fire_texture == null or fire_texture.get_size() != Vector2(fire_expected.x, fire_expected.y):
		return {}
	profile.fire = fire_texture
	profile.fire_frame_size = plan.get("fire_frame_size", Vector2i.ZERO)
	profile.fire_foot_anchor = plan.get("fire_foot_anchor", Vector2i.ZERO)
	profile.fire_actor_ground_offset = plan.get("fire_actor_ground_offset", Vector2i.ZERO)
	profile.fire_frame_count = int(plan.get("fire_frame_count", 0))
	profile.fire_frame_ms = int(plan.get("fire_frame_ms", 100))
	profile.attack_release_frame_index = int(plan.get("attack_release_frame_index", 5))
	profile.attack_release_ms = int(plan.get("attack_release_ms", 500))
	return profile


static func _resource_entries_from_plan(plan: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var image_paths: Dictionary = plan.get("image_paths", {})
	for action_name: String in REQUIRED_ACTIONS:
		var path := str(image_paths.get(action_name, ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			return []
		entries.append({"key": action_name, "path": path})
	var fire_path := str(plan.get("fire_path", ""))
	if not fire_path.is_empty():
		if not ResourceLoader.exists(fire_path):
			return []
		entries.append({"key": "fire", "path": fire_path})
	return entries


static func _assemble_profile(result: Dictionary) -> Dictionary:
	var plan: Dictionary = result.get("plan", {})
	var images: Dictionary = result.get("images", {})
	if plan.is_empty() or images.is_empty():
		return {}
	var profile := {
		"contract_id": str(plan.get("contract_id", "")),
		"direction_mode": str(plan.get("direction_mode", "")),
		"frame_size": plan.get("frame_size", Vector2i.ZERO),
		"foot_anchor": plan.get("foot_anchor", Vector2i.ZERO),
		"actor_ground_offset": plan.get("actor_ground_offset", Vector2i.ZERO),
		"stable_body_top": int(plan.get("stable_body_top", 0)),
		"frame_counts": (plan.get("frame_counts", {}) as Dictionary).duplicate(),
		"frame_ms": (plan.get("frame_ms", {}) as Dictionary).duplicate(),
	}
	for action_name: String in REQUIRED_ACTIONS:
		var image: Image = images.get(action_name, null)
		if image == null:
			return {}
		profile[action_name] = ImageTexture.create_from_image(image)
	var summon_id := str(plan.get("summon_id", ""))
	if summon_id == "divine_beast":
		var fire_image: Image = images.get("fire", null)
		if fire_image == null:
			return {}
		profile.fire = ImageTexture.create_from_image(fire_image)
		profile.fire_frame_size = plan.get("fire_frame_size", Vector2i.ZERO)
		profile.fire_foot_anchor = plan.get("fire_foot_anchor", Vector2i.ZERO)
		profile.fire_actor_ground_offset = plan.get(
			"fire_actor_ground_offset",
			Vector2i.ZERO
		)
		profile.fire_frame_count = int(plan.get("fire_frame_count", 0))
		profile.fire_frame_ms = int(plan.get("fire_frame_ms", 100))
		profile.attack_release_frame_index = int(
			plan.get("attack_release_frame_index", 5)
		)
		profile.attack_release_ms = int(plan.get("attack_release_ms", 500))
	return profile


static func _load_sync_profile(summon_id: String) -> Dictionary:
	var plan := _build_load_plan(summon_id)
	if plan.is_empty():
		return {}
	var result := _build_action_profile_from_plan(plan)
	if result.is_empty():
		return {}
	if summon_id == "divine_beast":
		var fire_path := str(plan.get("fire_path", ""))
		if fire_path.is_empty():
			return {}
		var fire_texture := _load_texture(fire_path)
		var fire_expected: Vector2i = plan.get(
			"fire_expected_size",
			Vector2i.ZERO
		)
		if (
			fire_texture == null
			or fire_texture.get_size() != Vector2(
				fire_expected.x,
				fire_expected.y
			)
		):
			return {}
		result.fire = fire_texture
		result.fire_frame_size = plan.get("fire_frame_size", Vector2i.ZERO)
		result.fire_foot_anchor = plan.get("fire_foot_anchor", Vector2i.ZERO)
		result.fire_actor_ground_offset = plan.get(
			"fire_actor_ground_offset",
			Vector2i.ZERO
		)
		result.fire_frame_count = int(plan.get("fire_frame_count", 0))
		result.fire_frame_ms = int(plan.get("fire_frame_ms", 100))
		result.attack_release_frame_index = int(
			plan.get("attack_release_frame_index", 5)
		)
		result.attack_release_ms = int(plan.get("attack_release_ms", 500))
	return result


static func _build_load_plan(summon_id: String) -> Dictionary:
	if summon_id == "divine_beast":
		return _build_divine_beast_plan()
	if summon_id == "skeleton":
		return _build_skeleton_plan()
	return {}


static func _build_skeleton_plan() -> Dictionary:
	var parsed := _read_json(SUMMON_BASELINE_PATH)
	var templates: Dictionary = parsed.get("templates", {})
	var skeleton: Dictionary = templates.get("skeleton", {})
	var visual: Dictionary = skeleton.get("visual", {})
	return _build_action_metadata(
		str(visual.get("contract_id", "")),
		str(visual.get("direction_mode", "")),
		visual.get("frame_size", []),
		visual.get("foot_anchor", []),
		visual.get("actor_ground_offset", []),
		int(visual.get("stable_body_top", 0)),
		visual.get("actions", {}),
		"frames_per_direction",
		"frame_ms",
		"skeleton"
	)


static func _build_divine_beast_plan() -> Dictionary:
	var parsed := _read_json(DIVINE_BEAST_MANIFEST_PATH)
	if str(parsed.get("contract_id", "")) != DIVINE_BEAST_CONTRACT_ID:
		return {}
	var result := _build_action_metadata(
		DIVINE_BEAST_CONTRACT_ID,
		str(parsed.get("directionMode", "")),
		parsed.get("frameSize", []),
		parsed.get("footAnchor", []),
		parsed.get("actorGroundOffset", []),
		int(parsed.get("stableBodyTop", 39)),
		parsed.get("actions", {}),
		"framesPerDirection",
		"frameMs",
		"divine_beast"
	)
	if result.is_empty():
		return {}
	var fire: Dictionary = parsed.get("fire", {})
	var fire_path := str(fire.get("path", ""))
	var fire_frame_size := _vector2i(fire.get("frameSize", []))
	var fire_foot_anchor := _vector2i(fire.get("footAnchor", []))
	var fire_ground_offset := _vector2i(fire.get("actorGroundOffset", []))
	var fire_frame_count := int(fire.get("framesPerDirection", 0))
	if (
		fire_path.is_empty()
		or fire_frame_size == Vector2i.ZERO
		or fire_frame_count <= 0
	):
		return {}
	result["fire_path"] = fire_path
	result["fire_expected_size"] = Vector2i(
		fire_frame_size.x * fire_frame_count,
		fire_frame_size.y * 8
	)
	result["fire_frame_size"] = fire_frame_size
	result["fire_foot_anchor"] = fire_foot_anchor
	result["fire_actor_ground_offset"] = fire_ground_offset
	result["fire_frame_count"] = fire_frame_count
	result["fire_frame_ms"] = int(fire.get("frameMs", 100))
	result["attack_release_frame_index"] = int(
		parsed.get("attackReleaseFrameIndex", 5)
	)
	result["attack_release_ms"] = int(parsed.get("attackReleaseMs", 500))
	return result


static func _build_action_metadata(
	contract_id: String,
	direction_mode: String,
	frame_size_data: Variant,
	foot_anchor_data: Variant,
	ground_offset_data: Variant,
	stable_body_top: int,
	actions_value: Variant,
	frame_count_key: String,
	frame_ms_key: String,
	summon_id: String
) -> Dictionary:
	if contract_id.is_empty() or not actions_value is Dictionary:
		return {}
	var frame_size := _vector2i(frame_size_data)
	var foot_anchor := _vector2i(foot_anchor_data)
	var ground_offset := _vector2i(ground_offset_data)
	if frame_size == Vector2i.ZERO:
		return {}
	var actions: Dictionary = actions_value
	var image_paths: Dictionary = {}
	var expected_sizes: Dictionary = {}
	var frame_counts: Dictionary = {}
	var frame_ms: Dictionary = {}
	for action_name: String in REQUIRED_ACTIONS:
		var action: Dictionary = actions.get(action_name, {})
		var path := str(action.get("path", ""))
		var frame_count := int(action.get(frame_count_key, 0))
		if path.is_empty() or frame_count <= 0:
			return {}
		image_paths[action_name] = path
		expected_sizes[action_name] = Vector2i(
			frame_size.x * frame_count,
			frame_size.y * 8
		)
		frame_counts[action_name] = frame_count
		frame_ms[action_name] = int(action.get(frame_ms_key, 100))
	return {
		"summon_id": summon_id,
		"contract_id": contract_id,
		"direction_mode": direction_mode,
		"frame_size": frame_size,
		"foot_anchor": foot_anchor,
		"actor_ground_offset": ground_offset,
		"stable_body_top": stable_body_top,
		"image_paths": image_paths,
		"expected_texture_sizes": expected_sizes,
		"frame_counts": frame_counts,
		"frame_ms": frame_ms,
	}


static func _build_action_profile_from_plan(plan: Dictionary) -> Dictionary:
	var textures: Dictionary = {}
	var image_paths: Dictionary = plan.get("image_paths", {})
	for action_name: String in REQUIRED_ACTIONS:
		var path := str(image_paths.get(action_name, ""))
		if path.is_empty():
			return {}
		textures[action_name] = _load_texture(path)
	return _build_action_profile_from_textures(plan, textures)


static func _build_action_profile_from_textures(
	plan: Dictionary,
	textures: Dictionary
) -> Dictionary:
	if plan.is_empty():
		return {}
	var frame_size: Vector2i = plan.get("frame_size", Vector2i.ZERO)
	var foot_anchor: Vector2i = plan.get("foot_anchor", Vector2i.ZERO)
	var ground_offset: Vector2i = plan.get("actor_ground_offset", Vector2i.ZERO)
	var result := {
		"contract_id": str(plan.get("contract_id", "")),
		"direction_mode": str(plan.get("direction_mode", "")),
		"frame_size": frame_size,
		"foot_anchor": foot_anchor,
		"actor_ground_offset": ground_offset,
		"stable_body_top": int(plan.get("stable_body_top", 0)),
		"frame_counts": (plan.get("frame_counts", {}) as Dictionary).duplicate(),
		"frame_ms": (plan.get("frame_ms", {}) as Dictionary).duplicate(),
	}
	var expected_sizes: Dictionary = plan.get("expected_texture_sizes", {})
	for action_name: String in REQUIRED_ACTIONS:
		var texture := textures.get(action_name, null) as Texture2D
		var frame_count := int(
			plan.get("frame_counts", {}).get(action_name, 0)
		)
		var expected_size: Vector2i = expected_sizes.get(
			action_name,
			Vector2i.ZERO
		)
		if (
			texture == null
			or frame_count <= 0
			or texture.get_size() != Vector2(expected_size.x, expected_size.y)
		):
			return {}
		result[action_name] = texture
	return result


static func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed if parsed is Dictionary else {}


static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		_main_thread_blocking_load_count += 1
		return load(path) as Texture2D
	## Exported builds do not guarantee a filesystem path for imported assets;
	## never fall back to Image.load_from_file. Missing imports are terminal.
	return null


static func _vector2i(value: Variant) -> Vector2i:
	if not value is Array or value.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(value[0]), int(value[1]))
