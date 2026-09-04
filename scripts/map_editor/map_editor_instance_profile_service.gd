class_name MapEditorInstanceProfileService
extends RefCounted

const PlacementAnchorPolicy := preload("res://scripts/map_assets/map_asset_placement_anchor_policy.gd")
const MapEditorCoordinate := preload("res://scripts/map_editor/map_editor_coordinate.gd")
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
) -> Dictionary:
	if instance.is_empty() or asset.is_empty():
		return {"ok": false, "errors": ["instance_or_asset_empty"]}
	var before := _geometry_snapshot(instance, asset, design_size)
	if not bool(before.get("ok", false)):
		return before
	# Legacy custom instances written with the source anchor and a zero offset
	# are the pre-profile form.  Keep that established repair contract: the
	# policy refresh fixes the derived anchor while the authored offset remains
	# untouched.  Other custom instances use the visual-foot invariant below.
	var legacy_custom_anchor_repair: bool = (
		bool(instance.get("instance_custom_scale", false))
		and before.anchor == before.source_anchor
		and before.offset == Vector2.ZERO
	)
	var candidate: Dictionary = instance.duplicate(true)
	if bool(instance.get("instance_custom_scale", false)):
		# A custom instance owns its scale, footprint and manual offset.  Only
		# the placement anchor derived from the current source asset is refreshed.
		if PlacementAnchorPolicy.applies_to(asset):
			PlacementAnchorPolicy.refresh_custom_instance(candidate, asset)
	else:
		for key: String in GEOMETRY_PROFILE_FIELDS:
			if asset.has(key):
				candidate[key] = _copy_value(asset[key])
		var approved := _positive_number(
			asset.get("approved_scale", 1.0), "asset.approved_scale"
		)
		if not bool(approved.get("ok", false)):
			return approved
		candidate["anchor_px"] = _copy_value(
			asset.get("placement_anchor_px", asset.get("anchor_px", [0, 0]))
		)
		candidate["scale"] = [float(approved.value), float(approved.value)]
	var adaptive_auto_offset := _same_pair(
		candidate.get("offset_px", [0, 0]),
		candidate.get("adaptive_corner_offset_px", [])
	)
	apply_adaptive_corner_offset(candidate, asset, design_size)
	var after := _geometry_snapshot(candidate, asset, design_size)
	if not bool(after.get("ok", false)):
		return after
	if bool(before.get("foot_tile_policy", false)) \
			and bool(after.get("foot_tile_policy", false)):
		# footprint_bottom_vertex_v1 retains the existing resize invariant.
		var old_tile: Vector2i = before.tile
		var old_footprint: Vector2i = before.footprint
		var new_footprint: Vector2i = after.footprint
		var new_tile := old_tile - (new_footprint - old_footprint)
		candidate["tile"] = [new_tile.x, new_tile.y]
		candidate["tile_anchor"] = [new_tile.x, new_tile.y]
		after = _geometry_snapshot(candidate, asset, design_size)
		if not bool(after.get("ok", false)):
			return after
	# One residual correction covers anchor, scale, footprint and any approved
	# tile move. It also preserves deliberate offsets instead of replacing them.
	if not legacy_custom_anchor_repair:
		var residual: Vector2 = before.visual_foot - after.visual_foot
		var next_offset: Vector2 = after.offset + residual
		if not is_finite(next_offset.x) or not is_finite(next_offset.y):
			return {"ok": false, "errors": ["visual_offset_non_finite"]}
		candidate["offset_px"] = [next_offset.x, next_offset.y]
		if adaptive_auto_offset:
			# Keep the auto-offset marker coherent with the deterministic correction.
			# A deliberate manual offset never enters this branch.
			candidate["adaptive_corner_offset_px"] = [next_offset.x, next_offset.y]
	var final_tile: Vector2i = after.tile
	candidate["tile_anchor"] = [final_tile.x, final_tile.y]
	if not has_map_collision_override(instance):
		for key: String in COLLISION_PROFILE_FIELDS:
			if asset.has(key):
				candidate[key] = _copy_value(asset[key])
		candidate["map_collision_override"] = str(
			asset.get("map_collision_override", "default")
		)
	var changed := candidate != instance
	instance.clear()
	for key: Variant in candidate:
		instance[key] = candidate[key]
	return {"ok": true, "errors": [], "changed": changed, "instance": instance}


