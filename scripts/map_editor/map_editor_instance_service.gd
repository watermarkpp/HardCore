class_name MapEditorInstanceService
extends RefCounted

const PlacementAnchorPolicy := preload("res://scripts/map_assets/map_asset_placement_anchor_policy.gd")
const MATERIAL_LAYER_ORDER_MIN := -128
const MATERIAL_LAYER_ORDER_MAX := 128
const STATIC_MATERIAL_CHILD_Z_INDEX := 1
const MATERIAL_LAYER_NAMES := [
	"terrain_base", "terrain_front", "object_base", "object_front",
]
const ROLE_DEFAULTS := {
	"decoration": {"scene_intent": "visual_detail", "gameplay_role": "none", "placement_rule": "inside_map", "collision_policy": "none", "navigation_policy": "ignore"},
	"obstacle": {"scene_intent": "block_path", "gameplay_role": "navigation_blocker", "placement_rule": "non_overlapping", "collision_policy": "preset", "navigation_policy": "block_player_and_monster"},
	"building": {"scene_intent": "landmark", "gameplay_role": "service_or_landmark", "placement_rule": "non_overlapping", "collision_policy": "solid_footprint", "navigation_policy": "block_player_and_monster"},
	"interactable": {"scene_intent": "visual_detail", "gameplay_role": "interactable", "placement_rule": "inside_map", "collision_policy": "preset", "navigation_policy": "block_player_and_monster"},
	"terrain": {"scene_intent": "terrain_boundary", "gameplay_role": "navigation_blocker", "placement_rule": "non_overlapping", "collision_policy": "terrain_stamp_generated", "navigation_policy": "block_player_and_monster"},
}
const UNIFORM_VISUAL_SCALE_CONTRACT_ID := "maps.asset_visual_scale.base_relative_10pct.v1"
const UNIFORM_VISUAL_SCALE_STEP := 0.10
const MIN_RELATIVE_VISUAL_SCALE := 0.10
const MIN_ABSOLUTE_VISUAL_SCALE := 0.05
const MAX_ABSOLUTE_VISUAL_SCALE := 8.0


static func create_instance(document: Dictionary, asset_id: String, object_role: String, tile: Vector2i, layer := "object_base") -> Dictionary:
	var role := object_role if ROLE_DEFAULTS.has(object_role) else "decoration"
	var validation := MapEditorPlacementValidator.validate(document, asset_id, tile, layer, role)
	if not validation.ok:
		return {"ok": false, "errors": validation.errors, "warnings": validation.warnings}
	var asset: Dictionary = validation.asset
	var placement := MapEditorPlacementResolver.resolve(document,asset_id,tile,layer,role)
	var defaults: Dictionary = ROLE_DEFAULTS[role]
	var collision_policy := str(asset.get("collision_policy", defaults.collision_policy))
	var collision_footprint: Array = asset.get("collision_footprint_tiles", [])
	if collision_footprint.size() != 2:
		collision_footprint = [0, 0] if collision_policy in ["none", "manual"] else asset.get("footprint_tiles", [1, 1]).duplicate()
	var instance := {
		"instance_id": _next_id(document), "asset_id": asset_id, "object_role": role,
		"scene_intent": defaults.scene_intent, "gameplay_role": defaults.gameplay_role, "placement_rule": defaults.placement_rule,
		"tile": [tile.x, tile.y], "tile_anchor":[tile.x,tile.y], "offset_px": [0, 0], "position_mode":"tile_anchor", "layer": layer,
		"anchor_px": [placement.placement_anchor_px.x,placement.placement_anchor_px.y], "placement_anchor_px":[placement.placement_anchor_px.x,placement.placement_anchor_px.y], "anchor_mode": asset.get("anchor_mode", "foot_tile"),
		"placement_anchor_policy_id": str(asset.get("placement_anchor_policy_id", "")),
		"footprint_tiles": asset.get("footprint_tiles", [1, 1]),
		"collision_policy": collision_policy,
		"collision_profile_id":asset.get("collision_profile_id","none_visual"), "collision_footprint_tiles":collision_footprint,
		"collision_cells": asset.get("collision_cells", []).duplicate(true),
		"navigation_policy": asset.get("navigation_policy", defaults.navigation_policy),
		"manual_collision_expected": bool(asset.get("manual_collision_expected", false)),
		"map_collision_override": str(asset.get("map_collision_override", "default")),
		"collision_authority": str(asset.get("collision_authority", "asset")),
		"collision_policy_id": str(asset.get("collision_policy_id", "")),
		"occlusion": bool(asset.get("occlusion", false)), "runtime_export": true,
		"content_layer": "personal_expansion", "rotation_deg": 0.0, "scale": [float(asset.get("approved_scale",1.0)),float(asset.get("approved_scale",1.0))], "flip_x": false, "flip_y": false,
		"instance_base_scale": float(asset.get("approved_scale", 1.0)),
		"instance_base_footprint_tiles": asset.get("footprint_tiles", [1, 1]).duplicate(),
		"material_layer_order": 0,
		"selectable":true,"movable":true,"selection_locked":false,
	}
	var design_raw: Array = document.design.get("design_size", [0, 0])
	MapEditorInstanceProfileService.apply_adaptive_corner_offset(
		instance,
		asset,
		Vector2i(int(design_raw[0]), int(design_raw[1])),
		true
	)
	var layers: Dictionary = document.layers
	var entries: Array = layers.get(layer, [])
	entries.append(instance)
	layers[layer] = entries
	document.layers = layers
	return {"ok": true, "instance": instance, "warnings": validation.warnings}


