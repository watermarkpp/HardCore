class_name MapAssetManualCollisionPolicy
extends RefCounted

const POLICY_ID := "cave_tomb_manual_collision_v1"
const VISUAL_ONLY_WALL_FAMILIES := [
	"orc_tomb_rough_stone_u0",
	"cave_granite_u0",
]


static func is_visual_only_wall(asset: Dictionary) -> bool:
	return str(asset.get("asset_type", "")) == "wall_module" \
		and str(asset.get("wall_family_id", "")) in VISUAL_ONLY_WALL_FAMILIES


static func apply_to_asset(asset: Dictionary) -> Dictionary:
	if not is_visual_only_wall(asset):
		return asset
	var result := asset.duplicate(true)
	if not result.has("authored_collision_policy"):
		result["authored_collision_policy"] = str(result.get("collision_policy", "none"))
	result["collision_policy"] = "none"
	result["collision_profile_id"] = "none_visual"
	result["collision_footprint_tiles"] = [0, 0]
	result["collision_cells"] = []
	result["placement_clearance_cells"] = []
	result["navigation_policy"] = "ignore"
	result["manual_collision_expected"] = true
	result["map_collision_override"] = "default"
	result["collision_authority"] = "manual_by_user"
	result["collision_policy_id"] = POLICY_ID
	return result


static func apply_to_instance(instance: Dictionary, asset: Dictionary) -> bool:
	if not is_visual_only_wall(asset):
		return false
	var changed: bool = str(instance.get("collision_policy", "none")) != "none" \
		or not (instance.get("collision_cells", []) as Array).is_empty() \
		or instance.get("collision_footprint_tiles", [0, 0]) != [0, 0] \
		or str(instance.get("navigation_policy", "ignore")) != "ignore" \
		or str(instance.get("map_collision_override", "disabled")) != "disabled"
	instance["collision_policy"] = "none"
	instance["collision_profile_id"] = "none_visual"
	instance["collision_footprint_tiles"] = [0, 0]
	instance["collision_cells"] = []
	instance["navigation_policy"] = "ignore"
	instance["manual_collision_expected"] = true
	instance["map_collision_override"] = "disabled"
	instance["collision_authority"] = "manual_by_user"
	instance["collision_policy_id"] = POLICY_ID
	return changed
