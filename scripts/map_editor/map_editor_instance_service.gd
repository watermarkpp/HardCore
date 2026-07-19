class_name MapEditorInstanceService
extends RefCounted

const PlacementAnchorPolicy := preload("res://scripts/map_assets/map_asset_placement_anchor_policy.gd")
const ROLE_DEFAULTS := {
	"decoration": {"scene_intent": "visual_detail", "gameplay_role": "none", "placement_rule": "inside_map", "collision_policy": "none", "navigation_policy": "ignore"},
	"obstacle": {"scene_intent": "block_path", "gameplay_role": "navigation_blocker", "placement_rule": "non_overlapping", "collision_policy": "preset", "navigation_policy": "block_player_and_monster"},
	"building": {"scene_intent": "landmark", "gameplay_role": "service_or_landmark", "placement_rule": "non_overlapping", "collision_policy": "solid_footprint", "navigation_policy": "block_player_and_monster"},
	"interactable": {"scene_intent": "visual_detail", "gameplay_role": "interactable", "placement_rule": "inside_map", "collision_policy": "preset", "navigation_policy": "block_player_and_monster"},
	"terrain": {"scene_intent": "terrain_boundary", "gameplay_role": "navigation_blocker", "placement_rule": "non_overlapping", "collision_policy": "terrain_stamp_generated", "navigation_policy": "block_player_and_monster"},
}


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
		"selectable":true,"movable":true,"selection_locked":false,
	}
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
	# A manual copy is independent from generated dungeon structure metadata.
	for generated_key: String in ["generated_by", "structure_id", "structure_role"]:
		duplicate.erase(generated_key)
	var layers: Dictionary = document.layers
	var entries: Array = layers.get(layer, [])
	entries.append(duplicate)
	layers[layer] = entries
	document.layers = layers
	return {"ok": true, "instance": duplicate, "warnings": validation.warnings}


static func resize_instance(document: Dictionary, instance_id: String, direction: int) -> Dictionary:
	var located := _locate(document, instance_id)
	if not located.ok:
		return located
	var instance: Dictionary = located.instance
	var asset := MapAssetCatalogService.find_asset(str(instance.get("asset_id", "")))
	var base_fp: Array = asset.get("base_footprint_tiles", asset.get("footprint_tiles", [1, 1]))
	var old_fp: Array = instance.get("footprint_tiles", base_fp)
	var old_width := int(old_fp[0]); var old_height := int(old_fp[1])
	if direction < 0 and old_width == 1 and old_height == 1:
		return {"ok": true, "instance": instance}
	var new_fp: Array
	if int(base_fp[0]) == int(base_fp[1]):
		var side := maxi(1, old_width + (1 if direction > 0 else -1))
		new_fp = [side, side]
	elif int(base_fp[0]) > int(base_fp[1]):
		var width := maxi(1, old_width + (1 if direction > 0 else -1))
		var height := maxi(1, roundi(float(width) * float(base_fp[1]) / float(base_fp[0])))
		new_fp = [width, height]
	else:
		var height := maxi(1, old_height + (1 if direction > 0 else -1))
		var width := maxi(1, roundi(float(height) * float(base_fp[0]) / float(base_fp[1])))
		new_fp = [width, height]
	var actual_delta := Vector2i(int(new_fp[0]) - int(old_fp[0]), int(new_fp[1]) - int(old_fp[1]))
	if actual_delta == Vector2i.ZERO:
		return {"ok": true, "instance": instance}
	var old_tile: Array = instance.get("tile", [0, 0])
	var old_tile_v := Vector2i(int(old_tile[0]), int(old_tile[1]))
	var new_tile := old_tile_v - Vector2i(floori(float(actual_delta.x) / 2.0), floori(float(actual_delta.y) / 2.0))
	var map_size: Array = document.design.design_size
	if new_tile.x < 0 or new_tile.y < 0 or new_tile.x + int(new_fp[0]) > int(map_size[0]) or new_tile.y + int(new_fp[1]) > int(map_size[1]):
		return {"ok": false, "errors": ["缩放后超出地图边界"]}
	# Resize relative to the instance's current visual scale. The approved asset
	# scale is independent from its logical footprint (for example a 4×4 tree
	# may start at 0.40). Recomputing from footprint/base_footprint would reset
	# 0.40 to 0.75 on the first shrink and make the sprite grow instead.
	var old_scale: Array = instance.get("scale", [float(asset.get("approved_scale", 1.0)), float(asset.get("approved_scale", 1.0))])
	var next_scale := resized_visual_scale(Vector2(float(old_scale[0]), float(old_scale[1])), old_fp, new_fp)
	var raw_size: Array = document.design.design_size
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var old_center := MapEditorCoordinate.tile_to_ground_px(Vector2(old_tile_v) + Vector2(float(old_fp[0]),float(old_fp[1])) * 0.5, design_size)
	var new_center := MapEditorCoordinate.tile_to_ground_px(Vector2(new_tile) + Vector2(float(new_fp[0]),float(new_fp[1])) * 0.5, design_size)
	var old_offset: Array = instance.get("offset_px", [0,0])
	var compensated_offset := Vector2(float(old_offset[0]),float(old_offset[1])) + old_center - new_center
	instance["tile"] = [new_tile.x, new_tile.y]
	instance["tile_anchor"] = [new_tile.x, new_tile.y]
	instance["footprint_tiles"] = new_fp
	instance["occupancy_footprint_tiles"] = new_fp
	instance["visual_footprint_tiles"] = new_fp
	instance["scale"] = [next_scale.x, next_scale.y]
	instance["offset_px"] = [roundi(compensated_offset.x),roundi(compensated_offset.y)]
	instance["instance_scale_level"] = int(instance.get("instance_scale_level", 0)) + (1 if direction > 0 else -1)
	instance["instance_custom_scale"] = true
	instance["instance_base_scale"] = float(instance.get("instance_base_scale", asset.get("approved_scale", 1.0)))
	instance["instance_base_footprint_tiles"] = instance.get("instance_base_footprint_tiles", old_fp).duplicate()
	PlacementAnchorPolicy.refresh_custom_instance(instance, asset)
	_resize_instance_collision(instance, old_fp, new_fp)
	_located_replace(document, located, instance)
	return {"ok": true, "instance": instance}


static func resized_visual_scale(current_scale: Vector2, old_fp: Array, new_fp: Array) -> Vector2:
	var old_primary := maxf(1.0, maxf(float(old_fp[0]), float(old_fp[1])))
	var new_primary := maxf(1.0, maxf(float(new_fp[0]), float(new_fp[1])))
	return current_scale * (new_primary / old_primary)


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
