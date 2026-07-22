class_name MonsterVisual
extends Node2D

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const BOSS_ART_PATH := "res://assets/data/classic_boss_client_art_sources.json"
const COMPLETE_ART_PATH := "res://assets/data/complete_monster_client_art_sources.json"
# WIL px/py values are relative to the classic DrawChr origin, not to the
# actor's ground point. The player client-art path already migrates this same
# origin by (+32,+28); monsters must use the identical coordinate conversion.
const CLIENT_ACTOR_GROUND_OFFSET := Vector2i(32, 28)
const HEALTH_BAR_FRAME_MARGIN := 8.0
const CLIENT_RESOURCE_CACHE_CAPACITY := 12
const CLIENT_RESOURCE_CACHE_BUDGET_BYTES := 64 * 1024 * 1024
const VISUAL_ACTIVATION_DISTANCE := 1600.0
const VISUAL_RELEASE_DISTANCE := 2000.0
const RESOURCE_RESIDENCY_CHECK_SECONDS := 0.12
const MAX_CONCURRENT_PROFILE_LOADS := 2
const ACTOR_Y_SORT_RENDER_DOMAIN := "actor_y_sort"
const ACTOR_Y_SORT_RENDER_CONTRACT := "monster.actor_y_sort.v1"

static var _boss_art: Dictionary = {}
static var _complete_art: Dictionary = {}
static var _client_resource_profiles: Dictionary = {}
static var _client_resource_profile_lru: Array[String] = []
static var _client_resource_profile_bytes: Dictionary = {}
static var _client_resource_cache_bytes := 0
static var _client_texture_load_request_count := 0
static var _threaded_profile_requests: Dictionary = {}
static var _threaded_profile_queue: Array[String] = []
static var _threaded_texture_request_count := 0
static var _threaded_texture_get_count := 0
static var _map_prefetch_keys: Array[String] = []
static var _map_pinned_profile_keys: Dictionary = {}
static var _map_prefetch_completed_keys: Dictionary = {}
static var _map_pinned_bytes := 0
static var _map_prefetch_generation := 0
static var _last_streaming_poll_frame := -1
static var _synchronous_loading_for_tests := true

var actor: EnemyActor
var sprite: Sprite2D
var active_resources: Dictionary = {}
var current_state := "idle"
var current_direction := 0
var current_frame := 0
var frame_size := ArtSpec.MONSTER_FRAME
var foot_anchor := ArtSpec.MONSTER_FOOT_ANCHOR
var actor_ground_offset := Vector2i.ZERO
var health_bar_top_by_direction: Array = []
var _elapsed := 0.0
var _last_state := ""
var _attack_remaining := 0.0
var _hit_remaining := 0.0
var _death_remaining := 0.0
var _action_duration := 0.0
var _fixed_health_bar_y := 0.0
var _render_state_update_count := 0
var _resource_residency_timer := 0.0


static func configure_actor_y_sort_item(item: CanvasItem, role: String) -> void:
	# Keep the complete monster composite under EnemyActor's GameRoot Y-sort key.
	item.z_index = 0
	item.z_as_relative = true
	item.y_sort_enabled = false
	item.show_behind_parent = false
	item.set_as_top_level(false)
	item.set_meta("monster_render_domain", ACTOR_Y_SORT_RENDER_DOMAIN)
	item.set_meta("monster_render_contract", ACTOR_Y_SORT_RENDER_CONTRACT)
	item.set_meta("monster_render_role", role)


func setup(owner_actor: EnemyActor) -> void:
	actor = owner_actor


