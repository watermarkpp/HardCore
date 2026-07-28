class_name HelmetVisualV2
extends RefCounted

const CONTRACT_ID := "equipment.world_helmet.player_visual_v2"
const HEAD_SOCKET_CONTRACT_ID := "player.visual.head_socket.v1"
const CONTRACT_PATH := "res://assets/data/equipment_helmet_visual_v2.json"
const HEAD_SOCKET_PATH := "res://assets/data/player_head_socket_db.json"
const OVERRIDE_PATH := "res://assets/data/equipment_helmet_visual_v2_overrides.json"
const CANONICAL_DIRECTIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const WORLD_SCALE_MIN_PERCENT := 5
const WORLD_SCALE_MAX_PERCENT := 200
const WORLD_SCALE_STEP_PERCENT := 5

static var _contract: Dictionary = {}
static var _head_sockets: Dictionary = {}
static var _overrides: Dictionary = {}
static var _session_overrides: Dictionary = {}
static var _session_asset_overrides: Dictionary = {}
static var _override_path := OVERRIDE_PATH


static func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func contract() -> Dictionary:
	if _contract.is_empty():
		_contract = _json(CONTRACT_PATH)
	return _contract


static func head_socket_database() -> Dictionary:
	if _head_sockets.is_empty():
		_head_sockets = _json(HEAD_SOCKET_PATH)
	return _head_sockets


static func calibration_overrides() -> Dictionary:
	if _overrides.is_empty():
		_overrides = _json(_override_path)
	return _overrides


static func reload_data() -> void:
	_contract = {}
	_head_sockets = {}
	_overrides = {}
	_session_overrides = {}
	_session_asset_overrides = {}


static func calibration_override_path() -> String:
	return _override_path


static func set_calibration_override_path_for_test(path: String) -> bool:
	if not (
		path.begins_with("res://outputs/")
		or path.begins_with("user://")
	):
		return false
	_override_path = path
	_overrides = {}
	_session_overrides = {}
	_session_asset_overrides = {}
	return true


static func reset_calibration_override_path() -> void:
	_override_path = OVERRIDE_PATH
	_overrides = {}
	_session_overrides = {}
	_session_asset_overrides = {}


static func visual_asset_for_item(item_id: int) -> Dictionary:
	var data := contract()
	var asset_id := str(data.get("itemVisualAssetRefs", {}).get(str(item_id), ""))
	var asset: Variant = data.get("visualAssets", {}).get(asset_id, {})
	return asset if asset is Dictionary else {}


static func visual_asset_id_for_item(item_id: int) -> String:
	return str(contract().get("itemVisualAssetRefs", {}).get(str(item_id), ""))


static func calibration_items() -> Array:
	var items: Variant = contract().get("calibrationItems", [])
	return items if items is Array else []


static func calibration_item_id_for_item(item_id: int) -> int:
	var asset := visual_asset_for_item(item_id)
	return int(asset.get("calibrationItemId", item_id))


static func visual_asset_override_for_item(item_id: int) -> Dictionary:
	var asset_id := visual_asset_id_for_item(item_id)
	var merged: Dictionary = calibration_overrides().get(
		"visualAssetOverrides", {}
	).get(asset_id, {}).duplicate(true)
	var session: Variant = _session_asset_overrides.get(asset_id, {})
	if session is Dictionary:
		merged.merge(session, true)
	return merged


static func canonical_direction(direction_row: int) -> String:
	return CANONICAL_DIRECTIONS[posmod(direction_row, CANONICAL_DIRECTIONS.size())]


static func direction_record(item_id: int, direction_row: int) -> Dictionary:
	var asset := visual_asset_for_item(item_id)
	var record: Variant = asset.get("directions", {}).get(canonical_direction(direction_row), {})
	if not record is Dictionary:
		return {}
	var merged: Dictionary = record.duplicate(true)
	var calibration_item_id := calibration_item_id_for_item(item_id)
	var override: Variant = calibration_overrides().get("itemOverrides", {}).get(
		str(calibration_item_id), {}
	).get("directions", {}).get(canonical_direction(direction_row), {})
	if override is Dictionary:
		merged.merge(override, true)
	var session: Variant = _session_overrides.get(str(calibration_item_id), {}).get(
		canonical_direction(direction_row), {}
	)
	if session is Dictionary:
		merged.merge(session, true)
	return merged


