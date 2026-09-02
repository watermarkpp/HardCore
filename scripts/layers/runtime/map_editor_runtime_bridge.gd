class_name MapEditorRuntimeBridge
extends RefCounted

const NPCServiceIdentityScript := preload("res://scripts/npc_service_identity.gd")
const MonsterRespawnPolicyScript := preload(
	"res://scripts/monster_respawn_policy.gd"
)
const MapUIPresentationProjectionScript := preload(
	"res://scripts/map_editor/map_ui_presentation_projection.gd"
)
const BICH_MAP_ID := 910001
const SAFE_RADIUS_GU := 9.0
const RUNTIME_OUTPUT_CONTRACT_ID := "map.editor.runtime.output_units.v1"
const BOSS_RESPAWN_OVERRIDES := {
	911002: 3600.0,
	911003: 3600.0,
	911103: 1800.0,
}
## FREEZE-P0.2R: formal map implementation states. Only maps with a MapEditor
## runtime build + ready marker are implemented_playable; world/reference data
## alone never grants gameplay readiness.
const IMPLEMENTATION_STATE_IMPLEMENTED_PLAYABLE := &"implemented_playable"
const IMPLEMENTATION_STATE_PLANNED_UNBUILT := &"planned_unbuilt"
const IMPLEMENTATION_STATE_REFERENCE_ONLY := &"reference_only"
const IMPLEMENTATION_STATE_UNSUPPORTED := &"unsupported"
const RELEASE_REGISTRY_PATH := (
	"res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
)
const RELEASE_STATE_IMPLEMENTED_PLAYABLE := &"implemented_playable"
const RELEASE_STATE_IMPLEMENTED_STAGING := &"implemented_staging"
const IMPLEMENTATION_STATE_IMPLEMENTED_STAGING := &"implemented_staging"
## FREEZE-P0.3: build-bound release rejection reasons.
const REASON_RUNTIME_RELEASE_NOT_REGISTERED := &"runtime_release_not_registered"
const REASON_RUNTIME_RELEASE_NOT_READY := &"runtime_release_not_ready"
const REASON_RUNTIME_FILE_MISSING := &"runtime_file_missing"
const REASON_RUNTIME_INVALID := &"runtime_invalid"
const REASON_RUNTIME_BUILD_NOT_APPROVED := &"runtime_build_not_approved"
const REASON_RUNTIME_MAP_KEY_MISMATCH := &"runtime_map_key_mismatch"
const REASON_RUNTIME_RELEASE_REGISTRY_MISSING := (
	&"runtime_release_registry_missing"
)
const REASON_RUNTIME_RELEASE_REGISTRY_INVALID := (
	&"runtime_release_registry_invalid"
)

static var _runtime_cache := {}
static var _registry_cache: Dictionary = {}
static var _registry_loaded := false
static var _registry_load_valid := false
static var _registry_load_reason := &""
static var _registry_load_errors: Array[String] = []
static var _registry_override_path := ""
static var _readiness_result: Dictionary = {}


static func _registry_path() -> String:
	return (
		_registry_override_path
		if not _registry_override_path.is_empty()
		else RELEASE_REGISTRY_PATH
	)


static func _load_release_registry() -> void:
	if _registry_loaded:
		return
	_registry_cache.clear()
	_registry_load_valid = false
	_registry_load_reason = &""
	_registry_load_errors = []
	var path := _registry_path()
	if not FileAccess.file_exists(path):
		## FREEZE-P0.3R: missing registry -> whole formal release fail-closed.
		_registry_load_reason = REASON_RUNTIME_RELEASE_REGISTRY_MISSING
		_registry_loaded = true
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = (
		JSON.parse_string(file.get_as_text())
		if file != null
		else null
	)
	if file != null:
		file.close()
	if not parsed is Dictionary:
		## FREEZE-P0.3R: unparseable registry -> fail-closed.
		_registry_load_reason = REASON_RUNTIME_RELEASE_REGISTRY_INVALID
		_registry_load_errors = ["runtime_json_invalid"]
		_registry_loaded = true
		return
	## FREEZE-P0.3R: production load must run the SAME schema validator used by
	## publish/tests. Invalid schema -> fail-closed, no partial entry load.
	var schema_errors := validate_release_registry(parsed)
	if not schema_errors.is_empty():
		_registry_load_reason = REASON_RUNTIME_RELEASE_REGISTRY_INVALID
		_registry_load_errors = schema_errors
		_registry_loaded = true
		return
	for raw_entry: Variant in parsed.get("maps", []):
		if raw_entry is Dictionary:
			var mid := int(raw_entry.get("runtime_map_id", -1))
			if mid > 0:
				_registry_cache[mid] = raw_entry
	_registry_load_valid = true
	_registry_loaded = true