func _ready() -> void:
	configure_actor_y_sort_item(self, "visual_root")
	# 普通怪下沉4px，Boss下沉6px，使脚底与阴影中心实际重叠。
	position = Vector2(0, 6 if actor.is_boss else 4)
	visible = false
	sprite = Sprite2D.new()
	sprite.name = "BodySprite"
	configure_actor_y_sort_item(sprite, "body_sprite")
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2.ZERO, frame_size)
	sprite.centered = false
	sprite.position = -Vector2(foot_anchor + actor_ground_offset)
	# Every action and direction uses the same authored frame rectangle and foot
	# anchor. Pin UI to that rectangle's upper edge instead of the current
	# animation pixels, so a changing pose can never move the health bar through
	# the monster's head, chest, or waist.
	_fixed_health_bar_y = position.y + sprite.position.y - HEALTH_BAR_FRAME_MARGIN
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	_resource_residency_timer = RESOURCE_RESIDENCY_CHECK_SECONDS * float(posmod(get_instance_id(), 7)) / 7.0
	if _inside_visual_distance(VISUAL_ACTIVATION_DISTANCE):
		_activate_resources()


func _process(delta: float) -> void:
	if not is_instance_valid(actor):
		return
	poll_streaming()
	_attack_remaining = maxf(0.0, _attack_remaining - delta)
	_hit_remaining = maxf(0.0, _hit_remaining - delta)
	_death_remaining = maxf(0.0, _death_remaining - delta)
	_resource_residency_timer -= delta
	if _resource_residency_timer <= 0.0:
		_resource_residency_timer = RESOURCE_RESIDENCY_CHECK_SECONDS
		if active_resources.is_empty():
			if _inside_visual_distance(VISUAL_ACTIVATION_DISTANCE):
				_activate_resources()
		elif not _inside_visual_distance(VISUAL_RELEASE_DISTANCE):
			_release_resources()
	if active_resources.is_empty() or not visible:
		return
	if _death_remaining > 0.0:
		current_state = "death"
	elif _attack_remaining > 0.0:
		current_state = "attack"
	elif _hit_remaining > 0.0:
		current_state = "hit"
	elif actor.velocity.length_squared() > 25.0:
		current_state = "walk"
	else:
		current_state = "idle"
	var visual_facing: Vector2 = actor.movement_facing if current_state == "walk" else actor.facing
	current_direction = _direction_row(visual_facing)
	if current_state != _last_state:
		_elapsed = 0.0
		_last_state = current_state
	_elapsed += delta
	var frame_count := MonsterAnimationPolicy.frame_count(active_resources, StringName(current_state))
	if current_state in ["attack", "hit", "death"]:
		var progress := clampf(_elapsed / maxf(_action_duration, 0.001), 0.0, 0.999)
		current_frame = mini(frame_count - 1, int(floor(progress * frame_count)))
	else:
		var fps := MonsterAnimationPolicy.loop_fps(StringName(current_state))
		current_frame = int(floor(_elapsed * fps)) % frame_count
	var next_region := Rect2(current_frame * frame_size.x, current_direction * frame_size.y, frame_size.x, frame_size.y)
	if sprite.texture != active_resources[current_state] or sprite.region_rect != next_region:
		_apply_render_state(active_resources[current_state], next_region)


func _inside_visual_distance(distance: float) -> bool:
	if not is_instance_valid(actor) or not is_instance_valid(actor.primary_target):
		return true
	return actor.global_position.distance_squared_to(actor.primary_target.global_position) <= distance * distance


func _activate_resources() -> void:
	if not active_resources.is_empty():
		return
	var resources := _resources_for(actor.monster_data)
	if resources.is_empty():
		return
	active_resources = resources
	frame_size = resources.get("frame_size", ArtSpec.MONSTER_FRAME)
	foot_anchor = resources.get("foot_anchor", ArtSpec.MONSTER_FOOT_ANCHOR)
	actor_ground_offset = resources.get("actor_ground_offset", Vector2i.ZERO)
	health_bar_top_by_direction = resources.get("health_bar_top_by_direction", [])
	sprite.region_rect = Rect2(Vector2.ZERO, frame_size)
	sprite.position = -Vector2(foot_anchor + actor_ground_offset)
	_fixed_health_bar_y = position.y + sprite.position.y - HEALTH_BAR_FRAME_MARGIN
	visible = not actor._burrowed
	_last_state = ""
	_apply_render_state(active_resources["idle"], Rect2(Vector2.ZERO, frame_size))


func _release_resources() -> void:
	if active_resources.is_empty():
		return
	visible = false
	sprite.texture = null
	active_resources = {}