static func move_instance(document: Dictionary, instance_id: String, tile: Vector2i) -> Dictionary:
	var located := _locate(document, instance_id)
	if not located.ok:
		return located
	var instance: Dictionary = located.instance
	var validation := MapEditorPlacementValidator.validate(
		document,
		instance.asset_id,
		tile,
		instance.layer,
		instance.object_role,
		instance_id,
		instance.get("footprint_tiles", [])
	)
	if not validation.ok:
		return {"ok": false, "errors": validation.errors}
	instance.tile = [tile.x, tile.y]
	instance.tile_anchor = [tile.x, tile.y]
	var asset := MapAssetCatalogService.find_asset(str(instance.get("asset_id", "")))
	var design_raw: Array = document.design.get("design_size", [0, 0])
	MapEditorInstanceProfileService.apply_adaptive_corner_offset(
		instance,
		asset,
		Vector2i(int(design_raw[0]), int(design_raw[1]))
	)
	_located_replace(document, located, instance)
	return {"ok": true, "instance": instance}


static func delete_instance(document: Dictionary, instance_id: String) -> Dictionary:
	var located := _locate(document, instance_id)
	if not located.ok:
		return located
	var entries: Array = document.layers[located.layer]
	entries.remove_at(located.index)
	document.layers[located.layer] = entries
	return {"ok": true, "deleted": instance_id}


static func duplicate_instance(document: Dictionary, instance_id: String, tile: Vector2i) -> Dictionary:
	var located := _locate(document, instance_id)
	if not located.ok:
		return located
	return duplicate_instance_snapshot(document, located.instance, tile)


static func duplicate_instance_snapshot(
	document: Dictionary,
	source_instance: Dictionary,
	tile: Vector2i
) -> Dictionary:
	var asset_id := str(source_instance.get("asset_id", ""))
	var layer := str(source_instance.get("layer", "object_base"))
	var role := str(source_instance.get("object_role", "decoration"))
	var validation := MapEditorPlacementValidator.validate(
		document,
		asset_id,
		tile,
		layer,
		role,
		"",
		source_instance.get("footprint_tiles", [])
	)
	if not validation.ok:
		return {"ok": false, "errors": validation.errors, "warnings": validation.warnings}
	var duplicate := source_instance.duplicate(true)
	duplicate["instance_id"] = _next_id(document)
	duplicate["tile"] = [tile.x, tile.y]
	duplicate["tile_anchor"] = [tile.x, tile.y]
	duplicate["layer"] = layer
	var asset := MapAssetCatalogService.find_asset(asset_id)
	var design_raw: Array = document.design.get("design_size", [0, 0])
	MapEditorInstanceProfileService.apply_adaptive_corner_offset(
		duplicate,
		asset,
		Vector2i(int(design_raw[0]), int(design_raw[1]))
	)
	# A manual copy is independent from generated dungeon structure metadata.
	for generated_key: String in ["generated_by", "structure_id", "structure_role"]:
		duplicate.erase(generated_key)
	var layers: Dictionary = document.layers
	var entries: Array = layers.get(layer, [])
	entries.append(duplicate)
	layers[layer] = entries
	document.layers = layers
	return {"ok": true, "instance": duplicate, "warnings": validation.warnings}


