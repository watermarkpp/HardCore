class_name MapAssetPlacementAnchorPolicy
extends RefCounted

const POLICY_ID := "footprint_bottom_vertex_v1"
const HALF_TILE_W := 32.0
const HALF_TILE_H := 16.0


static func applies_to(asset: Dictionary) -> bool:
	return (
		str(asset.get("anchor_mode", "")) == "foot_tile"
		and str(asset.get("asset_type", "")) != "wall_module"
		and str(asset.get("object_class", "")) != "wall"
	)


static func apply_to_asset(asset: Dictionary) -> Dictionary:
	if not applies_to(asset):
		return asset
	var result := asset.duplicate(true)
	var footprint: Array = result.get("footprint_tiles", [1, 1])
	var approved_scale := maxf(0.0001, float(result.get("approved_scale", 1.0)))
	var placement_anchor := placement_anchor_px(
		result,
		footprint,
		Vector2(approved_scale, approved_scale)
	)
	result["placement_anchor_px"] = [placement_anchor.x, placement_anchor.y]
	result["placement_anchor_policy_id"] = POLICY_ID
	return result


static func refresh_custom_instance(instance: Dictionary, asset: Dictionary) -> void:
	if not applies_to(asset):
		return
	var footprint: Array = instance.get(
		"footprint_tiles",
		asset.get("footprint_tiles", [1, 1])
	)
	var scale_raw: Array = instance.get(
		"scale",
		[
			float(asset.get("approved_scale", 1.0)),
			float(asset.get("approved_scale", 1.0)),
		]
	)
	var placement_anchor := placement_anchor_px(
		asset,
		footprint,
		Vector2(float(scale_raw[0]), float(scale_raw[1]))
	)
	instance["anchor_px"] = [placement_anchor.x, placement_anchor.y]
	instance["placement_anchor_px"] = [placement_anchor.x, placement_anchor.y]
	instance["placement_anchor_policy_id"] = POLICY_ID


static func placement_anchor_px(
	asset: Dictionary,
	footprint: Array,
	visual_scale: Vector2
) -> Vector2:
	var source_anchor: Array = asset.get(
		"anchor_px",
		asset.get("placement_anchor_px", [0, 0])
	)
	var width := maxf(1.0, float(footprint[0]))
	var height := maxf(1.0, float(footprint[1]))
	var center_to_bottom := Vector2(
		(width - height) * HALF_TILE_W * 0.5,
		(width + height) * HALF_TILE_H * 0.5
	)
	return Vector2(
		float(source_anchor[0]) - center_to_bottom.x / maxf(0.0001, absf(visual_scale.x)),
		float(source_anchor[1]) - center_to_bottom.y / maxf(0.0001, absf(visual_scale.y))
	)