func _resources_for(monster_data: Dictionary) -> Dictionary:
	var client_mapping := _client_mapping_for(monster_data)
	if not client_mapping.is_empty():
		return _client_resources(client_mapping)
	var monster_name := str(monster_data.get("name", actor.display_name if is_instance_valid(actor) else ""))
	var stable_lookup := MonsterIdentityScript.animation_lookup_name(monster_data)
	var lookup_names := [stable_lookup] if not stable_lookup.is_empty() else []
	if not monster_name.is_empty() and not lookup_names.has(monster_name):
		lookup_names.append(monster_name)
	if monster_name.ends_with("0"):
		lookup_names.append(monster_name.trim_suffix("0"))
	for lookup_name:String in lookup_names:
		var resources:=PresentationAssets.monster_resources(lookup_name)
		if not resources.is_empty():return resources
	return {}


func _client_mapping_for(monster_data: Dictionary) -> Dictionary:
	var monster_name := str(monster_data.get("name", actor.display_name if is_instance_valid(actor) else ""))
	var stable_lookup := MonsterIdentityScript.animation_lookup_name(monster_data)
	var lookup_names := [stable_lookup] if not stable_lookup.is_empty() else []
	if not monster_name.is_empty() and not lookup_names.has(monster_name):
		lookup_names.append(monster_name)
	if monster_name.ends_with("0"):
		lookup_names.append(monster_name.trim_suffix("0"))
	var monster_key := MonsterIdentityScript.stable_key(monster_data)
	var complete_manifest := _complete_art_manifest()
	if not monster_key.is_empty():
		var complete_mapping: Variant = complete_manifest.get("runtimeMappingsByMonsterId", {}).get(monster_key, {})
		if complete_mapping is Dictionary and not complete_mapping.is_empty():
			return complete_mapping
	var boss_manifest := _boss_art_manifest()
	if not monster_key.is_empty():
		var boss_mapping: Variant = boss_manifest.get("runtimeMappingsByMonsterId", {}).get(monster_key, {})
		if boss_mapping is Dictionary and not boss_mapping.is_empty():
			return boss_mapping
	for lookup_name: String in lookup_names:
		var legacy_boss_mapping: Variant = boss_manifest.get("runtimeMappings", {}).get(lookup_name, {})
		if legacy_boss_mapping is Dictionary and not legacy_boss_mapping.is_empty():
			return legacy_boss_mapping
	for manifest: Dictionary in [GameData.bich_common_art, GameData.bich_undead_art]:
		if not monster_key.is_empty():
			var id_mapping: Variant = manifest.get("runtimeMappingsByMonsterId", {}).get(monster_key, {})
			if id_mapping is String:
				id_mapping = manifest.get("runtimeMappings", {}).get(id_mapping, {})
			if id_mapping is Dictionary and not id_mapping.is_empty():
				return id_mapping
		for lookup_name:String in lookup_names:
			var canonical_name := str(manifest.get("legacyAliases", {}).get(lookup_name, lookup_name))
			var mapping: Variant = manifest.get("runtimeMappings", {}).get(canonical_name, {})
			if mapping is Dictionary and not mapping.is_empty():
				return mapping
	return {}