static func resize_instance(
	document: Dictionary,
	instance_id: String,
	direction: int
) -> Dictionary:
	if direction != -1 and direction != 1:
		return {
			"ok": false,
			"errors": ["invalid_resize_direction"],
		}

	var located := _locate(document, instance_id)
	if not located.ok:
		return located

	var instance: Dictionary = located.instance
	var asset := MapAssetCatalogService.find_asset(
		str(instance.get("asset_id", ""))
	)

	# Uniform 10% visual scale contract:
	# visual scale is authoritative;
	# integer footprint is derived from one stable base footprint.
	var base_scale := float(
		instance.get(
			"instance_base_scale",
			asset.get("approved_scale", 1.0)
		)
	)

	var current_scale_arr: Array = instance.get(
		"scale",
		[base_scale, base_scale]
	)
	var current_scale := float(current_scale_arr[0])

	var new_visual_scale := stepped_visual_scale(
		current_scale,
		base_scale,
		direction
	)

	if is_equal_approx(new_visual_scale, current_scale):
		return {
			"ok": true,
			"instance": instance,
		}

	# IMPORTANT:
	# For a legacy instance without instance_base_footprint_tiles,
	# resolve the same stable catalog base used for THIS calculation.
	# Never replace that base with old_fp after the operation.
	var base_footprint: Array = instance.get(
		"instance_base_footprint_tiles",
		asset.get(
			"base_footprint_tiles",
			asset.get("footprint_tiles", [1, 1])
		)
	).duplicate()

	var old_fp: Array = instance.get(
		"footprint_tiles",
		base_footprint
	)

	var new_fp: Array = footprint_for_visual_scale(
		base_footprint,
		base_scale,
		new_visual_scale
	)

	var fp_changed := (
		int(new_fp[0]) != int(old_fp[0])
		or int(new_fp[1]) != int(old_fp[1])
	)

	var old_offset_raw: Array = instance.get(
		"offset_px",
		[0, 0]
	)
	var old_offset := Vector2(
		float(old_offset_raw[0]),
		float(old_offset_raw[1])
	)

	var new_tile_v := Vector2i.ZERO
	var new_offset := old_offset

	if fp_changed:
		var actual_delta := Vector2i(
			int(new_fp[0]) - int(old_fp[0]),
			int(new_fp[1]) - int(old_fp[1])
		)

		var old_tile_raw: Array = instance.get(
			"tile",
			[0, 0]
		)
		var old_tile_v := Vector2i(
			int(old_tile_raw[0]),
			int(old_tile_raw[1])
		)

		if PlacementAnchorPolicy.applies_to(asset):
			# footprint_bottom_vertex_v1:
			#
			# Preserve:
			#
			# old_tile + old_footprint
			# ==
			# new_tile + new_footprint
			#
			# Therefore the authored visual foot does not jump when
			# integer footprint crosses a rounding threshold.
			new_tile_v = old_tile_v - actual_delta
			new_offset = old_offset
		else:
			# Non-foot-tile assets retain the previous center-preserving
			# behaviour. Do not change wall/non-foot anchor semantics.
			new_tile_v = old_tile_v - Vector2i(
				floori(float(actual_delta.x) / 2.0),
				floori(float(actual_delta.y) / 2.0)
			)

			var raw_size: Array = document.design.design_size
			var design_size := Vector2i(
				int(raw_size[0]),
				int(raw_size[1])
			)

			var old_center := MapEditorCoordinate.tile_to_ground_px(
				Vector2(old_tile_v)
				+ Vector2(
					float(old_fp[0]),
					float(old_fp[1])
				) * 0.5,
				design_size
			)

			var new_center := MapEditorCoordinate.tile_to_ground_px(
				Vector2(new_tile_v)
				+ Vector2(
					float(new_fp[0]),
					float(new_fp[1])
				) * 0.5,
				design_size
			)

			new_offset = (
				old_offset
				+ old_center
				- new_center
			)

		var map_size: Array = document.design.design_size

		if (
			new_tile_v.x < 0
			or new_tile_v.y < 0
			or new_tile_v.x + int(new_fp[0]) > int(map_size[0])
			or new_tile_v.y + int(new_fp[1]) > int(map_size[1])
		):
			return {
				"ok": false,
				"errors": ["缩放后超出地图边界"],
			}

	# The visual scale must always change by the exact 10% contract,
	# even when integer footprint did not change.
	instance["scale"] = [
		new_visual_scale,
		new_visual_scale,
	]

	instance["footprint_tiles"] = new_fp
	instance["occupancy_footprint_tiles"] = new_fp
	instance["visual_footprint_tiles"] = new_fp
	instance["instance_custom_scale"] = true

	# CRITICAL LEGACY FIX:
	#
	# Persist exactly the basis that was used for this calculation.
	#
	# DO NOT use old_fp here.
	instance["instance_base_scale"] = base_scale
	instance["instance_base_footprint_tiles"] = (
		base_footprint.duplicate()
	)

	instance["instance_scale_level"] = (
		int(instance.get("instance_scale_level", 0))
		+ direction
	)

	if fp_changed:
		instance["tile"] = [
			new_tile_v.x,
			new_tile_v.y,
		]
		instance["tile_anchor"] = [
			new_tile_v.x,
			new_tile_v.y,
		]
		instance["offset_px"] = [
			new_offset.x,
			new_offset.y,
		]

		_resize_instance_collision(
			instance,
			old_fp,
			new_fp
		)

	PlacementAnchorPolicy.refresh_custom_instance(
		instance,
		asset
	)

	_located_replace(
		document,
		located,
		instance
	)

	return {
		"ok": true,
		"instance": instance,
	}