static func source_direction_row(item_id: int, direction_row: int) -> int:
	var record := direction_record(item_id, direction_row)
	if record.is_empty():
		return posmod(direction_row, CANONICAL_DIRECTIONS.size())
	return int(record.get("source_row", direction_row))


static func source_direction_for_row(item_id: int, source_row: int) -> String:
	if source_row < 0 or source_row >= CANONICAL_DIRECTIONS.size():
		return ""
	var source_map: Variant = visual_asset_for_item(item_id).get(
		"source_direction_map", {}
	)
	if source_map is Dictionary:
		for direction: String in CANONICAL_DIRECTIONS:
			if int(source_map.get(direction, -1)) == source_row:
				return direction
	return ""


static func source_slot_id_for_row(item_id: int, source_row: int) -> String:
	if source_row < 0 or source_row >= CANONICAL_DIRECTIONS.size():
		return ""
	var slots: Variant = visual_asset_for_item(item_id).get("sourceSlots", {})
	if slots is Dictionary:
		for slot_id: String in slots:
			if int(slots[slot_id]) == source_row:
				return slot_id
	return "slot_%d" % source_row


static func source_pivot_direction_index(item_id: int, source_row: int) -> int:
	var base_directions: Variant = visual_asset_for_item(item_id).get(
		"directions", {}
	)
	if base_directions is Dictionary:
		for direction_index: int in CANONICAL_DIRECTIONS.size():
			var record: Variant = base_directions.get(
				canonical_direction(direction_index), {}
			)
			if record is Dictionary and int(
				record.get("source_row", -1)
			) == source_row:
				return direction_index
	return -1


static func is_read_only(item_id: int) -> bool:
	return bool(visual_asset_for_item(item_id).get(
		"readOnlyGoldenReference", false
	))


static func saved_direction_override(
	item_id: int,
	direction_row: int
) -> Dictionary:
	var calibration_item_id := calibration_item_id_for_item(item_id)
	var saved: Variant = calibration_overrides().get(
		"itemOverrides", {}
	).get(str(calibration_item_id), {}).get("directions", {}).get(
		canonical_direction(direction_row), {}
	)
	return saved if saved is Dictionary else {}


static func idle_baseline_complete(item_id: int) -> bool:
	if is_read_only(item_id):
		return false
	for direction_row: int in CANONICAL_DIRECTIONS.size():
		var saved := saved_direction_override(item_id, direction_row)
		if (
			not saved.has("source_row")
			or not saved.has("source_slot_id")
			or not saved.has("nudge")
		):
			return false
	var asset_override := visual_asset_override_for_item(item_id)
	return (
		asset_override.has("uniform_scale_percent")
		and asset_override.has("derivedAtlases")
	)


static func body_head_socket(
	player_visual_id: String,
	action: String,
	direction_row: int,
	frame_index: int
) -> Vector2i:
	var visual: Variant = head_socket_database().get("playerVisuals", {}).get(player_visual_id, {})
	if not visual is Dictionary:
		return Vector2i.ZERO
	var frames: Variant = visual.get("actions", {}).get(action, {}).get(
		"directions", {}
	).get(canonical_direction(direction_row), [])
	if not frames is Array or frames.is_empty():
		return Vector2i.ZERO
	var frame: Variant = frames[clampi(frame_index, 0, frames.size() - 1)]
	if not frame is Dictionary:
		return Vector2i.ZERO
	return _integer_vector(frame.get("head_socket", []))


