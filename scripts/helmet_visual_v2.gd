class_name HelmetVisualV2
extends RefCounted

const CONTRACT_ID := "equipment.world_helmet.player_visual_v2"
const HEAD_SOCKET_CONTRACT_ID := "player.visual.head_socket.v1"
const CONTRACT_PATH := "res://assets/data/equipment_helmet_visual_v2.json"
const HEAD_SOCKET_PATH := "res://assets/data/player_head_socket_db.json"
const OVERRIDE_PATH := "res://assets/data/equipment_helmet_visual_v2_overrides.json"
const CANONICAL_DIRECTIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

static var _contract: Dictionary = {}
static var _head_sockets: Dictionary = {}
static var _overrides: Dictionary = {}
static var _session_overrides: Dictionary = {}


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
		_overrides = _json(OVERRIDE_PATH)
	return _overrides


static func reload_data() -> void:
	_contract = {}
	_head_sockets = {}
	_overrides = {}
	_session_overrides = {}


static func visual_asset_for_item(item_id: int) -> Dictionary:
	var data := contract()
	var asset_id := str(data.get("itemVisualAssetRefs", {}).get(str(item_id), ""))
	var asset: Variant = data.get("visualAssets", {}).get(asset_id, {})
	return asset if asset is Dictionary else {}


static func visual_asset_id_for_item(item_id: int) -> String:
	return str(contract().get("itemVisualAssetRefs", {}).get(str(item_id), ""))


static func canonical_direction(direction_row: int) -> String:
	return CANONICAL_DIRECTIONS[posmod(direction_row, CANONICAL_DIRECTIONS.size())]


static func direction_record(item_id: int, direction_row: int) -> Dictionary:
	var asset := visual_asset_for_item(item_id)
	var record: Variant = asset.get("directions", {}).get(canonical_direction(direction_row), {})
	if not record is Dictionary:
		return {}
	var merged: Dictionary = record.duplicate(true)
	var override: Variant = calibration_overrides().get("itemOverrides", {}).get(
		str(item_id), {}
	).get("directions", {}).get(canonical_direction(direction_row), {})
	if override is Dictionary:
		merged.merge(override, true)
	var session: Variant = _session_overrides.get(str(item_id), {}).get(
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
) -> Vector2i:
	var record := direction_record(item_id, direction_row)
	if record.is_empty():
		return Vector2i.ZERO
	var socket := body_head_socket(player_visual_id, action, direction_row, frame_index)
	if socket == Vector2i.ZERO:
		return Vector2i.ZERO
	var pivot := pivot_for_frame(item_id, action, direction_row, frame_index)
	var nudge := _integer_vector(record.get("nudge", []))
	return socket - pivot + nudge


static func pivot_for_frame(
	item_id: int,
	action: String,
	direction_row: int,
	frame_index: int
) -> Vector2i:
	var record := direction_record(item_id, direction_row)
	var frames: Variant = record.get("pivotByActionFrame", {}).get(action, [])
	if frames is Array and not frames.is_empty():
		return _integer_vector(frames[clampi(frame_index, 0, frames.size() - 1)])
	return _integer_vector(record.get("pivot", []))


static func action_texture_path(
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


static func is_locked(item_id: int, direction_row: int) -> bool:
	return bool(direction_record(item_id, direction_row).get("locked", false))


static func persist_calibration_override(
	item_id: int,
	direction_row: int,
	override_fields: Dictionary
) -> bool:
	var asset := visual_asset_for_item(item_id)
	if asset.is_empty() or bool(asset.get("readOnlyGoldenReference", false)):
		return false
	var allowed: Dictionary = {}
	for field: String in ["nudge", "status", "locked"]:
		if override_fields.has(field):
			allowed[field] = override_fields[field]
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
	var items: Dictionary = data.get("itemOverrides", {})
	var item: Dictionary = items.get(str(item_id), {})
	var directions: Dictionary = item.get("directions", {})
	directions[canonical_direction(direction_row)] = allowed
	item["directions"] = directions
	items[str(item_id)] = item
	data["itemOverrides"] = items
	var file := FileAccess.open(OVERRIDE_PATH, FileAccess.WRITE)
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
	if asset.is_empty() or bool(asset.get("readOnlyGoldenReference", false)):
		return false
	var item: Dictionary = _session_overrides.get(str(item_id), {})
	var direction := canonical_direction(direction_row)
	var current: Dictionary = item.get(direction, {})
	current.merge(override_fields, true)
	item[direction] = current
	_session_overrides[str(item_id)] = item
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