static func stepped_visual_scale(current_scale: float, base_scale: float, direction: int) -> float:
	var safe_base := maxf(base_scale, 0.01)
	var dir := 1.0 if direction > 0 else -1.0
	var min_scale := maxf(MIN_ABSOLUTE_VISUAL_SCALE, safe_base * MIN_RELATIVE_VISUAL_SCALE)
	var stepped := current_scale + dir * safe_base * UNIFORM_VISUAL_SCALE_STEP
	return clampf(stepped, min_scale, MAX_ABSOLUTE_VISUAL_SCALE)


static func footprint_for_visual_scale(base_footprint: Array, base_scale: float, visual_scale: float) -> Array:
	var safe_base := maxf(base_scale, 0.01)
	var relative_factor := visual_scale / safe_base
	var width := maxi(1, roundi(float(int(base_footprint[0])) * relative_factor))
	var height := maxi(1, roundi(float(int(base_footprint[1])) * relative_factor))
	return [width, height]


static func adjust_material_layer_order(
	document: Dictionary,
	instance_id: String,
	delta: int
) -> Dictionary:
	var located := _locate(document, instance_id)
	if not located.get("ok", false):
		return located
	if delta == 0:
		return {
			"ok": true,
			"instance": located.instance,
			"material_layer_order": material_layer_order(located.instance),
		}
	var instance: Dictionary = located.instance
	var next_order := clampi(
		material_layer_order(instance) + delta,
		MATERIAL_LAYER_ORDER_MIN,
		MATERIAL_LAYER_ORDER_MAX
	)
	instance["material_layer_order"] = next_order
	_located_replace(document, located, instance)
	return {
		"ok": true,
		"instance": instance,
		"material_layer_order": next_order,
	}


static func material_layer_order(instance: Dictionary) -> int:
	return clampi(
		int(instance.get("material_layer_order", 0)),
		MATERIAL_LAYER_ORDER_MIN,
		MATERIAL_LAYER_ORDER_MAX
	)


