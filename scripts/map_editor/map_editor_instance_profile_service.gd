class_name MapEditorInstanceProfileService
extends RefCounted

const PlacementAnchorPolicy := preload("res://scripts/map_assets/map_asset_placement_anchor_policy.gd")
const GEOMETRY_PROFILE_FIELDS := [
	"footprint_tiles",
	"occupancy_footprint_tiles",
	"placement_anchor_px",
	"placement_anchor_policy_id",
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


static func refresh_from_asset(
	instance: Dictionary,
	asset: Dictionary,
	design_size := Vector2i.ZERO
) -> void:
	if bool(instance.get("instance_custom_scale", false)):
		# Preserve the user's resized footprint, scale and offset, but migrate
		# the derived placement anchor so legacy instances use the same
		# bottom-of-footprint alignment as newly placed props.
		PlacementAnchorPolicy.refresh_custom_instance(instance, asset)
		apply_adaptive_corner_offset(instance, asset, design_size)
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
	apply_adaptive_corner_offset(instance, asset, design_size)
	if has_map_collision_override(instance):
		return
	for key: String in COLLISION_PROFILE_FIELDS:
		if asset.has(key):
			instance[key] = _copy_value(asset[key])
	instance["map_collision_override"] = str(asset.get("map_collision_override", "default"))


static func apply_adaptive_corner_offset(
	instance: Dictionary,
	asset: Dictionary,
	design_size: Vector2i,
	force := false
) -> void:
	if design_size.x <= 0 or design_size.y <= 0:
		return
	var raw_profile: Variant = asset.get("adaptive_corner_offsets_px", {})
	if not raw_profile is Dictionary:
		return
	var profile: Dictionary = raw_profile
	if profile.is_empty():
		return
	var tile_raw: Array = instance.get("tile", [0, 0])
	var tile := Vector2i(int(tile_raw[0]), int(tile_raw[1]))
	# Directional corner placement is authoritative at the visible tile.
	# Copies created by older editor builds could retain the source anchor,
	# which made later keyboard movement or saving jump by one cell.
	instance["tile_anchor"] = [tile.x, tile.y]
	var zone := adaptive_corner_zone(tile, design_size)
	var raw_asset_profile: Variant = asset.get(
		"adaptive_corner_asset_ids",
		{}
	)
	if raw_asset_profile is Dictionary:
		var directional_asset_id := str(
			(raw_asset_profile as Dictionary).get(zone, "")
		)
		if not directional_asset_id.is_empty():
			instance["asset_id"] = directional_asset_id
	var raw_sort_profile: Variant = asset.get(
		"adaptive_corner_sort_tile_offsets",
		{}
	)
	if raw_sort_profile is Dictionary:
		var sort_raw: Variant = (raw_sort_profile as Dictionary).get(zone, [])
		if sort_raw is Array and (sort_raw as Array).size() == 2:
			instance["adaptive_corner_sort_tile_offset"] = [
				int((sort_raw as Array)[0]),
				int((sort_raw as Array)[1]),
			]
	var next_raw: Variant = profile.get(zone, [])
	if not next_raw is Array or (next_raw as Array).size() != 2:
		return
	var next_offset := [
		int((next_raw as Array)[0]),
		int((next_raw as Array)[1]),
	]
	var current_raw: Array = instance.get("offset_px", [0, 0])
	var current_offset := [
		int(current_raw[0]) if current_raw.size() >= 1 else 0,
		int(current_raw[1]) if current_raw.size() >= 2 else 0,
	]
	var prior_raw: Array = instance.get("adaptive_corner_offset_px", [])
	var follows_auto := (
		prior_raw.size() == 2
		and current_offset == [int(prior_raw[0]), int(prior_raw[1])]
	)
	var legacy_default := (
		not instance.has("adaptive_corner_offset_px")
		and current_offset == [0, 0]
	)
	if not force and not follows_auto and not legacy_default:
		# A non-automatic offset is a deliberate map edit and remains the
		# authority when the instance is moved or the catalog is reloaded.
		return
	instance["offset_px"] = next_offset.duplicate()
	instance["adaptive_corner_offset_px"] = next_offset.duplicate()
	instance["adaptive_corner_zone"] = zone
	instance["adaptive_corner_contract_id"] = str(
		asset.get("adaptive_corner_contract_id", "")
	)


static func adaptive_corner_zone(tile: Vector2i, design_size: Vector2i) -> String:
	var maximum := Vector2i(
		maxi(0, design_size.x - 1),
		maxi(0, design_size.y - 1)
	)
	var candidates := [
		{"zone": "min_min", "distance": tile.x + tile.y},
		{
			"zone": "max_min",
			"distance": absi(maximum.x - tile.x) + tile.y,
		},
		{
			"zone": "max_max",
			"distance": (
				absi(maximum.x - tile.x)
				+ absi(maximum.y - tile.y)
			),
		},
		{
			"zone": "min_max",
			"distance": tile.x + absi(maximum.y - tile.y),
		},
	]
	var best: Dictionary = candidates[0]
	for candidate: Dictionary in candidates:
		if int(candidate.distance) < int(best.distance):
			best = candidate
	return str(best.zone)


static func has_map_collision_override(instance: Dictionary) -> bool:
	return str(instance.get("map_collision_override", "default")) not in CATALOG_CONTROLLED_OVERRIDES


static func _copy_value(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value