static func final_position_delta(
	item_id: int,
	player_visual_id: String,
	action: String,
	direction_row: int,
	frame_index: int
) -> Vector2:
	var record := direction_record(item_id, direction_row)
	if record.is_empty():
		return Vector2.ZERO
	var socket := body_head_socket(player_visual_id, action, direction_row, frame_index)
	if socket == Vector2i.ZERO:
		return Vector2.ZERO
	var pivot := pivot_for_frame(item_id, action, direction_row, frame_index)
	var nudge := _numeric_vector(record.get("nudge", []))
	return Vector2(socket - pivot) + nudge


static func pivot_for_frame(
	item_id: int,
	action: String,
	direction_row: int,
	frame_index: int
) -> Vector2i:
	var record := direction_record(item_id, direction_row)
	var source_row := int(record.get("source_row", direction_row))
	return pivot_for_source_row(item_id, action, source_row, frame_index)


static func pivot_for_source_row(
	item_id: int,
	action: String,
	source_row: int,
	frame_index: int
) -> Vector2i:
	var pivot_direction := source_pivot_direction_index(item_id, source_row)
	var pivot_record: Dictionary = {}
	if pivot_direction >= 0:
		var base_record: Variant = visual_asset_for_item(item_id).get(
			"directions", {}
		).get(canonical_direction(pivot_direction), {})
		if base_record is Dictionary:
			pivot_record = base_record
	var frames: Variant = pivot_record.get(
		"pivotByActionFrame", {}
	).get(action, [])
	if frames is Array and not frames.is_empty():
		return _integer_vector(frames[clampi(frame_index, 0, frames.size() - 1)])
	return _integer_vector(pivot_record.get("pivot", []))


static func action_texture_path(
	item_id: int,
	action: String,
	direction_row: int,
	layer_name: String
) -> String:
	if layer_name == "helmet_front":
		var derived: Variant = visual_asset_override_for_item(item_id).get(
			"derivedAtlases", {}
		)
		if derived is Dictionary:
			var derived_path := str(derived.get(action, ""))
			if (
				not derived_path.is_empty()
				and FileAccess.file_exists(derived_path)
			):
				return derived_path
	return base_action_texture_path(item_id, action, direction_row, layer_name)


static func base_action_texture_path(
	item_id: int,
	action: String,
	direction_row: int,
	layer_name: String
) -> String:
	var record := direction_record(item_id, direction_row)
	if record.is_empty():
		return ""
	var layers: Variant = record.get("layers", {})
	if not layers is Dictionary:
		return ""
	var layer: Variant = layers.get(layer_name, null)
	if layer is Dictionary:
		return str(layer.get(action, ""))
	return str(layer) if layer != null else ""


static func uniform_scale_percent(item_id: int) -> int:
	return clampi(int(visual_asset_override_for_item(item_id).get(
		"uniform_scale_percent", 100
	)), WORLD_SCALE_MIN_PERCENT, WORLD_SCALE_MAX_PERCENT)


static func direction_scale_percent(item_id: int, direction_row: int) -> int:
	var record := direction_record(item_id, direction_row)
	if record.has("scale_percent"):
		return clampi(
			int(record.get("scale_percent", 100)),
			WORLD_SCALE_MIN_PERCENT,
			WORLD_SCALE_MAX_PERCENT
		)
	var directional: Variant = visual_asset_override_for_item(item_id).get(
		"directionScalePercent", {}
	)
	if directional is Dictionary:
		var direction := canonical_direction(direction_row)
		if directional.has(direction):
			return clampi(
				int(directional.get(direction, 100)),
				WORLD_SCALE_MIN_PERCENT,
				WORLD_SCALE_MAX_PERCENT
			)
	return uniform_scale_percent(item_id)


static func direction_scale_profile(item_id: int) -> Dictionary:
	var profile: Dictionary = {}
	for direction_row: int in CANONICAL_DIRECTIONS.size():
		profile[canonical_direction(direction_row)] = direction_scale_percent(
			item_id, direction_row
		)
	return profile


