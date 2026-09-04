extends Node

const InstanceProfileService := preload("res://scripts/map_editor/map_editor_instance_profile_service.gd")
const PlacementAnchorPolicy := preload("res://scripts/map_assets/map_asset_placement_anchor_policy.gd")
const Coordinate := preload("res://scripts/map_editor/map_editor_coordinate.gd")
const JsonCodec := preload("res://scripts/map_editor/map_editor_json_codec.gd")
const MapEditorAppScript := preload("res://scripts/map_editor/map_editor_app.gd")
const DESIGN_SIZE := Vector2i(32, 32)
const EPSILON := 0.01


func _ready() -> void:
	_test_footprint_resize_preserves_foot()
	_test_anchor_change_preserves_foot()
	_test_asset_scale_and_custom_instance_contracts()
	_test_noop_and_idempotence()
	_test_fail_closed_and_rollback()
	_test_candidate_document_transaction()
	print("MSE_INSTANCE_PROFILE_REFRESH_POSITION_REGRESSION_PASS")
	get_tree().quit(0)


func _test_footprint_resize_preserves_foot() -> void:
	var old_asset := _asset("synthetic.old_2x2", [96, 160], [2, 2], 1.0)
	var new_asset := _asset("synthetic.new_3x3", [96, 160], [3, 3], 1.0)
	var old_placement := PlacementAnchorPolicy.placement_anchor_px(
		old_asset, [2, 2], Vector2.ONE
	)
	var instance := _instance(
		"resize", [12, 13], [2, 2], _pair_array(old_placement),
		Vector2.ONE, [0, 0], true
	)
	var before := _visual_foot(instance, new_asset)
	var result := InstanceProfileService.refresh_from_asset(
		instance, new_asset, DESIGN_SIZE
	)
	assert(bool(result.get("ok", false)), str(result.get("errors", [])))
	assert(instance.get("tile", []) == [11, 12], "footprint policy must move tile by delta")
	assert(instance.get("footprint_tiles", []) == [3, 3])
	assert(_visual_foot(instance, new_asset).distance_to(before) < EPSILON)


func _test_anchor_change_preserves_foot() -> void:
	var old_asset := _asset("synthetic.old_anchor", [80, 140], [3, 3], 1.0)
	var new_asset := _asset("synthetic.new_anchor", [112, 116], [3, 3], 1.0)
	var old_placement := PlacementAnchorPolicy.placement_anchor_px(
		old_asset, [3, 3], Vector2.ONE
	)
	var instance := _instance(
		"anchor", [7, 8], [3, 3], _pair_array(old_placement),
		Vector2.ONE, [4, -3], true
	)
	var before := _visual_foot(instance, new_asset)
	var result := InstanceProfileService.refresh_from_asset(
		instance, new_asset, DESIGN_SIZE
	)
	assert(bool(result.get("ok", false)), str(result.get("errors", [])))
	assert(instance.get("offset_px", []) != [4, -3], "anchor delta needs one residual correction")
	assert(_visual_foot(instance, new_asset).distance_to(before) < EPSILON)


func _test_asset_scale_and_custom_instance_contracts() -> void:
	var old_asset := _asset("synthetic.old_scale", [100, 150], [2, 2], 1.0)
	var new_asset := _asset("synthetic.new_scale", [124, 126], [3, 2], 1.25)
	var old_placement := PlacementAnchorPolicy.placement_anchor_px(
		old_asset, [2, 2], Vector2.ONE
	)
	var normal := _instance(
		"base_scale", [10, 10], [2, 2], _pair_array(old_placement),
		Vector2.ONE, [2, 6], true
	)
	var normal_before := _visual_foot(normal, new_asset)
	var normal_result := InstanceProfileService.refresh_from_asset(
		normal, new_asset, DESIGN_SIZE
	)
	assert(bool(normal_result.get("ok", false)), str(normal_result.get("errors", [])))
	assert(normal.get("scale", []) == [1.25, 1.25])
	assert(normal.get("footprint_tiles", []) == [3, 2])
	assert(_visual_foot(normal, new_asset).distance_to(normal_before) < EPSILON)

	var custom := _instance(
		"custom_scale", [11, 9], [3, 2], [41, 57],
		Vector2(0.73, 0.73), [13, -9], true, true
	)
	var custom_before := _visual_foot(custom, new_asset)
	var custom_fp: Array = custom.footprint_tiles.duplicate()
	var custom_scale: Array = custom.scale.duplicate()
	var custom_result := InstanceProfileService.refresh_from_asset(
		custom, new_asset, DESIGN_SIZE
	)
	assert(bool(custom_result.get("ok", false)), str(custom_result.get("errors", [])))
	assert(custom.footprint_tiles == custom_fp, "custom footprint is user-owned")
	assert(custom.scale == custom_scale, "custom scale is user-owned")
	assert(_visual_foot(custom, new_asset).distance_to(custom_before) < EPSILON)


func _test_noop_and_idempotence() -> void:
	var asset := _asset("synthetic.noop", [90, 130], [2, 2], 1.0)
	var placement := PlacementAnchorPolicy.placement_anchor_px(asset, [2, 2], Vector2.ONE)
	var instance := _instance(
		"noop", [5, 6], [2, 2], _pair_array(placement),
		Vector2.ONE, [5, -2], true
	)
	var first := InstanceProfileService.refresh_from_asset(instance, asset, DESIGN_SIZE)
	assert(bool(first.get("ok", false)), str(first.get("errors", [])))
	var first_bytes := JsonCodec.encode(instance)
	var second := InstanceProfileService.refresh_from_asset(instance, asset, DESIGN_SIZE)
	assert(bool(second.get("ok", false)), str(second.get("errors", [])))
	assert(JsonCodec.encode(instance) == first_bytes, "refresh must be idempotent")


