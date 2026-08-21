extends Node


const GENERATED_POLICIES := [
	"terrain_stamp_generated",
	"wall_cells_generated",
]


func _ready() -> void:
	MapAssetCatalogService.invalidate_cache()
	var asset := _find_automatic_collision_asset()
	assert(not asset.is_empty())
	var document := MapEditorTypes.new_map(
		"manual_collision_only_test",
		990221,
		"Manual Collision Only",
		Vector2i(256, 256)
	)
	var manual := MapEditorCollisionService.add_manual_shape(
		document,
		"rect",
		{"rect": [2, 2, 1, 1]}
	)
	assert(bool(manual.get("ok", false)))
	document.layers["collision_erase"] = [
		{"tile": [3, 3], "source": "test"},
	]
	var manual_before := JSON.stringify(document.layers.collision)
	var erase_before := JSON.stringify(document.layers.collision_erase)

	var placed := MapEditorInstanceService.create_instance(
		document,
		str(asset.asset_id),
		"obstacle",
		Vector2i(20, 20),
		"object_base"
	)
	assert(bool(placed.get("ok", false)), str(placed.get("errors", [])))
	_assert_manual_only_instance(placed.instance)
	_assert_geometry_matches_asset(placed.instance, asset)
	assert(str(placed.instance.placement_rule) == "non_overlapping")
	assert(JSON.stringify(document.layers.collision) == manual_before)
	assert(JSON.stringify(document.layers.collision_erase) == erase_before)

	var overlap := MapEditorInstanceService.create_instance(
		document,
		str(asset.asset_id),
		"obstacle",
		Vector2i(20, 20),
		"object_base"
	)
	assert(not bool(overlap.get("ok", false)))
	assert(
		(overlap.get("errors", []) as Array).has(
			"blocked_footprint_overlap:%s" % str(placed.instance.instance_id)
		)
	)

	for role: String in ["building", "interactable"]:
		var tile := Vector2i(80, 20) if role == "building" else Vector2i(140, 20)
		var result := MapEditorInstanceService.create_instance(
			document,
			str(asset.asset_id),
			role,
			tile,
			"object_base"
		)
		assert(bool(result.get("ok", false)), "%s:%s" % [role, result.get("errors", [])])
		_assert_manual_only_instance(result.instance)
		_assert_geometry_matches_asset(result.instance, asset)
		assert(str(result.instance.object_role) == role)

	var decoration_overlap := MapEditorInstanceService.create_instance(
		document,
		str(asset.asset_id),
		"decoration",
		Vector2i(20, 20),
		"object_front"
	)
	assert(
		bool(decoration_overlap.get("ok", false)),
		str(decoration_overlap.get("errors", []))
	)
	_assert_manual_only_instance(decoration_overlap.instance)
	assert(str(decoration_overlap.instance.placement_rule) == "inside_map")

	var refresh := MapEditorInstanceProfileService.refresh_from_asset(
		placed.instance,
		asset,
		Vector2i(256, 256)
	)
	assert(bool(refresh.get("ok", false)), str(refresh.get("errors", [])))
	_assert_manual_only_instance(placed.instance)

	var existing_default: Dictionary = placed.instance.duplicate(true)
	existing_default["map_collision_override"] = "default"
	existing_default["collision_policy"] = "none"
	existing_default["collision_profile_id"] = "none_visual"
	existing_default["collision_footprint_tiles"] = [0, 0]
	existing_default["collision_cells"] = []
	existing_default["navigation_policy"] = "ignore"
	var legacy_refresh := MapEditorInstanceProfileService.refresh_from_asset(
		existing_default,
		asset,
		Vector2i(256, 256)
	)
	assert(bool(legacy_refresh.get("ok", false)), str(legacy_refresh.get("errors", [])))
	assert(
		str(existing_default.get("collision_policy", ""))
		== str(asset.get("collision_policy", ""))
	)

	var source: Dictionary = existing_default.duplicate(true)
	source["tile"] = [160, 120]
	source["tile_anchor"] = [160, 120]
	source["object_role"] = "obstacle"
	source["placement_rule"] = "non_overlapping"
	var source_before := JSON.stringify(source)
	var duplicated := MapEditorInstanceService.duplicate_instance_snapshot(
		document,
		source,
		Vector2i(190, 120)
	)
	assert(bool(duplicated.get("ok", false)), str(duplicated.get("errors", [])))
	assert(JSON.stringify(source) == source_before)
	_assert_manual_only_instance(duplicated.instance)

	for policy: String in GENERATED_POLICIES:
		var generated_instance := {
			"collision_policy": policy,
			"collision_profile_id": "generated",
			"collision_footprint_tiles": [2, 1],
			"collision_cells": [[0, 0]],
			"navigation_policy": "block_player_and_monster",
		}
		var generated_asset := {"collision_policy": policy}
		var generated_before := JSON.stringify(generated_instance)
		assert(
			not MapEditorInstanceService._apply_new_instance_collision_policy(
				generated_instance,
				generated_asset
			)
		)
		assert(JSON.stringify(generated_instance) == generated_before)

	var generated_runtime_instance := {
		"instance_id": "generated_runtime",
		"tile": [220, 220],
		"footprint_tiles": [1, 1],
		"collision_policy": "terrain_stamp_generated",
		"collision_footprint_tiles": [1, 1],
		"collision_cells": [],
	}
	document.layers.object_base.append(generated_runtime_instance)
	var walkability := MapEditorCollisionService.build_walkability(document)
	assert(walkability.blocked_tiles.has("2,2"))
	assert(walkability.blocked_tiles.has("220,220"))
	assert(not walkability.blocked_tiles.has("20,20"))
	assert(JSON.stringify(document.layers.collision) == manual_before)
	assert(JSON.stringify(document.layers.collision_erase) == erase_before)

	print(
		"MSE_NEW_INSTANCE_MANUAL_COLLISION_POLICY_PASS "
		+ "normal_roles=4 generated=2 manual_preserved=true occupancy_overlap=true"
	)
	get_tree().quit(0)