static func set_session_uniform_scale_percent(
	item_id: int,
	percent: int
) -> bool:
	if (
		is_read_only(item_id)
		or percent < WORLD_SCALE_MIN_PERCENT
		or percent > WORLD_SCALE_MAX_PERCENT
	):
		return false
	var asset_id := visual_asset_id_for_item(item_id)
	if asset_id.is_empty():
		return false
	var current: Dictionary = _session_asset_overrides.get(asset_id, {})
	current["uniform_scale_percent"] = percent
	_session_asset_overrides[asset_id] = current
	return true


static func clear_session_uniform_scale(item_id: int) -> void:
	_session_asset_overrides.erase(visual_asset_id_for_item(item_id))


static func persist_uniform_scale_bake(
	item_id: int,
	percent: int,
	derived_atlases: Dictionary,
	source_sha256: Dictionary,
	derived_sha256: Dictionary,
	source_recipe_id: String = "primary_source_rows.v1"
) -> bool:
	if (
		is_read_only(item_id)
		or percent < WORLD_SCALE_MIN_PERCENT
		or percent > WORLD_SCALE_MAX_PERCENT
		or derived_atlases.is_empty()
	):
		return false
	for required_action: String in [
		"idle", "walk", "attack", "cast", "hit", "death",
	]:
		if (
			not derived_atlases.has(required_action)
			or not source_sha256.has(required_action)
			or not derived_sha256.has(required_action)
		):
			return false
	for action: String in derived_atlases:
		var path := str(derived_atlases[action])
		if path.is_empty() or not FileAccess.file_exists(path):
			return false
	var data := calibration_overrides().duplicate(true)
	var asset_id := visual_asset_id_for_item(item_id)
	var assets: Dictionary = data.get("visualAssetOverrides", {})
	var asset_override: Dictionary = assets.get(asset_id, {}).duplicate(true)
	asset_override.merge({
		"uniform_scale_percent": percent,
		"directionScalePercent": {
			"N": percent, "NE": percent, "E": percent, "SE": percent,
			"S": percent, "SW": percent, "W": percent, "NW": percent,
		},
		"derivedAtlases": derived_atlases,
		"sourceAtlasSha256": source_sha256,
		"derivedAtlasSha256": derived_sha256,
		"bakePolicy": {
			"filter": "nearest",
			"pivotInvariant": true,
			"allActionsDirectionsFrames": true,
			"requiredActions": [
				"idle", "walk", "attack", "cast", "hit", "death",
			],
			"pivotSource": (
				"res://assets/data/equipment_male_world_helmet.json"
				+ "#visualIdentities.*.actions.*.frames[].hairAnchorCentroid"
			),
			"castPivotUsesSameFramePrimaryHairEvidence": true,
			"runtimeScale": [1, 1],
			"sourceAtlasModified": false,
			"sourceRecipeId": source_recipe_id,
		},
	}, true)
	assets[asset_id] = asset_override
	data["visualAssetOverrides"] = assets
	var file := FileAccess.open(_override_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t", false) + "\n")
	file.close()
	_overrides = data
	_session_asset_overrides.erase(asset_id)
	return true


static func persist_directional_scale_bake(
	item_id: int,
	direction_scale_percent: Dictionary,
	derived_atlases: Dictionary,
	source_sha256: Dictionary,
	derived_sha256: Dictionary,
	source_recipe_id: String = "primary_source_rows.v1"
) -> bool:
	if is_read_only(item_id) or direction_scale_percent.size() != 8:
		return false
	var normalized: Dictionary = {}
	for direction: String in CANONICAL_DIRECTIONS:
		if not direction_scale_percent.has(direction):
			return false
		var percent := int(direction_scale_percent[direction])
		if (
			percent < WORLD_SCALE_MIN_PERCENT
			or percent > WORLD_SCALE_MAX_PERCENT
			or percent % WORLD_SCALE_STEP_PERCENT != 0
		):
			return false
		normalized[direction] = percent
	var uniform_percent := int(normalized[CANONICAL_DIRECTIONS[0]])
	for direction: String in CANONICAL_DIRECTIONS:
		if int(normalized[direction]) != uniform_percent:
			uniform_percent = 100
			break
	for required_action: String in [
		"idle", "walk", "attack", "cast", "hit", "death",
	]:
		if (
			not derived_atlases.has(required_action)
			or not source_sha256.has(required_action)
			or not derived_sha256.has(required_action)
		):
			return false
	for action: String in derived_atlases:
		var path := str(derived_atlases[action])
		if path.is_empty() or not FileAccess.file_exists(path):
			return false
	var data := calibration_overrides().duplicate(true)
	var asset_id := visual_asset_id_for_item(item_id)
	var assets: Dictionary = data.get("visualAssetOverrides", {})
	var asset_override: Dictionary = assets.get(asset_id, {}).duplicate(true)
	asset_override.merge({
		"uniform_scale_percent": uniform_percent,
		"directionScalePercent": normalized,
		"derivedAtlases": derived_atlases,
		"sourceAtlasSha256": source_sha256,
		"derivedAtlasSha256": derived_sha256,
		"bakePolicy": {
			"filter": "lanczos_from_authored_source_then_nearest_runtime",
			"pivotInvariant": true,
			"directionIndependent": true,
			"scaleStepPercent": 5,
			"allActionsDirectionsFrames": true,
			"requiredActions": [
				"idle", "walk", "attack", "cast", "hit", "death",
			],
			"runtimeScale": [1, 1],
			"sourceAtlasModified": false,
			"sourceRecipeId": source_recipe_id,
		},
	}, true)
	assets[asset_id] = asset_override
	data["visualAssetOverrides"] = assets
	if not _write_overrides(data):
		return false
	_overrides = data
	_session_asset_overrides.erase(asset_id)
	return true


static func presentation_calibration(item_id: int) -> Dictionary:
	var value: Variant = visual_asset_override_for_item(item_id).get(
		"presentationCalibration", {}
	)
	return value.duplicate(true) if value is Dictionary else {}


static func set_session_presentation_calibration(
	item_id: int,
	value: Dictionary
) -> bool:
	if is_read_only(item_id):
		return false
	var normalized := _validated_presentation_calibration(value, true)
	if normalized.is_empty():
		return false
	var asset_id := visual_asset_id_for_item(item_id)
	if asset_id.is_empty():
		return false
	var current: Dictionary = _session_asset_overrides.get(
		asset_id, {}
	).duplicate(true)
	current["presentationCalibration"] = normalized
	_session_asset_overrides[asset_id] = current
	return true


static func persist_presentation_calibration(
	item_id: int,
	value: Dictionary
) -> bool:
	if is_read_only(item_id):
		return false
	var normalized := _validated_presentation_calibration(
		value,
		_override_path != OVERRIDE_PATH
	)
	if normalized.is_empty():
		return false
	var data := calibration_overrides().duplicate(true)
	var asset_id := visual_asset_id_for_item(item_id)
	var assets: Dictionary = data.get("visualAssetOverrides", {})
	var asset_override: Dictionary = assets.get(asset_id, {}).duplicate(true)
	asset_override["presentationCalibration"] = normalized
	assets[asset_id] = asset_override
	data["visualAssetOverrides"] = assets
	if not _write_overrides(data):
		return false
	_overrides = data
	var session: Dictionary = _session_asset_overrides.get(
		asset_id, {}
	).duplicate(true)
	session.erase("presentationCalibration")
	if session.is_empty():
		_session_asset_overrides.erase(asset_id)
	else:
		_session_asset_overrides[asset_id] = session
	return true


static func is_locked(item_id: int, direction_row: int) -> bool:
	return bool(direction_record(item_id, direction_row).get("locked", false))


static func persist_calibration_override(
	item_id: int,
	direction_row: int,
	override_fields: Dictionary
) -> bool:
	var asset := visual_asset_for_item(item_id)
	if asset.is_empty() or is_read_only(item_id):
		return false
	var allowed := _validated_override_fields(
		item_id,
		override_fields,
		_override_path != OVERRIDE_PATH
	)
	if allowed.is_empty():
		return false
	var data := calibration_overrides().duplicate(true)
	if data.is_empty():
		data = {
			"schemaVersion": 1,
			"contractId": "equipment.world_helmet.player_visual_v2.overrides.v1",
			"runtimeReadable": true,
			"itemOverrides": {},
		}
	var calibration_item_id := calibration_item_id_for_item(item_id)
	var items: Dictionary = data.get("itemOverrides", {})
	var item: Dictionary = items.get(str(calibration_item_id), {})
	var directions: Dictionary = item.get("directions", {})
	var saved: Dictionary = directions.get(canonical_direction(direction_row), {})
	saved.merge(allowed, true)
	directions[canonical_direction(direction_row)] = saved
	item["directions"] = directions
	items[str(calibration_item_id)] = item
	data["itemOverrides"] = items
	var file := FileAccess.open(_override_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t", false) + "\n")
	file.close()
	_overrides = data
	return true


static func set_session_calibration_override(
	item_id: int,
	direction_row: int,
	override_fields: Dictionary
) -> bool:
	var asset := visual_asset_for_item(item_id)
	if asset.is_empty() or is_read_only(item_id):
		return false
	var allowed := _validated_override_fields(item_id, override_fields, true)
	if allowed.is_empty():
		return false
	var calibration_item_id := calibration_item_id_for_item(item_id)
	var item: Dictionary = _session_overrides.get(str(calibration_item_id), {})
	var direction := canonical_direction(direction_row)
	var current: Dictionary = item.get(direction, {})
	current.merge(allowed, true)
	item[direction] = current
	_session_overrides[str(calibration_item_id)] = item
	return true


static func clear_session_calibration_override(
	item_id: int,
	direction_row: int
) -> void:
	var calibration_item_id := calibration_item_id_for_item(item_id)
	var item: Dictionary = _session_overrides.get(str(calibration_item_id), {})
	item.erase(canonical_direction(direction_row))
	if item.is_empty():
		_session_overrides.erase(str(calibration_item_id))
	else:
		_session_overrides[str(calibration_item_id)] = item


static func _validated_override_fields(
	item_id: int,
	override_fields: Dictionary,
	allow_half_pixel_nudge: bool = false
) -> Dictionary:
	var allowed: Dictionary = {}
	for field: String in [
		"source_row", "source_slot_id", "source_direction",
		"nudge", "status", "locked", "scale_percent"
	]:
		if override_fields.has(field):
			allowed[field] = override_fields[field]
	if allowed.is_empty():
		return {}
	if allowed.has("source_row"):
		var raw_row: Variant = allowed["source_row"]
		if not (raw_row is int or raw_row is float):
			return {}
		var source_row := int(raw_row)
		if float(raw_row) != float(source_row) or source_row < 0 or source_row > 7:
			return {}
		allowed["source_row"] = source_row
	if allowed.has("source_direction"):
		var source_direction := str(allowed["source_direction"])
		if source_direction not in CANONICAL_DIRECTIONS:
			return {}
		allowed["source_direction"] = source_direction
	if allowed.has("source_slot_id"):
		var source_slot_id := str(allowed["source_slot_id"])
		if not source_slot_id.begins_with("slot_"):
			return {}
		allowed["source_slot_id"] = source_slot_id
	if allowed.has("source_row") and allowed.has("source_slot_id"):
		if source_slot_id_for_row(item_id, int(allowed["source_row"])) != str(
			allowed["source_slot_id"]
		):
			return {}
	if allowed.has("nudge"):
		var nudge: Variant = allowed["nudge"]
		if not nudge is Array or nudge.size() != 2:
			return {}
		for coordinate: Variant in nudge:
			if not (coordinate is int or coordinate is float):
				return {}
			var scaled_coordinate := float(coordinate) * (
				2.0 if allow_half_pixel_nudge else 1.0
			)
			if not is_finite(float(coordinate)) or not is_equal_approx(
				scaled_coordinate, roundf(scaled_coordinate)
			):
				return {}
		allowed["nudge"] = (
			[
				snappedf(float(nudge[0]), 0.5),
				snappedf(float(nudge[1]), 0.5),
			]
			if allow_half_pixel_nudge
			else [int(nudge[0]), int(nudge[1])]
		)
	if allowed.has("status"):
		var valid_statuses: Variant = contract().get(
			"policies", {}
		).get("statusValues", [])
		if str(allowed["status"]) not in valid_statuses:
			return {}
		allowed["status"] = str(allowed["status"])
	if allowed.has("locked"):
		if not allowed["locked"] is bool:
			return {}
	if allowed.has("scale_percent"):
		var percent := int(allowed["scale_percent"])
		if (
			not (allowed["scale_percent"] is int or allowed["scale_percent"] is float)
			or percent < WORLD_SCALE_MIN_PERCENT
			or percent > WORLD_SCALE_MAX_PERCENT
			or percent % WORLD_SCALE_STEP_PERCENT != 0
		):
			return {}
		allowed["scale_percent"] = percent
	return allowed


static func _validated_presentation_calibration(
	value: Dictionary,
	allow_half_pixel_offset: bool = false
) -> Dictionary:
	var normalized := {
		"contractId": "equipment.helmet.presentation_calibration.v1",
	}
	for role: String in ["paperDoll", "inventory", "ground"]:
		var raw: Variant = value.get(role, {})
		if not raw is Dictionary:
			return {}
		var source_row := int(raw.get("source_row", -1))
		if source_row < 0 or source_row > 7:
			return {}
		var record: Dictionary = {
			"source_row": source_row,
			"source_direction": canonical_direction(source_row),
		}
		var source_variant := str(raw.get("source_variant", ""))
		if not source_variant.is_empty():
			if (
				not allow_half_pixel_offset
				or role != "inventory"
				or source_variant != "dedicated_inventory"
			):
				return {}
			record["source_variant"] = source_variant
		if role == "paperDoll":
			var offset: Variant = raw.get("offset", [])
			var percent := int(raw.get("scale_percent", 100))
			if (
				not offset is Array
				or offset.size() != 2
				or percent < 10
				or percent > 300
				or percent % 5 != 0
			):
				return {}
			for coordinate: Variant in offset:
				if not (coordinate is int or coordinate is float):
					return {}
				var scaled_coordinate := float(coordinate) * (
					2.0 if allow_half_pixel_offset else 1.0
				)
				if not is_finite(float(coordinate)) or not is_equal_approx(
					scaled_coordinate, roundf(scaled_coordinate)
				):
					return {}
			record["offset"] = (
				[
					snappedf(float(offset[0]), 0.5),
					snappedf(float(offset[1]), 0.5),
				]
				if allow_half_pixel_offset
				else [int(offset[0]), int(offset[1])]
			)
			record["scale_percent"] = percent
		normalized[role] = record
	return normalized


static func _write_overrides(data: Dictionary) -> bool:
	var file := FileAccess.open(_override_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t", false) + "\n")
	file.close()
	return true


static func apply_alpha_mask(
	destination: Image,
	mask: Image,
	offset: Vector2i = Vector2i.ZERO
) -> Image:
	var result := destination.duplicate()
	var bounds := Rect2i(Vector2i.ZERO, result.get_size())
	for mask_y: int in mask.get_height():
		for mask_x: int in mask.get_width():
			var target := Vector2i(mask_x, mask_y) + offset
			if not bounds.has_point(target):
				continue
			var mask_alpha := mask.get_pixel(mask_x, mask_y).a
			if mask_alpha <= 0.0:
				continue
			var color: Color = result.get_pixelv(target)
			color.a *= 1.0 - mask_alpha
			result.set_pixelv(target, color)
	return result


static func _integer_vector(value: Variant) -> Vector2i:
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO


static func _numeric_vector(value: Variant) -> Vector2:
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