func _test_fail_closed_and_rollback() -> void:
	var asset := _asset("synthetic.invalid", [100, 140], [2, 2], 1.0)
	var placement := PlacementAnchorPolicy.placement_anchor_px(asset, [2, 2], Vector2.ONE)
	var base := _instance(
		"invalid", [8, 8], [2, 2], _pair_array(placement),
		Vector2.ONE, [0, 0], true
	)
	var invalid_cases := [
		{"field": "tile", "value": ["bad", 8]},
		{"field": "footprint_tiles", "value": [0, 2]},
		{"field": "anchor_px", "value": ["bad", 8]},
		{"field": "scale", "value": ["bad", 1.0]},
		{"field": "tile", "value": [31, 31]},
	]
	for invalid_case: Dictionary in invalid_cases:
		var candidate: Dictionary = base.duplicate(true)
		candidate[str(invalid_case.field)] = invalid_case.value
		var before := JsonCodec.encode(candidate)
		var result := InstanceProfileService.refresh_from_asset(
			candidate, asset, DESIGN_SIZE
		)
		assert(not bool(result.get("ok", false)), str(invalid_case))
		assert(JsonCodec.encode(candidate) == before, "failed refresh mutated input")

	var too_large_asset := _asset("synthetic.too_large", [100, 140], [4, 4], 1.0)
	var edge := _instance(
		"edge", [1, 1], [2, 2], _pair_array(placement),
		Vector2.ONE, [0, 0], true
	)
	var edge_before := JsonCodec.encode(edge)
	var edge_result := InstanceProfileService.refresh_from_asset(
		edge, too_large_asset, DESIGN_SIZE
	)
	assert(not bool(edge_result.get("ok", false)), str(edge_result.get("errors", [])))
	assert(JsonCodec.encode(edge) == edge_before)


func _test_candidate_document_transaction() -> void:
	var document := {
		"map_id": "synthetic_transaction",
		"design": {"design_size": [32, 32]},
		"layers": {
			"terrain_base": [], "terrain_front": [],
			"object_base": [{"instance_id": "inst_000001", "asset_id": "missing.synthetic"}],
			"object_front": [],
		},
	}
	var before := JsonCodec.encode(document)
	var result := MapEditorAppScript.migrate_loaded_instances_to_class_profiles(document)
	assert(not bool(result.get("ok", false)), str(result))
	assert(JsonCodec.encode(document) == before, "candidate migration polluted source document")
func _asset(
	asset_id: String,
	source_anchor: Array,
	footprint: Array,
	approved_scale: float,
	foot_tile := true
) -> Dictionary:
	var asset := {
		"asset_id": asset_id,
		"asset_type": "large_prop",
		"object_class": "small_prop",
		"anchor_mode": "foot_tile" if foot_tile else "tile_center",
		"anchor_px": source_anchor.duplicate(),
		"footprint_tiles": footprint.duplicate(),
		"occupancy_footprint_tiles": footprint.duplicate(),
		"approved_scale": approved_scale,
		"placeable": true,
		"collision_policy": "none",
		"collision_footprint_tiles": [0, 0],
		"map_collision_override": "default",
	}
	if foot_tile:
		var placement := PlacementAnchorPolicy.placement_anchor_px(
			asset, footprint, Vector2(approved_scale, approved_scale)
		)
		asset["placement_anchor_px"] = _pair_array(placement)
		asset["placement_anchor_policy_id"] = PlacementAnchorPolicy.POLICY_ID
	else:
		asset["placement_anchor_px"] = source_anchor.duplicate()
	return asset


func _instance(
	instance_id: String,
	tile: Array,
	footprint: Array,
	anchor: Array,
	visual_scale: Vector2,
	offset: Array,
	foot_tile := true,
	custom_scale := false
) -> Dictionary:
	return {
		"instance_id": instance_id,
		"asset_id": "synthetic.asset",
		"layer": "object_base",
		"tile": tile.duplicate(),
		"tile_anchor": tile.duplicate(),
		"footprint_tiles": footprint.duplicate(),
		"occupancy_footprint_tiles": footprint.duplicate(),
		"offset_px": offset.duplicate(),
		"anchor_px": anchor.duplicate(),
		"placement_anchor_px": anchor.duplicate(),
		"placement_anchor_policy_id": PlacementAnchorPolicy.POLICY_ID if foot_tile else "",
		"scale": [visual_scale.x, visual_scale.y],
		"instance_custom_scale": custom_scale,
		"map_collision_override": "default",
	}


func _visual_foot(instance: Dictionary, asset: Dictionary) -> Vector2:
	var tile: Array = instance.tile
	var footprint: Array = instance.footprint_tiles
	var offset: Array = instance.get("offset_px", [0, 0])
	var scale: Array = instance.scale
	var anchor: Array = instance.get("anchor_px", asset.get("anchor_px", [0, 0]))
	var source: Array = asset.get("anchor_px", [0, 0])
	var center := Coordinate.tile_to_ground_px(
		Vector2(float(tile[0]) + float(footprint[0]) * 0.5, float(tile[1]) + float(footprint[1]) * 0.5),
		DESIGN_SIZE
	) + Vector2(float(offset[0]), float(offset[1]))
	return center + Vector2(
		(float(source[0]) - float(anchor[0])) * float(scale[0]),
		(float(source[1]) - float(anchor[1])) * float(scale[1])
	)


func _pair_array(value: Vector2) -> Array:
	return [value.x, value.y]