func _boss_art_manifest() -> Dictionary:
	if _boss_art.is_empty() and FileAccess.file_exists(BOSS_ART_PATH):
		var file := FileAccess.open(BOSS_ART_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		_boss_art = parsed if parsed is Dictionary else {}
	return _boss_art


func _complete_art_manifest() -> Dictionary:
	if _complete_art.is_empty() and FileAccess.file_exists(COMPLETE_ART_PATH):
		var file := FileAccess.open(COMPLETE_ART_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		_complete_art = parsed if parsed is Dictionary else {}
	return _complete_art


func ground_contact_offset() -> Vector2:
	return Vector2.ZERO


func ground_contact_position(fallback: Vector2) -> Vector2:
	return position if uses_final_art() else fallback


func health_bar_anchor_y(fallback_y: float) -> float:
	if not uses_final_art():
		return fallback_y
	if health_bar_top_by_direction.size() == 8:
		var direction := clampi(current_direction, 0, health_bar_top_by_direction.size() - 1)
		return position.y + sprite.position.y + float(health_bar_top_by_direction[direction]) - HEALTH_BAR_FRAME_MARGIN
	return _fixed_health_bar_y


func _direction_row(direction: Vector2) -> int:
	if str(active_resources.get("direction_policy", "mir2_directional")) == "fixed_source_direction":
		return 0
	# Raw Mon*.wil atlases are north-first. Project-authored turnaround atlases
	# are south-first. Every resource declares its convention here instead of
	# forcing one global mapping and breaking half the monster roster.
	return MonsterAnimationPolicy.direction_row(direction, StringName(str(active_resources.get("direction_mode", "logical_south_first"))))


func _client_resources(client_mapping: Dictionary) -> Dictionary:
	var cache_key := _client_resource_cache_key(client_mapping)
	var cached: Variant = _client_resource_profiles.get(cache_key, {})
	if cached is Dictionary and not cached.is_empty():
		_touch_client_resource_profile(cache_key)
		return cached
	# Unit/asset tests retain their deterministic immediate-load fixture. Runtime
	# activation never enters this branch: it queues the five atlases on the
	# threaded loader and keeps the cheap procedural fallback until ready.
	if not PlayerState.test_mode or not _synchronous_loading_for_tests:
		_request_client_profile(client_mapping, actor.monster_id if is_instance_valid(actor) else -1)
		return {}
	return _load_client_profile_synchronously(client_mapping)


func _client_profile_shell(client_mapping: Dictionary) -> Dictionary:
	var actions: Variant = client_mapping.get("actions", {})
	return {
		"frame_size": Vector2i(int(client_mapping.get("frameSize", [160, 160])[0]), int(client_mapping.get("frameSize", [160, 160])[1])),
		"foot_anchor": Vector2i(int(client_mapping.get("footAnchor", [80, 138])[0]), int(client_mapping.get("footAnchor", [80, 138])[1])),
		"actor_ground_offset": CLIENT_ACTOR_GROUND_OFFSET,
		"health_bar_top_by_direction": client_mapping.get("healthBarTopByDirection", []),
		"frame_counts": {},
		"direction_mode": "mir2_north_first",
		"direction_policy": str(client_mapping.get("directionPolicy", "mir2_directional")),
		"animation_source": "classic_client_wil",
	}


func _load_client_profile_synchronously(client_mapping: Dictionary) -> Dictionary:
	var cache_key := _client_resource_cache_key(client_mapping)
	var actions: Variant = client_mapping.get("actions", {})
	var result := _client_profile_shell(client_mapping)
	for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
		var action: Variant = actions.get(action_name, {}) if actions is Dictionary else {}
		var path := str(action.get("path", "")) if action is Dictionary else ""
		if path.is_empty():
			return {}
		var frame_count := int(action.get("framesPerDirection", 1))
		var texture := _load_client_texture(path, Vector2i(result.frame_size.x * frame_count, result.frame_size.y * 8))
		if texture == null:
			return {}
		result[action_name] = texture
		result["frame_counts"][action_name] = frame_count
	if not MonsterAnimationPolicy.validate(result).is_empty():
		return {}
	# Keep a bounded strong-reference window across nearby streamed areas. Godot's
	# resource cache may release an atlas after the last actor leaves; this LRU
	# prevents an immediate return from decoding/uploading all five actions again
	# without eventually retaining the entire 214-monster catalog on mobile.
	_retain_client_resource_profile(cache_key, result)
	return result


func _request_client_profile(client_mapping: Dictionary, monster_id := -1, map_generation := -1) -> void:
	var cache_key := _client_resource_cache_key(client_mapping)
	if _client_resource_profiles.has(cache_key):
		return
	if _threaded_profile_requests.has(cache_key):
		var existing: Dictionary = _threaded_profile_requests[cache_key]
		if map_generation >= 0:
			existing["map_generation"] = map_generation
			existing["monster_id"] = monster_id
			_threaded_profile_requests[cache_key] = existing
		return
	var paths := {}
	var expected_sizes := {}
	var frame_size_values: Array = client_mapping.get("frameSize", [160, 160])
	var frame_size := Vector2i(int(frame_size_values[0]), int(frame_size_values[1]))
	var actions: Dictionary = client_mapping.get("actions", {})
	for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
		var action: Dictionary = actions.get(action_name, {})
		var path := str(action.get("path", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			_threaded_profile_requests[cache_key] = {
				"state": "failed", "mapping": client_mapping,
				"monster_id": monster_id, "map_generation": map_generation,
				"failed_path": path,
			}
			return
		paths[action_name] = path
		expected_sizes[action_name] = frame_size * Vector2i(int(action.get("framesPerDirection", 1)), 8)
	_threaded_profile_requests[cache_key] = {
		"state": "queued",
		"mapping": client_mapping.duplicate(true),
		"paths": paths,
		"expected_sizes": expected_sizes,
		"monster_id": monster_id,
		"map_generation": map_generation,
	}
	_threaded_profile_queue.append(cache_key)
	_pump_threaded_profile_queue()


func _pump_threaded_profile_queue() -> void:
	var active_count := 0
	for job: Dictionary in _threaded_profile_requests.values():
		if str(job.get("state", "")) in ["loading", "loaded"]:
			active_count += 1
	while active_count < MAX_CONCURRENT_PROFILE_LOADS and not _threaded_profile_queue.is_empty():
		var cache_key: String = _threaded_profile_queue.pop_front()
		if not _threaded_profile_requests.has(cache_key):
			continue
		var job: Dictionary = _threaded_profile_requests[cache_key]
		if str(job.get("state", "")) != "queued":
			continue
		var paths: Dictionary = job.get("paths", {})
		var failed_path := ""
		for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
			var path := str(paths.get(action_name, ""))
			var request_error := ResourceLoader.load_threaded_request(path, "Texture2D", true)
			if request_error != OK:
				failed_path = path
				break
			_threaded_texture_request_count += 1
		if not failed_path.is_empty():
			job["state"] = "failed"
			job["failed_path"] = failed_path
		else:
			job["state"] = "loading"
			active_count += 1
		_threaded_profile_requests[cache_key] = job


func _retain_client_resource_profile(cache_key: String, resources: Dictionary) -> void:
	if _client_resource_profiles.has(cache_key):
		_client_resource_cache_bytes -= int(_client_resource_profile_bytes.get(cache_key, 0))
	_client_resource_profiles[cache_key] = resources
	var estimated_bytes := _estimated_client_profile_bytes(resources)
	_client_resource_profile_bytes[cache_key] = estimated_bytes
	_client_resource_cache_bytes += estimated_bytes
	_touch_client_resource_profile(cache_key)
	_evict_client_resource_profiles()


func _evict_client_resource_profiles() -> void:
	while (
		_client_resource_profile_lru.size() > CLIENT_RESOURCE_CACHE_CAPACITY
		or _client_resource_cache_bytes > CLIENT_RESOURCE_CACHE_BUDGET_BYTES
	):
		var expired_index := -1
		for index in range(_client_resource_profile_lru.size()):
			if not _map_pinned_profile_keys.has(_client_resource_profile_lru[index]):
				expired_index = index
				break
		if expired_index < 0:
			# Pin admission is budgeted before retention. Reaching this branch means
			# the pinned set alone owns the hard budget, so no unpinned profile may
			# be retained beyond it.
			return
		var expired_key: String = _client_resource_profile_lru.pop_at(expired_index)
		_client_resource_cache_bytes -= int(_client_resource_profile_bytes.get(expired_key, 0))
		_client_resource_profile_bytes.erase(expired_key)
		_client_resource_profiles.erase(expired_key)
	assert(_client_resource_profile_lru.size() <= CLIENT_RESOURCE_CACHE_CAPACITY)
	assert(_client_resource_cache_bytes <= CLIENT_RESOURCE_CACHE_BUDGET_BYTES)


func _try_pin_map_profile(cache_key: String, estimated_bytes: int) -> bool:
	if _map_pinned_profile_keys.has(cache_key):
		return true
	if _map_pinned_profile_keys.size() >= CLIENT_RESOURCE_CACHE_CAPACITY:
		return false
	if estimated_bytes <= 0 or _map_pinned_bytes + estimated_bytes > CLIENT_RESOURCE_CACHE_BUDGET_BYTES:
		return false
	_map_pinned_profile_keys[cache_key] = true
	_map_pinned_bytes += estimated_bytes
	return true


func _estimated_client_profile_bytes(resources: Dictionary) -> int:
	# Android imports these atlases as ETC2 RGBA8 (8 bits per pixel). This is a
	# conservative GPU-residency estimate and deliberately excludes mipmaps.
	var total := 0
	for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
		var texture := resources.get(action_name) as Texture2D
		if texture != null:
			var size := texture.get_size()
			total += int(size.x) * int(size.y)
	return total


func _client_resource_cache_key(client_mapping: Dictionary) -> String:
	var frame_values: Array = client_mapping.get("frameSize", [160, 160])
	var foot_values: Array = client_mapping.get("footAnchor", [80, 138])
	var parts := PackedStringArray([
		"%sx%s" % [int(frame_values[0]), int(frame_values[1])],
		"%s,%s" % [int(foot_values[0]), int(foot_values[1])],
		str(client_mapping.get("directionPolicy", "mir2_directional")),
		str(client_mapping.get("healthBarTopByDirection", [])),
	])
	var actions: Dictionary = client_mapping.get("actions", {})
	for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
		var action: Dictionary = actions.get(action_name, {})
		parts.append("%s:%d" % [str(action.get("path", "")), int(action.get("framesPerDirection", 0))])
	return "|".join(parts)


func _touch_client_resource_profile(cache_key: String) -> void:
	_client_resource_profile_lru.erase(cache_key)
	_client_resource_profile_lru.append(cache_key)


func _apply_render_state(texture: Texture2D, region: Rect2) -> void:
	var changed := false
	if sprite.texture != texture:
		sprite.texture = texture
		changed = true
	if sprite.region_rect != region:
		sprite.region_rect = region
		changed = true
	if changed:
		_render_state_update_count += 1


func render_state_update_count() -> int:
	return _render_state_update_count


static func cached_client_profile_count() -> int:
	return _client_resource_profiles.size()


static func cached_client_profile_estimated_bytes() -> int:
	return _client_resource_cache_bytes


static func begin_map_prefetch(monster_ids: Array) -> Dictionary:
	release_map_pins()
	_map_prefetch_generation += 1
	var helper := MonsterVisual.new()
	var seen_ids := {}
	for value: Variant in monster_ids:
		var monster_id := int(value)
		if seen_ids.has(monster_id):
			continue
		seen_ids[monster_id] = true
		var data := GameData.get_monster_by_id(monster_id)
		if data.is_empty():
			continue
		var mapping := helper._client_mapping_for(data)
		if mapping.is_empty():
			continue
		var cache_key := helper._client_resource_cache_key(mapping)
		_map_prefetch_keys.append(cache_key)
		if _client_resource_profiles.has(cache_key):
			_map_prefetch_completed_keys[cache_key] = true
			helper._try_pin_map_profile(cache_key, int(_client_resource_profile_bytes.get(cache_key, 0)))
		else:
			helper._request_client_profile(mapping, monster_id, _map_prefetch_generation)
	helper.free()
	return map_prefetch_status()


static func poll_streaming() -> Dictionary:
	var process_frame := Engine.get_process_frames()
	if process_frame == _last_streaming_poll_frame:
		return map_prefetch_status()
	_last_streaming_poll_frame = process_frame
	var helper := MonsterVisual.new()
	for cache_key: String in _threaded_profile_requests.keys():
		var job: Dictionary = _threaded_profile_requests[cache_key]
		if str(job.get("state", "")) != "loading":
			continue
		var ready := true
		var failed := false
		var paths: Dictionary = job.get("paths", {})
		for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
			var status := ResourceLoader.load_threaded_get_status(str(paths.get(action_name, "")))
			if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				failed = true
				break
			if status != ResourceLoader.THREAD_LOAD_LOADED:
				ready = false
		if failed:
			job["state"] = "failed"
			_threaded_profile_requests[cache_key] = job
			continue
		if not ready:
			continue
		var mapping: Dictionary = job.get("mapping", {})
		var result := helper._client_profile_shell(mapping)
		var expected_sizes: Dictionary = job.get("expected_sizes", {})
		for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
			var texture := ResourceLoader.load_threaded_get(str(paths[action_name])) as Texture2D
			_threaded_texture_get_count += 1
			if texture == null or Vector2i(texture.get_size()) != Vector2i(expected_sizes[action_name]):
				failed = true
				break
			result[action_name] = texture
			result["frame_counts"][action_name] = int(mapping.get("actions", {}).get(action_name, {}).get("framesPerDirection", 1))
		if failed or not MonsterAnimationPolicy.validate(result).is_empty():
			job["state"] = "failed"
			_threaded_profile_requests[cache_key] = job
			continue
		job["state"] = "loaded"
		job["resources"] = result
		_threaded_profile_requests[cache_key] = job
	helper._commit_loaded_profiles()
	helper._pump_threaded_profile_queue()
	helper.free()
	return map_prefetch_status()


func _commit_loaded_profiles() -> void:
	# Current-map profiles commit strictly in caller order, so pin priority is
	# deterministic even when the second threaded job finishes first.
	for cache_key: String in _map_prefetch_keys:
		if _map_prefetch_completed_keys.has(cache_key):
			continue
		var job: Dictionary = _threaded_profile_requests.get(cache_key, {})
		var state := str(job.get("state", ""))
		if state == "failed":
			continue
		if state != "loaded":
			break
		var resources: Dictionary = job.get("resources", {})
		var estimated_bytes := _estimated_client_profile_bytes(resources)
		_try_pin_map_profile(cache_key, estimated_bytes)
		_retain_client_resource_profile(cache_key, resources)
		_map_prefetch_completed_keys[cache_key] = true
		_threaded_profile_requests.erase(cache_key)
	# Requests from a released map or proximity activation are regular async LRU.
	for cache_key: String in _threaded_profile_requests.keys():
		var job: Dictionary = _threaded_profile_requests[cache_key]
		if str(job.get("state", "")) != "loaded":
			continue
		if int(job.get("map_generation", -1)) == _map_prefetch_generation and _map_prefetch_keys.has(cache_key):
			continue
		_retain_client_resource_profile(cache_key, job.get("resources", {}))
		_threaded_profile_requests.erase(cache_key)


static func map_prefetch_status() -> Dictionary:
	var ready := 0
	var failed := 0
	var streamed := 0
	var pending_details := []
	var failed_details := []
	for cache_key: String in _map_prefetch_keys:
		if _map_prefetch_completed_keys.has(cache_key):
			if _client_resource_profiles.has(cache_key):
				ready += 1
			else:
				streamed += 1
			continue
		var job: Dictionary = _threaded_profile_requests.get(cache_key, {})
		if str(job.get("state", "")) == "failed":
			failed += 1
			failed_details.append({
				"monsterId": int(job.get("monster_id", -1)),
				"path": str(job.get("failed_path", "")),
				"state": "failed",
			})
			continue
		var path_states := []
		for path: Variant in job.get("paths", {}).values():
			var threaded_status := ResourceLoader.load_threaded_get_status(str(path)) if str(job.get("state", "")) == "loading" else -1
			if threaded_status != ResourceLoader.THREAD_LOAD_LOADED:
				path_states.append({"path": str(path), "status": threaded_status})
		pending_details.append({
			"monsterId": int(job.get("monster_id", -1)),
			"state": str(job.get("state", "missing")),
			"paths": path_states,
		})
	var completed := ready + streamed
	return {
		"requested": _map_prefetch_keys.size(),
		"ready": ready,
		"streamed": streamed,
		"pinned": _map_pinned_profile_keys.size(),
		"pinned_bytes": _map_pinned_bytes,
		"failed": failed,
		"pending": _map_prefetch_keys.size() - completed - failed,
		"pending_details": pending_details,
		"failed_details": failed_details,
		"complete": completed + failed == _map_prefetch_keys.size(),
	}


static func release_map_pins() -> void:
	_map_prefetch_keys.clear()
	_map_pinned_profile_keys.clear()
	_map_prefetch_completed_keys.clear()
	_map_pinned_bytes = 0
	# Do not start queued work from the map being left. Already-loading profiles
	# cannot be cancelled safely and will fall back into the bounded async LRU.
	for cache_key: String in _threaded_profile_queue.duplicate():
		var job: Dictionary = _threaded_profile_requests.get(cache_key, {})
		if int(job.get("map_generation", -1)) >= 0 and str(job.get("state", "")) == "queued":
			_threaded_profile_queue.erase(cache_key)
			_threaded_profile_requests.erase(cache_key)
	var helper := MonsterVisual.new()
	helper._evict_client_resource_profiles()
	helper.free()


static func threaded_texture_request_count() -> int:
	return _threaded_texture_request_count


static func threaded_texture_get_count() -> int:
	return _threaded_texture_get_count


static func set_synchronous_loading_for_tests(enabled: bool) -> void:
	_synchronous_loading_for_tests = enabled


static func reset_client_resource_cache() -> void:
	_client_resource_profiles.clear()
	_client_resource_profile_lru.clear()
	_client_resource_profile_bytes.clear()
	_client_resource_cache_bytes = 0
	_client_texture_load_request_count = 0
	_threaded_profile_requests.clear()
	_threaded_profile_queue.clear()
	_threaded_texture_request_count = 0
	_threaded_texture_get_count = 0
	_map_prefetch_keys.clear()
	_map_pinned_profile_keys.clear()
	_map_prefetch_completed_keys.clear()
	_map_pinned_bytes = 0
	_map_prefetch_generation = 0
	_last_streaming_poll_frame = -1
	_synchronous_loading_for_tests = true


static func client_texture_load_request_count() -> int:
	return _client_texture_load_request_count


func _load_client_texture(path: String, expected_size: Vector2i) -> Texture2D:
	_client_texture_load_request_count += 1
	if ResourceLoader.exists(path):
		var imported := load(path) as Texture2D
		if imported != null and Vector2i(imported.get_size()) == expected_size:
			return imported
	# Headless test runs can see a freshly generated PNG before Godot has made
	# its import cache. Loading the source image keeps the data-driven manifest
	# testable without sharing .godot between worktrees.
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null


func play_attack(duration := 0.46) -> void:
	if _death_remaining > 0.0:
		return
	_attack_remaining = duration
	_action_duration = duration
	_elapsed = 0.0


func play_hit(duration := 0.22) -> void:
	if _death_remaining > 0.0:
		return
	_hit_remaining = duration
	_action_duration = duration
	_elapsed = 0.0


func play_death(duration := 0.62) -> void:
	_death_remaining = duration
	_hit_remaining = 0.0
	_attack_remaining = 0.0
	_action_duration = duration
	_elapsed = 0.0


func uses_final_art() -> bool:
	return visible and sprite != null and sprite.texture != null


func is_fallback_attacking() -> bool:
	return not uses_final_art() and _attack_remaining > 0.0


func fallback_attack_progress() -> float:
	if not is_fallback_attacking() or _action_duration <= 0.0:
		return 0.0
	return clampf(1.0 - _attack_remaining / _action_duration, 0.0, 1.0)


func fallback_lunge_offset(direction: Vector2) -> Vector2:
	return direction.normalized() * sin(fallback_attack_progress() * PI) * 12.0 if is_fallback_attacking() else Vector2.ZERO


func fallback_attack_scale() -> Vector2:
	if not is_fallback_attacking():return Vector2.ONE
	var pulse:=sin(fallback_attack_progress()*PI)
	return Vector2(1.0+0.18*pulse,1.0-0.12*pulse)


func fallback_attack_angle(direction:Vector2)->float:
	if not is_fallback_attacking():return 0.0
	var side:=signf(direction.x) if absf(direction.x)>0.05 else 1.0
	return side*sin(fallback_attack_progress()*TAU)*0.12