func _find_automatic_collision_asset() -> Dictionary:
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		var policy := str(asset.get("collision_policy", "none"))
		if (
			bool(asset.get("placeable", false))
			and str(asset.get("asset_type", "")) != "ground_brush"
			and policy != "none"
			and policy not in GENERATED_POLICIES
			and (asset.get("footprint_tiles", []) as Array).size() == 2
		):
			return asset
	return {}


func _assert_manual_only_instance(instance: Dictionary) -> void:
	assert(str(instance.get("collision_policy", "")) == "none")
	assert(str(instance.get("collision_profile_id", "")) == "none_visual")
	assert(instance.get("collision_footprint_tiles", []) == [0, 0])
	assert((instance.get("collision_cells", []) as Array).is_empty())
	assert(str(instance.get("navigation_policy", "")) == "ignore")
	assert(bool(instance.get("manual_collision_expected", false)))
	assert(str(instance.get("map_collision_override", "")) == "disabled")
	assert(str(instance.get("collision_authority", "")) == "manual_by_user")
	assert(
		str(instance.get("collision_policy_id", ""))
		== MapEditorInstanceService.NEW_INSTANCE_COLLISION_POLICY_ID
	)


func _assert_geometry_matches_asset(
	instance: Dictionary,
	asset: Dictionary
) -> void:
	var footprint: Array = asset.get("footprint_tiles", [1, 1])
	assert(instance.get("footprint_tiles", []) == footprint)
	assert(
		instance.get("visual_footprint_tiles", [])
		== asset.get("visual_footprint_tiles", footprint)
	)
	assert(
		instance.get("occupancy_footprint_tiles", [])
		== asset.get("occupancy_footprint_tiles", footprint)
	)
	assert(
		instance.get("base_footprint_tiles", [])
		== asset.get("base_footprint_tiles", footprint)
	)
