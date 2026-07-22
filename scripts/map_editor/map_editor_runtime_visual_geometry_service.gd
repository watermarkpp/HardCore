class_name MapEditorRuntimeVisualGeometryService
extends RefCounted

const VISUAL_GEOMETRY_CONTRACT_ID := "map_editor_runtime_visual_geometry_v1"
const EDITOR_LAYOUT_CONTRACT_ID := "map_editor_authoritative_layout_v1"
const MATERIAL_LAYER_NAMES := [
	"terrain_base", "terrain_front", "object_base", "object_front",
]
const SEMANTIC_LAYER_NAMES := [
	"npc_points", "monster_spawn", "boss_spawn", "door_points",
	"map_entrance_points", "map_exit_points", "respawn_points",
	"safe_area", "light", "region_trigger",
]


static func instance_foot_tile(
	instance: Dictionary,
	asset: Dictionary
) -> Vector2:
	var tile: Array = instance.get("tile", [0, 0])
	var footprint: Array = instance.get(
		"footprint_tiles", asset.get("footprint_tiles", [1, 1])
	)
	if str(asset.get("asset_type", "")) == "wall_module":
		return Vector2(float(tile[0]) + 0.5, float(tile[1]) + 0.5)
	return Vector2(
		float(tile[0]) + float(footprint[0]) * 0.5,
		float(tile[1]) + float(footprint[1]) * 0.5
	)


static func resolved_anchor_px(
	instance: Dictionary,
	asset: Dictionary,
	command_anchor: Array = []
) -> Vector2:
	if command_anchor.size() == 2:
		return Vector2(float(command_anchor[0]), float(command_anchor[1]))
	var raw: Array = instance.get(
		"anchor_px",
		instance.get(
			"placement_anchor_px", asset.get("anchor_px", [0, 0])
		)
	)
	return Vector2(float(raw[0]), float(raw[1]))


static func editor_instance_geometry(
	instance: Dictionary,
	asset: Dictionary,
	design_size: Vector2i,
	draw_offset: Vector2,
	draw_scale: float,
	texture_size: Vector2,
	command_anchor: Array = []
) -> Dictionary:
	var offset_px: Array = instance.get("offset_px", [0, 0])
	var authored_center := (
		MapEditorCoordinate.tile_to_ground_px(
			instance_foot_tile(instance, asset), design_size
		)
		+ Vector2(float(offset_px[0]), float(offset_px[1]))
	)
	return _geometry_from_center(
		instance,
		asset,
		draw_offset + authored_center * draw_scale,
		draw_scale,
		texture_size,
		command_anchor
	)


static func runtime_instance_geometry(
	instance: Dictionary,
	asset: Dictionary,
	design_size: Vector2i,
	texture_size: Vector2,
	command_anchor: Array = []
) -> Dictionary:
	var offset_px: Array = instance.get("offset_px", [0, 0])
	var world_center := (
		MapEditorCoordinate.tile_to_world(
			instance_foot_tile(instance, asset), design_size
		)
		+ Vector2(float(offset_px[0]), float(offset_px[1]))
	)
	return _geometry_from_center(
		instance,
		asset,
		world_center,
		1.0,
		texture_size,
		command_anchor
	)


static func editor_command_geometry(
	command: Dictionary,
	design_size: Vector2i,
	draw_offset: Vector2,
	draw_scale: float,
	texture_size: Vector2
) -> Dictionary:
	return editor_instance_geometry(
		command.instance,
		command.asset,
		design_size,
		draw_offset,
		draw_scale,
		texture_size,
		command.get("anchor", [])
	)


static func runtime_command_geometry(
	command: Dictionary,
	design_size: Vector2i,
	texture_size: Vector2
) -> Dictionary:
	return runtime_instance_geometry(
		command.instance,
		command.asset,
		design_size,
		texture_size,
		command.get("anchor", [])
	)