static func _geometry_snapshot(
	instance: Dictionary,
	asset: Dictionary,
	design_size: Vector2i
) -> Dictionary:
	var tile_result := _pair(instance.get("tile", null), "instance.tile", false, true)
	if not bool(tile_result.get("ok", false)):
		return tile_result
	var footprint_result := _pair(
		instance.get("footprint_tiles", null), "instance.footprint_tiles", true, true
	)
	if not bool(footprint_result.get("ok", false)):
		return footprint_result
	var scale_result := _pair(
		instance.get("scale", null), "instance.scale", true, false
	)
	if not bool(scale_result.get("ok", false)):
		return scale_result
	var source_result := _pair(
		asset.get("anchor_px", [0, 0]), "asset.anchor_px", false, false
	)
	if not bool(source_result.get("ok", false)):
		return source_result
	var anchor_value: Variant
	if instance.has("anchor_px"):
		anchor_value = instance.get("anchor_px")
	elif instance.has("placement_anchor_px"):
		anchor_value = instance.get("placement_anchor_px")
	else:
		anchor_value = asset.get("anchor_px", [0, 0])
	var anchor_result := _pair(anchor_value, "instance.anchor_px", false, false)
	if not bool(anchor_result.get("ok", false)):
		return anchor_result
	var offset_result := _pair(
		instance.get("offset_px", [0, 0]), "instance.offset_px", false, false
	)
	if not bool(offset_result.get("ok", false)):
		return offset_result
	var tile: Vector2i = tile_result.value
	var footprint: Vector2i = footprint_result.value
	if design_size.x > 0 and design_size.y > 0:
		if tile.x < 0 or tile.y < 0 \
				or tile.x + footprint.x > design_size.x \
				or tile.y + footprint.y > design_size.y:
			return {"ok": false, "errors": ["instance_geometry_out_of_bounds"]}
	var scale: Vector2 = scale_result.value
	var source_anchor: Vector2 = source_result.value
	var anchor: Vector2 = anchor_result.value
	var offset: Vector2 = offset_result.value
	var center := MapEditorCoordinate.tile_to_ground_px(
		Vector2(tile) + Vector2(footprint) * 0.5,
		design_size
	) + offset
	return {
		"ok": true,
		"tile": tile,
		"footprint": footprint,
		"scale": scale,
		"offset": offset,
		"anchor": anchor,
		"source_anchor": source_anchor,
		"visual_foot": center + (source_anchor - anchor) * scale,
		"foot_tile_policy": str(instance.get("placement_anchor_policy_id", "")) \
			== PlacementAnchorPolicy.POLICY_ID,
	}


static func _pair(
	value: Variant,
	label: String,
	positive: bool,
	integer: bool
) -> Dictionary:
	if not value is Array or (value as Array).size() != 2:
		return {"ok": false, "errors": [label + "_invalid_pair"]}
	var values: Array = value
	var result := Vector2.ZERO
	for index in 2:
		var raw: Variant = values[index]
		if typeof(raw) not in [TYPE_INT, TYPE_FLOAT]:
			return {"ok": false, "errors": [label + "_invalid_number"]}
		var number := float(raw)
		if not is_finite(number) or (integer and not is_equal_approx(number, roundf(number))):
			return {"ok": false, "errors": [label + "_invalid_number"]}
		if positive and number <= 0.0:
			return {"ok": false, "errors": [label + "_not_positive"]}
		result[index] = number
	if integer:
		return {"ok": true, "value": Vector2i(roundi(result.x), roundi(result.y))}
	return {"ok": true, "value": result}


static func _positive_number(value: Variant, label: String) -> Dictionary:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return {"ok": false, "errors": [label + "_invalid_number"]}
	var number := float(value)
	if not is_finite(number) or number <= 0.0:
		return {"ok": false, "errors": [label + "_not_positive"]}
	return {"ok": true, "value": number}


static func _same_pair(left: Variant, right: Variant) -> bool:
	if not left is Array or not right is Array:
		return false
	if (left as Array).size() != 2 or (right as Array).size() != 2:
		return false
	return is_equal_approx(float((left as Array)[0]), float((right as Array)[0])) \
		and is_equal_approx(float((left as Array)[1]), float((right as Array)[1]))


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
