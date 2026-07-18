class_name MapEditorInstanceProfileService
extends RefCounted

const GEOMETRY_PROFILE_FIELDS := [
	"footprint_tiles",
	"occupancy_footprint_tiles",
	"placement_anchor_px",
	"selection_shape",
]
const COLLISION_PROFILE_FIELDS := [
	"collision_footprint_tiles",
	"collision_profile_id",
	"collision_policy",
	"collision_cells",
	"navigation_policy",
	"manual_collision_expected",
	"collision_authority",
	"collision_policy_id",
]
const CATALOG_CONTROLLED_OVERRIDES := ["", "default", "asset"]


static func refresh_from_asset(instance: Dictionary, asset: Dictionary) -> void:
	if bool(instance.get("instance_custom_scale", false)):
		return
	for key: String in GEOMETRY_PROFILE_FIELDS:
		if asset.has(key):
			instance[key] = _copy_value(asset[key])
	instance["anchor_px"] = _copy_value(
		asset.get("placement_anchor_px", asset.get("anchor_px", instance.get("anchor_px", [0, 0])))
	)
	instance["scale"] = [
		float(asset.get("approved_scale", 1.0)),
		float(asset.get("approved_scale", 1.0)),
	]
	if has_map_collision_override(instance):
		return
	for key: String in COLLISION_PROFILE_FIELDS:
		if asset.has(key):
			instance[key] = _copy_value(asset[key])
	instance["map_collision_override"] = str(asset.get("map_collision_override", "default"))


static func has_map_collision_override(instance: Dictionary) -> bool:
	return str(instance.get("map_collision_override", "default")) not in CATALOG_CONTROLLED_OVERRIDES


static func _copy_value(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value