static func _geometry_from_center(
	instance: Dictionary,
	asset: Dictionary,
	center: Vector2,
	draw_scale: float,
	texture_size: Vector2,
	command_anchor: Array
) -> Dictionary:
	var instance_scale: Array = instance.get("scale", [1.0, 1.0])
	var visual_scale := Vector2(
		float(instance_scale[0]), float(instance_scale[1])
	) * draw_scale
	var anchor := resolved_anchor_px(instance, asset, command_anchor)
	var top_left := center - anchor * visual_scale
	var selection_bounds: Array = asset.get("selection_bounds_px", [])
	var visual_rect := Rect2(top_left, texture_size * visual_scale)
	if command_anchor.is_empty() and selection_bounds.size() == 4:
		visual_rect = Rect2(
			top_left + Vector2(
				float(selection_bounds[0]), float(selection_bounds[1])
			) * visual_scale,
			Vector2(
				float(selection_bounds[2]), float(selection_bounds[3])
			) * visual_scale
		)
	return {
		"center": center,
		"anchor": anchor,
		"visual_scale": visual_scale,
		"rotation": deg_to_rad(float(instance.get("rotation_deg", 0.0))),
		"top_left": top_left,
		"rect": visual_rect,
	}


static func instance_draw_commands(
	instance: Dictionary,
	asset: Dictionary,
	layer_index := 0,
	sequence := 0
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tile_raw: Array = instance.get("tile", [0, 0])
	var footprint: Array = instance.get(
		"footprint_tiles", asset.get("footprint_tiles", [1, 1])
	)
	var instance_tile := Vector2i(int(tile_raw[0]), int(tile_raw[1]))
	var adaptive_raw: Array = instance.get(
		"adaptive_corner_sort_tile_offset", [0, 0]
	)
	var adaptive := Vector2i(
		int(adaptive_raw[0]) if adaptive_raw.size() >= 1 else 0,
		int(adaptive_raw[1]) if adaptive_raw.size() >= 2 else 0
	)
	var render_parts: Array = asset.get("render_parts", [])
	if (
		str(asset.get("asset_type", "")) == "wall_module"
		and not render_parts.is_empty()
	):
		for part: Dictionary in render_parts:
			var sort_offset_raw: Array = part.get(
				"sort_tile_offset", part.get("tile_offset", [0, 0])
			)
			var sort_tile := instance_tile + Vector2i(
				int(sort_offset_raw[0]), int(sort_offset_raw[1])
			) + adaptive
			var anchor: Array = part.get(
				"anchor", asset.get("anchor_px", [0, 0])
			)
			for image_pass: Dictionary in [
				{"field": "shadow_image", "pass": 0},
				{"field": "base_image", "pass": 1},
				{"field": "front_image", "pass": 2},
			]:
				var image_path := str(part.get(str(image_pass.field), ""))
				if image_path.is_empty():
					continue
				result.append({
					"instance": instance,
					"asset": asset,
					"image_path": image_path,
					"anchor": anchor,
					"sort_tile": sort_tile,
					"layer_index": layer_index,
					"image_pass": int(image_pass.pass),
					"part_order": int(part.get("draw_order_index", 0)),
					"sequence": sequence,
				})
		return result
	var sort_tile := instance_tile + Vector2i(
		maxi(0, int(footprint[0]) - 1),
		maxi(0, int(footprint[1]) - 1)
	) + adaptive
	result.append({
		"instance": instance,
		"asset": asset,
		"image_path": str(asset.get("image", "")),
		"anchor": [],
		"sort_tile": sort_tile,
		"layer_index": layer_index,
		"image_pass": 1,
		"part_order": 0,
		"sequence": sequence,
	})
	return result


static func sorted_draw_commands(instances: Array) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	var sequence := 0
	for instance: Dictionary in instances:
		var asset := MapAssetCatalogService.find_asset(
			str(instance.get("asset_id", ""))
		)
		var layer_index := MATERIAL_LAYER_NAMES.find(
			str(instance.get("layer", "object_base"))
		)
		for command: Dictionary in instance_draw_commands(
			instance, asset, maxi(0, layer_index), sequence
		):
			commands.append(command)
		sequence += 1
	commands.sort_custom(draw_command_less)
	return commands


static func draw_command_less(a: Dictionary, b: Dictionary) -> bool:
	var a_order := MapEditorInstanceService.material_layer_order(a.instance)
	var b_order := MapEditorInstanceService.material_layer_order(b.instance)
	if a_order != b_order:
		return a_order < b_order
	var a_tile: Vector2i = a.sort_tile
	var b_tile: Vector2i = b.sort_tile
	var a_depth := a_tile.x + a_tile.y
	var b_depth := b_tile.x + b_tile.y
	if a_depth != b_depth:
		return a_depth < b_depth
	if a_tile.x != b_tile.x:
		return a_tile.x < b_tile.x
	if int(a.layer_index) != int(b.layer_index):
		return int(a.layer_index) < int(b.layer_index)
	if int(a.image_pass) != int(b.image_pass):
		return int(a.image_pass) < int(b.image_pass)
	if int(a.part_order) != int(b.part_order):
		return int(a.part_order) < int(b.part_order)
	return int(a.sequence) < int(b.sequence)


static func geometry_payload(instances: Array) -> Array[Dictionary]:
	var payload: Array[Dictionary] = []
	for instance: Dictionary in instances:
		var entry := {}
		for field: String in [
			"instance_id", "asset_id", "layer", "tile", "tile_anchor",
			"footprint_tiles", "offset_px", "anchor_px",
			"placement_anchor_px", "scale", "rotation_deg",
			"material_layer_order", "adaptive_corner_sort_tile_offset",
		]:
			if instance.has(field):
				entry[field] = instance[field]
		payload.append(entry)
	payload.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("instance_id", "")) < str(b.get("instance_id", ""))
	)
	return payload