static func sorted_for_material_render(instances: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for instance: Dictionary in instances:
		result.append(instance)
	result.sort_custom(_material_render_less)
	return result


static func _material_render_less(a: Dictionary, b: Dictionary) -> bool:
	var a_order := material_layer_order(a)
	var b_order := material_layer_order(b)
	if a_order != b_order:
		return a_order < b_order
	var a_tile := _material_sort_tile(a)
	var b_tile := _material_sort_tile(b)
	var a_depth := a_tile.x + a_tile.y
	var b_depth := b_tile.x + b_tile.y
	if a_depth != b_depth:
		return a_depth < b_depth
	if a_tile.x != b_tile.x:
		return a_tile.x < b_tile.x
	var a_layer := MATERIAL_LAYER_NAMES.find(str(a.get("layer", "object_base")))
	var b_layer := MATERIAL_LAYER_NAMES.find(str(b.get("layer", "object_base")))
	if a_layer != b_layer:
		return a_layer < b_layer
	return str(a.get("instance_id", "")) < str(b.get("instance_id", ""))


static func _material_sort_tile(instance: Dictionary) -> Vector2i:
	var tile: Array = instance.get("tile", [0, 0])
	var footprint: Array = instance.get("footprint_tiles", [1, 1])
	var adaptive: Array = instance.get("adaptive_corner_sort_tile_offset", [0, 0])
	return Vector2i(
		int(tile[0]) + maxi(0, int(footprint[0]) - 1)
			+ (int(adaptive[0]) if adaptive.size() >= 1 else 0),
		int(tile[1]) + maxi(0, int(footprint[1]) - 1)
			+ (int(adaptive[1]) if adaptive.size() >= 2 else 0)
	)


static func configure_runtime_material_canvas_item(
	item: CanvasItem,
	instance: Dictionary
) -> void:
	# Runtime map materials stay relative to WorldBackground (z=-20). Keeping
	# every material at child z=1 makes sibling order control only material vs.
	# material overlap; actors at the world root remain above them at z=0.
	item.z_as_relative = true
	item.z_index = STATIC_MATERIAL_CHILD_Z_INDEX
	item.set_meta("material_layer_order", material_layer_order(instance))


static func _resize_instance_collision(instance: Dictionary, old_fp: Array, new_fp: Array) -> void:
	var policy := str(instance.get("collision_policy", "none"))
	if policy in ["none", "manual"]:
		instance["collision_footprint_tiles"] = [0, 0]
		return
	if policy in ["solid_footprint", "terrain_stamp_generated"]:
		instance["collision_footprint_tiles"] = new_fp.duplicate()
		return
	var collision: Array = instance.get("collision_footprint_tiles", [0, 0])
	if collision.size() != 2 or int(collision[0]) <= 0 or int(collision[1]) <= 0:
		instance["collision_footprint_tiles"] = new_fp.duplicate()
		return
	var width_ratio := float(new_fp[0]) / maxf(1.0, float(old_fp[0]))
	var height_ratio := float(new_fp[1]) / maxf(1.0, float(old_fp[1]))
	instance["collision_footprint_tiles"] = [
		maxi(1, roundi(float(collision[0]) * width_ratio)),
		maxi(1, roundi(float(collision[1]) * height_ratio)),
	]


static func all_instances(document: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for layer_name: String in document.get("layers", {}):
		for instance: Dictionary in document.layers[layer_name]:
			if instance.has("instance_id"):
				result.append(instance)
	return result


static func _next_id(document: Dictionary) -> String:
	var maximum := 0
	for instance: Dictionary in all_instances(document):
		var value := str(instance.get("instance_id", "")).trim_prefix("inst_").to_int()
		maximum = maxi(maximum, value)
	return "inst_%06d" % (maximum + 1)


static func _locate(document: Dictionary, instance_id: String) -> Dictionary:
	for layer_name: String in document.get("layers", {}):
		var entries: Array = document.layers[layer_name]
		for index in entries.size():
			var instance: Dictionary = entries[index]
			if str(instance.get("instance_id", "")) == instance_id:
				return {"ok": true, "layer": layer_name, "index": index, "instance": instance}
	return {"ok": false, "errors": ["instance_not_found"]}


static func _located_replace(document: Dictionary, located: Dictionary, instance: Dictionary) -> void:
	var entries: Array = document.layers[located.layer]
	entries[located.index] = instance
	document.layers[located.layer] = entries