static func _release_entry(runtime_map_id: int) -> Dictionary:
	_load_release_registry()
	if not _registry_load_valid:
		return {}
	return _registry_cache.get(runtime_map_id, {})


## FREEZE-P0.3: test/dev seam only - point the registry loader at an alternate
## registry file and drop all caches. Production never calls this.
static func test_override_release_registry_path(path: String) -> void:
	_registry_override_path = path
	invalidate_release_registry()


static func reset_release_registry_override() -> void:
	_registry_override_path = ""
	invalidate_release_registry()


static func invalidate_release_registry() -> void:
	_registry_loaded = false
	_registry_cache.clear()
	_registry_load_valid = false
	_registry_load_reason = &""
	_registry_load_errors = []
	_runtime_cache.clear()
	_readiness_result.clear()

static func released_map_ids() -> Array[int]:
	_load_release_registry()
	if not _registry_load_valid:
		return []
	var ids: Array[int] = []
	for raw_id: Variant in _registry_cache.keys():
		ids.append(int(raw_id))
	ids.sort()
	return ids


## FREEZE-P0.3: schema contract for the Release Registry. Used by tests and by
## the publish tool before writing.
static func validate_release_registry(registry: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(registry.get("schema_version", 0)) != 1:
		errors.append("unsupported_schema_version")
	if (
		str(registry.get("registry_contract_id", ""))
		!= "mse.map.runtime.release.v1"
	):
		errors.append("invalid_registry_contract_id")
	var maps: Array = registry.get("maps", [])
	var ids: Dictionary = {}
	var keys: Dictionary = {}
	for raw_entry: Variant in maps:
		if not raw_entry is Dictionary:
			errors.append("invalid_entry")
			continue
		var entry: Dictionary = raw_entry
		var mid := int(entry.get("runtime_map_id", -1))
		var map_key := str(entry.get("map_key", ""))
		var runtime_file_path := str(entry.get("runtime_path", ""))
		var release_state := str(entry.get("release_state", ""))
		var approved := str(entry.get("approved_build_sha256", ""))
		if mid <= 0:
			errors.append("invalid_runtime_map_id")
		if ids.has(mid):
			errors.append("duplicate_runtime_map_id")
		ids[mid] = true
		if map_key.is_empty():
			errors.append("missing_map_key")
		if keys.has(map_key):
			errors.append("duplicate_map_key")
		keys[map_key] = true
		if runtime_file_path.is_empty():
			errors.append("missing_runtime_path")
		if approved.is_empty():
			errors.append("missing_approved_hash")
		var ui_projection: Variant = entry.get("ui_presentation", null)
		if ui_projection != null:
			if not ui_projection is Dictionary:
				errors.append("map_ui_projection_invalid")
			else:
				errors.append_array(
					MapUIPresentationProjectionScript.validate(
						ui_projection as Dictionary,
						approved
					)
				)
		if (
			release_state != str(RELEASE_STATE_IMPLEMENTED_PLAYABLE)
			and release_state != str(RELEASE_STATE_IMPLEMENTED_STAGING)
		):
			errors.append("unknown_release_state")
	return errors


static func _compute_readiness(runtime_map_id: int) -> Dictionary:
	var entry := _release_entry(runtime_map_id)
	if entry.is_empty():
		return {
			"playable": false,
			"reason": REASON_RUNTIME_RELEASE_NOT_REGISTERED,
		}
	if (
		str(entry.get("release_state", ""))
		!= str(RELEASE_STATE_IMPLEMENTED_PLAYABLE)
	):
		return {
			"playable": false,
			"reason": REASON_RUNTIME_RELEASE_NOT_READY,
		}
	var runtime_file_path := str(entry.get("runtime_path", ""))
	if (
		runtime_file_path.is_empty()
		or not FileAccess.file_exists(runtime_file_path)
	):
		return {"playable": false, "reason": REASON_RUNTIME_FILE_MISSING}
	var loaded := MapEditorRuntimeMapService.load_runtime(runtime_file_path)
	if not loaded.ok:
		return {"playable": false, "reason": REASON_RUNTIME_INVALID}
	var runtime: Dictionary = loaded.runtime
	var approved := str(entry.get("approved_build_sha256", ""))
	var current := str(runtime.get("build_sha256", ""))
	if approved != current:
		return {"playable": false, "reason": REASON_RUNTIME_BUILD_NOT_APPROVED}
	var map_key := str(entry.get("map_key", ""))
	var source_map_id := str(runtime.get("source", {}).get("map_id", ""))
	if source_map_id != map_key:
		return {"playable": false, "reason": REASON_RUNTIME_MAP_KEY_MISMATCH}
	return {"playable": true, "reason": &""}


static func _readiness(runtime_map_id: int) -> Dictionary:
	if not _readiness_result.has(runtime_map_id):
		_readiness_result[runtime_map_id] = _compute_readiness(runtime_map_id)
	return _readiness_result[runtime_map_id]


## FREEZE-P0.3: NOT "file exists". This answers "is the current release valid
## and approved" - registry entry + implemented_playable + runtime file +
## load ok + approved build hash match + map key match.
static func has_runtime_map(runtime_map_id: int) -> bool:
	_load_release_registry()
	if not _registry_load_valid:
		return false
	return bool(_readiness(runtime_map_id).get("playable", false))


static func release_rejection_reason(runtime_map_id: int) -> StringName:
	_load_release_registry()
	if not _registry_load_valid:
		return _registry_load_reason
	return str(_readiness(runtime_map_id).get("reason", &"")) as StringName


## FREEZE-P0.3R: global registry load state (valid / reason / errors). Read-only
## diagnostic for tests, evidence and MSE status display.
static func registry_load_state() -> Dictionary:
	_load_release_registry()
	return {
		"valid": _registry_load_valid,
		"reason": str(_registry_load_reason),
		"errors": _registry_load_errors.duplicate(),
	}


## Pure artifact existence: the registry entry exists AND its runtime file
## exists. Does NOT grant readiness.
static func runtime_artifact_exists(runtime_map_id: int) -> bool:
	var entry := _release_entry(runtime_map_id)
	if entry.is_empty():
		return false
	var runtime_file_path := str(entry.get("runtime_path", ""))
	return (
		not runtime_file_path.is_empty()
		and FileAccess.file_exists(runtime_file_path)
	)


static func is_runtime_built(runtime_map_id: int) -> bool:
	return has_runtime_map(runtime_map_id)


static func is_formal_playable(runtime_map_id: int) -> bool:
	return has_runtime_map(runtime_map_id)


static func implementation_state(runtime_map_id: int) -> Dictionary:
	_load_release_registry()
	if not _registry_load_valid:
		## FREEZE-P0.3R: invalid/missing registry -> every formal map
		## fail-closed; no entry may be treated as playable.
		return {
			"state": IMPLEMENTATION_STATE_UNSUPPORTED,
			"runtime_map_id": runtime_map_id,
			"formal_playable": false,
		}
	var entry := _release_entry(runtime_map_id)
	if not entry.is_empty():
		if has_runtime_map(runtime_map_id):
			return {
				"state": IMPLEMENTATION_STATE_IMPLEMENTED_PLAYABLE,
				"runtime_map_id": runtime_map_id,
				"formal_playable": true,
			}
		return {
			"state": IMPLEMENTATION_STATE_IMPLEMENTED_STAGING,
			"runtime_map_id": runtime_map_id,
			"formal_playable": false,
		}
	# The retired WorldContent monster table is not an implementation-state
	# authority.  A known map may still be reported as planned from GameData's
	# map identity catalog, but its legacy actor rows never affect this state.
	if not GameData.get_map_by_id(runtime_map_id).is_empty():
		return {
			"state": IMPLEMENTATION_STATE_PLANNED_UNBUILT,
			"runtime_map_id": runtime_map_id,
			"formal_playable": false,
		}
	return {
		"state": IMPLEMENTATION_STATE_UNSUPPORTED,
		"runtime_map_id": runtime_map_id,
		"formal_playable": false,
	}


static func runtime_path(runtime_map_id: int) -> String:
	var entry := _release_entry(runtime_map_id)
	if entry.is_empty():
		return ""
	return str(entry.get("runtime_path", ""))


static func ground_manifest_path(runtime_map_id: int) -> String:
	var entry := _release_entry(runtime_map_id)
	if entry.is_empty():
		return ""
	return (
		"res://map_editor_workspace/%s/ground/ground_manifest.json"
		% str(entry.get("map_key", ""))
	)


static func visual_path(runtime_map_id: int) -> String:
	var entry := _release_entry(runtime_map_id)
	if entry.is_empty():
		return ""
	return (
		"res://assets/data/runtime/map_editor/%s.visual.json"
		% str(entry.get("map_key", ""))
	)


static func load_map(runtime_map_id: int) -> Dictionary:
	if _runtime_cache.has(runtime_map_id):
		return _runtime_cache[runtime_map_id]
	if not has_runtime_map(runtime_map_id):
		_runtime_cache[runtime_map_id] = {}
		return {}
	var loaded := MapEditorRuntimeMapService.load_runtime(
		runtime_path(runtime_map_id)
	)
	var runtime: Dictionary = loaded.runtime if loaded.ok else {}
	if not runtime.is_empty():
		runtime["runtime_map_id"] = runtime_map_id
	_runtime_cache[runtime_map_id] = runtime
	return runtime


## Lightweight, build-bound map information for UI presentation. This reads
## only the already-loaded release registry and never opens a full runtime map.
static func map_ui_content_for_map(runtime_map_id: int) -> Dictionary:
	var entry := _release_entry(runtime_map_id)
	if entry.is_empty():
		return {}
	var raw_projection: Variant = entry.get("ui_presentation", null)
	if not raw_projection is Dictionary:
		return {}
	var projection: Dictionary = raw_projection
	if not MapUIPresentationProjectionScript.validate(
		projection,
		str(entry.get("approved_build_sha256", ""))
	).is_empty():
		return {}
	return MapUIPresentationProjectionScript.content_from_projection(projection)


static func map_ui_presentation_snapshot_key() -> String:
	_load_release_registry()
	if not _registry_load_valid:
		return "invalid"
	var parts: Array[String] = []
	for runtime_map_id: int in released_map_ids():
		var entry: Dictionary = _registry_cache.get(runtime_map_id, {})
		parts.append("%d:%s" % [
			runtime_map_id,
			str(entry.get("approved_build_sha256", "")),
		])
	return "|".join(parts)


static func debug_runtime_cache_size() -> int:
	return _runtime_cache.size()


static func load_bich() -> Dictionary:
	return load_map(BICH_MAP_ID)


static func ground_position_gu_to_screen_position_px(
	runtime: Dictionary,
	ground_position_gu: Vector2
) -> Vector2:
	var raw_size: Array = runtime.get("design", {}).get(
		"design_size", [256, 256]
	)
	return MapEditorCoordinate.ground_position_gu_to_screen_position_px(
		ground_position_gu,
		Vector2i(int(raw_size[0]), int(raw_size[1]))
	)


static func grid_cell_to_screen_position_px(
	runtime: Dictionary,
	raw_cell: Array
) -> Vector2:
	return ground_position_gu_to_screen_position_px(
		runtime, cell_to_ground_position_gu(raw_cell)
	)


static func screen_position_px_to_ground_position_gu(
	runtime: Dictionary,
	screen_position_px: Vector2
) -> Vector2:
	var raw_size: Array = runtime.get("design", {}).get(
		"design_size", [256, 256]
	)
	return MapEditorCoordinate.screen_position_px_to_ground_position_gu(
		screen_position_px,
		Vector2i(int(raw_size[0]), int(raw_size[1]))
	)


static func cell_to_ground_position_gu(raw_cell: Array) -> Vector2:
	return _array_to_vector2(raw_cell) + Vector2(0.5, 0.5)


static func ground_polygon_gu_to_screen_polygon_px(
	runtime: Dictionary,
	raw_polygon_ground_gu: Array
) -> PackedVector2Array:
	var projected := PackedVector2Array()
	for raw_point: Variant in raw_polygon_ground_gu:
		if raw_point is Array and raw_point.size() == 2:
			projected.append(ground_position_gu_to_screen_position_px(
				runtime, _array_to_vector2(raw_point)
			))
	return projected


static func portal_screen_position_px(
	runtime_map_id: int,
	portal_id: String,
	source_map_id := -1
) -> Vector2:
	var runtime := load_map(runtime_map_id)
	if runtime.is_empty():
		return Vector2.ZERO
	var found := _portal_ground_position_result(
		runtime, portal_id, source_map_id
	)
	if not bool(found.get("ok", false)):
		return Vector2.ZERO
	return ground_position_gu_to_screen_position_px(
		runtime, found.position_ground_gu
	)


static func portal_position_ground_gu(
	runtime_map_id: int,
	portal_id: String,
	source_map_id := -1
) -> Vector2:
	var runtime := load_map(runtime_map_id)
	if runtime.is_empty():
		return Vector2.ZERO
	var found := _portal_ground_position_result(
		runtime, portal_id, source_map_id
	)
	return found.get("position_ground_gu", Vector2.ZERO)


static func _portal_ground_position_result(
	runtime: Dictionary,
	portal_id: String,
	source_map_id: int
) -> Dictionary:
	for endpoint: Dictionary in runtime.get("semantics", {}).get(
		"map_exit_points", []
	):
		if not portal_id.is_empty() and str(
			endpoint.get("semantic_id", "")
		) == portal_id:
			return {
				"ok": true,
				"position_ground_gu": cell_to_ground_position_gu(
					endpoint.get("tile", [0, 0])
				),
			}
		if (
			portal_id.is_empty()
			and source_map_id >= 0
			and int(endpoint.get("target_map_id", -1)) == source_map_id
		):
			return {
				"ok": true,
				"position_ground_gu": cell_to_ground_position_gu(
					endpoint.get("tile", [0, 0])
				),
			}
	return {"ok": false}


static func home_screen_position_px() -> Vector2:
	var runtime := load_bich()
	if runtime.is_empty():
		return Vector2.ZERO
	return ground_position_gu_to_screen_position_px(
		runtime, home_position_ground_gu()
	)


static func home_position_ground_gu() -> Vector2:
	var runtime := load_bich()
	var safe_areas: Array = runtime.get("semantics", {}).get("safe_area", [])
	for safe: Dictionary in safe_areas:
		if bool(safe.get("return_anchor", false)):
			return cell_to_ground_position_gu(
				safe.get("return_tile", safe.get("tile", [128, 128]))
			)
	# Final editor maps can publish one authoritative safe area without the
	# legacy return/death/logout flags. Keep service-home spawning inside the
	# playable runtime by using that safe area's anchor tile.
	if not safe_areas.is_empty():
		var safe: Dictionary = safe_areas[0]
		return cell_to_ground_position_gu(
			safe.get("return_tile", safe.get("tile", [128, 128]))
		)
	return Vector2.ZERO


static func game_content() -> Dictionary:
	return game_content_for_map(BICH_MAP_ID)


static func game_content_for_map(runtime_map_id: int) -> Dictionary:
	var runtime := load_map(runtime_map_id)
	if runtime.is_empty():
		return {}
	var raw_size: Array = runtime.get("design", {}).get(
		"design_size", [256, 256]
	)
	var map_center_ground_gu := Vector2(
		(float(raw_size[0]) - 1.0) * 0.5,
		(float(raw_size[1]) - 1.0) * 0.5
	)
	var map_center_screen_position_px := ground_position_gu_to_screen_position_px(
		runtime, map_center_ground_gu
	)
	var release_entry := _release_entry(runtime_map_id)
	var result := {
		"name": str(release_entry.get("display_name", "地图")),
		"runtime_map_id": runtime_map_id,
		"runtime_map_key": str(release_entry.get("map_key", "")),
		"runtime_output_contract_id": RUNTIME_OUTPUT_CONTRACT_ID,
		"runtime_home_screen_position_px": home_screen_position_px() if runtime_map_id == BICH_MAP_ID else Vector2.ZERO,
		"runtime_home_position_ground_gu": home_position_ground_gu() if runtime_map_id == BICH_MAP_ID else Vector2.ZERO,
		"map_center_screen_position_px": map_center_screen_position_px,
		"map_center_ground_gu": map_center_ground_gu,
		"spawns": [],
		"bosses": [],
		"npcs": [],
		"portals": [],
		"safe_areas": [],
		"editor_runtime": true,
	}
	var semantics: Dictionary = runtime.get("semantics", {})
	for entry: Dictionary in semantics.get("monster_spawn", []):
		var spawn := _combat_spawn(runtime, entry, "monster_spawn")
		if not spawn.is_empty():
			result.spawns.append(spawn)
	for entry: Dictionary in semantics.get("boss_spawn", []):
		var spawn := _combat_spawn(
			runtime,
			entry,
			"boss_spawn",
			float(BOSS_RESPAWN_OVERRIDES.get(runtime_map_id, -1.0))
		)
		if not spawn.is_empty():
			result.bosses.append(spawn)
	for entry: Dictionary in semantics.get("npc_points", []):
		var npc_id := str(entry.get("npc_id", ""))
		var stock_key := str({
			"npc.4.001": "general",
			"npc.4.002": "starter_gear",
			"npc.4.003": "books",
			"npc.expansion.bich_pharmacist": "medicine",
		}.get(npc_id, ""))
		var service_role := str(entry.get("service_role", "dialogue"))
		var service_identity := NPCServiceIdentityScript.resolve(
			str(entry.get("display_name", "NPC")), service_role, stock_key
		)
		result.npcs.append({
			"name": service_identity.get("display_name", "NPC"),
			"screen_position_px": grid_cell_to_screen_position_px(
				runtime, entry.get("tile", [0, 0])
			),
			"position_ground_gu": cell_to_ground_position_gu(
				entry.get("tile", [0, 0])
			),
			"kind": service_role,
			"npc_id": npc_id,
			"service_identity_id": service_identity.get("id", ""),
			"stock": stock_key,
			"appearance": int(entry.get("appearance", -1)),
		})
	for entry: Dictionary in semantics.get("door_points", []):
		if not bool(entry.get("target_configured", true)):
			continue
		if int(entry.get("target_map_id", -1)) < 0:
			continue
		result.portals.append(_portal_record(runtime_map_id, runtime, entry))
	for entry: Dictionary in semantics.get("map_exit_points", []):
		if not bool(entry.get("target_configured", true)):
			continue
		if int(entry.get("target_map_id", -1)) < 0:
			continue
		result.portals.append(_portal_record(runtime_map_id, runtime, entry))
	if runtime_map_id == BICH_MAP_ID:
		var home_ground_gu := home_position_ground_gu()
		result.safe_areas.append({
			"center_ground_gu": home_ground_gu,
			"radius_gu": SAFE_RADIUS_GU,
			"shape": "circle",
			"polygon_ground_gu": PackedVector2Array(),
			"blocks_monster_damage": true,
			"blocks_monster_entry": true,
			"policy_override": "single_player_respawn_circle_9_gu",
		})
	else:
		for safe: Dictionary in semantics.get("safe_area", []):
			var converted := safe.duplicate(true)
			var center_ground_gu := cell_to_ground_position_gu(
				safe.get("tile", [0, 0])
			)
			converted["center_ground_gu"] = center_ground_gu
			converted["radius_gu"] = float(safe.get("radius_gu", 0.0))
			converted["polygon_ground_gu"] = safe.get(
				"polygon_ground_gu", []
			).duplicate(true)
			result.safe_areas.append(converted)
	return result


static func _combat_spawn(
	runtime: Dictionary,
	entry: Dictionary,
	placement_kind: String,
	respawn_override := -1.0
) -> Dictionary:
	var numeric_id := _strict_spawn_monster_id(entry)
	if numeric_id <= 0:
		return {}
	# The editor bridge is a production spawn boundary.  Both catalog/editor
	# eligibility and GameData's resolved-drop runtime closure must succeed.
	var canonical := GameData.get_canonical_monster_entry(
		numeric_id, "runtime"
	)
	if canonical.is_empty() or GameData.get_canonical_monster_entry(
		numeric_id, "editor"
	).is_empty():
		return {}
	var classification := str(canonical.get("classification", ""))
	var spawn_classification := str(
		canonical.get("spawn_classification", "")
	)
	var canonical_placement := str(
		canonical.get("editor_placement", {}).get("placement_kind", "")
	)
	if placement_kind not in ["monster_spawn", "boss_spawn"]:
		return {}
	if not canonical_placement.is_empty() and canonical_placement != placement_kind:
		return {}
	if spawn_classification == MonsterRespawnPolicyScript.SPECIAL_NORMAL:
		if placement_kind != "monster_spawn":
			return {}
		if int(entry.get("count", 1)) != 1 or int(entry.get("max_alive", 1)) != 1:
			return {}
	else:
		if placement_kind == "boss_spawn" and classification not in ["elite", "boss"]:
			return {}
		if placement_kind == "monster_spawn" and classification in ["elite", "boss"]:
			return {}
	var respawn_seconds := float(entry.get("respawn_seconds", 60.0))
	var respawn_policy_id := str(entry.get("respawn_policy_id", ""))
	if spawn_classification == MonsterRespawnPolicyScript.SPECIAL_NORMAL:
		# Canonical Authority upgrades legacy/dirty authoring values without
		# mutating the user's map workspace. Published runtime always receives
		# the frozen special_normal tier.
		respawn_policy_id = MonsterRespawnPolicyScript.SPECIAL_NORMAL
		respawn_seconds = MonsterRespawnPolicyScript.SPECIAL_NORMAL_SECONDS
	if respawn_override > 0.0:
		respawn_seconds = respawn_override
	return {
		"name": str(canonical.get("canonical_name", "")),
		"monster_id": numeric_id,
		"classification": classification,
		"spawn_classification": spawn_classification,
		"placement_kind": placement_kind,
		"is_boss": classification == "boss",
		"screen_position_px": grid_cell_to_screen_position_px(
			runtime, entry.get("tile", [0, 0])
		),
		"position_ground_gu": cell_to_ground_position_gu(
			entry.get("tile", [0, 0])
		),
		"respawn_seconds": respawn_seconds,
		"respawn_policy_id": respawn_policy_id,
		"count": int(entry.get("count", 1)),
		"max_alive": int(entry.get("max_alive", 1)),
		"radius_gu": float(entry.get("radius_gu", 0.0)),
		"spawn_group": entry.duplicate(true),
	}


static func _strict_spawn_monster_id(entry: Dictionary) -> int:
	# Published runtime semantics use one stable integer field.  Legacy editor
	# transport IDs and prefixed strings are deliberately not compatibility
	# inputs for the new APK monster runtime.
	var retired_camel_key := "monster" + "Id"
	if (
		not entry.has("monster_id")
		or entry.has(retired_camel_key)
		or entry.has("boss_id")
		or entry.has("content_id")
	):
		return -1
	var value: Variant = entry.get("monster_id")
	if value is int:
		return int(value) if int(value) > 0 else -1
	# Godot's JSON parser represents JSON numbers as floats, including integer
	# tokens written by the map compiler.  Accept only an exactly integral,
	# finite, positive value; strings and every lossy numeric token stay closed.
	if value is float:
		var numeric_value := float(value)
		if (
			is_finite(numeric_value)
			and numeric_value > 0.0
			and numeric_value == floorf(numeric_value)
			and numeric_value <= 9007199254740991.0
		):
			return int(numeric_value)
	return -1


static func _portal_record(
	source_map_id: int,
	runtime: Dictionary,
	entry: Dictionary
) -> Dictionary:
	return {
		"screen_position_px": grid_cell_to_screen_position_px(
			runtime, entry.get("tile", [0, 0])
		),
		"position_ground_gu": cell_to_ground_position_gu(
			entry.get("tile", [0, 0])
		),
		"source_map_id": source_map_id,
		"source_portal_id": str(entry.get("semantic_id", "")),
		"target_map_id": int(entry.get("target_map_id", -1)),
		"target_map_key": str(entry.get("target_map_key", "")),
		"target_portal_id": str(entry.get("target_portal_id", "")),
		"target_entrance_id": str(entry.get("target_entrance_id", "")),
		"target_tile": entry.get("target_tile", []).duplicate(),
		"label": entry.get("display_name", "地图入口"),
		"portal_contract_id": str(entry.get("portal_contract_id", "")),
		"arrival_reentry_policy_id": str(entry.get("arrival_reentry_policy_id", "")),
		"return_minimum_seconds": float(entry.get("return_minimum_seconds", 0.0)),
		"return_unlock_distance_gu": float(entry.get(
			"return_unlock_distance_gu", 0.0
		)),
		"travel_request_single_flight": bool(entry.get("travel_request_single_flight", false)),
	}


static func _array_to_vector2(raw: Array) -> Vector2:
	if raw.size() != 2:
		return Vector2.ZERO
	return Vector2(float(raw[0]), float(raw[1]))