static func geometry_sha256(instances: Array) -> String:
	return _sha256_text(MapEditorJsonCodec.encode({
		"contract_id": VISUAL_GEOMETRY_CONTRACT_ID,
		"instances": geometry_payload(instances),
		"draw_commands": draw_command_payload(instances),
	}))


static func draw_command_payload(instances: Array) -> Array[Dictionary]:
	var payload: Array[Dictionary] = []
	for command: Dictionary in sorted_draw_commands(instances):
		var sort_tile: Vector2i = command.sort_tile
		payload.append({
			"instance_id": str(command.instance.get("instance_id", "")),
			"asset_id": str(command.instance.get("asset_id", "")),
			"asset_type": str(command.asset.get("asset_type", "")),
			"image_path": str(command.image_path),
			"anchor": command.get("anchor", []).duplicate(),
			"sort_tile": [sort_tile.x, sort_tile.y],
			"layer_index": int(command.layer_index),
			"image_pass": int(command.image_pass),
			"part_order": int(command.part_order),
			"sequence": int(command.sequence),
		})
	return payload


static func document_content_sha256(document: Dictionary) -> String:
	return _sha256_text(MapEditorJsonCodec.encode(document))


static func editor_layout_sha256(document: Dictionary) -> String:
	var semantics: Array[Dictionary] = []
	for layer_name: String in SEMANTIC_LAYER_NAMES:
		for entry: Dictionary in document.get("layers", {}).get(layer_name, []):
			semantics.append({
				"layer": layer_name,
				"semantic_id": str(entry.get("semantic_id", "")),
				"kind": str(entry.get("kind", "")),
				"tile": entry.get("tile", []).duplicate(),
				"radius_tiles": entry.get("radius_tiles", 0),
				"display_name": str(entry.get("display_name", "")),
			})
	semantics.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				str(a.layer) + ":" + str(a.semantic_id)
				< str(b.layer) + ":" + str(b.semantic_id)
			)
	)
	var instances := MapEditorInstanceService.all_instances(document)
	return _sha256_text(MapEditorJsonCodec.encode({
		"contract_id": EDITOR_LAYOUT_CONTRACT_ID,
		"design_size": document.get("design", {}).get("design_size", []),
		"geometry": geometry_payload(instances),
		"semantics": semantics,
	}))


static func _sha256_text(value: String) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(value.to_utf8_buffer())
	return hashing.finish().hex_encode()
