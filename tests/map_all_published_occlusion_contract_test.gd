extends Node

const VisualGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)

const PUBLISHED_RUNTIME_MAPS := {
	4: "bich_province",
	217: "orc_tomb_1",
	218: "orc_tomb_2",
	221: "orc_tomb_3",
	268: "wooma_forest",
	313: "wooma_temple_1",
	314: "wooma_temple_2",
	315: "wooma_temple_3",
	406: "bich_mine_1",
	408: "bich_mine_2",
	1578: "corpse_king_hall",
}


func _ready() -> void:
	_assert_synthetic_command_families()
	var total_sources := 0
	var total_actor_commands := 0
	var total_regular_sources := 0
	var covered_maps := 0
	for runtime_map_id: int in PUBLISHED_RUNTIME_MAPS:
		var map_key := str(PUBLISHED_RUNTIME_MAPS[runtime_map_id])
		var loaded := MapEditorRuntimeMapService.load_runtime(
			"res://assets/data/runtime/map_editor/%s.runtime.json" % map_key
		)
		assert(loaded.ok, "%s runtime invalid: %s" % [map_key, loaded.errors])
		var commands := VisualGeometry.sorted_draw_commands(
			loaded.runtime.get("instances", [])
		)
		var actor_by_instance := {}
		var asset_by_id := {}
		for command: Dictionary in commands:
			if str(command.get("render_domain", "")) != VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT:
				continue
			assert(
				str(command.get("occlusion_contract_id", ""))
				== VisualGeometry.OCCLUSION_SORT_CONTRACT_ID
			)
			var instance_id := str(command.instance.get("instance_id", ""))
			actor_by_instance[instance_id] = int(actor_by_instance.get(instance_id, 0)) + 1
			total_actor_commands += 1
		var map_sources := 0
		var map_regular_sources := 0
		for instance: Dictionary in loaded.runtime.get("instances", []):
			var asset_id := str(instance.get("asset_id", ""))
			if not asset_by_id.has(asset_id):
				asset_by_id[asset_id] = MapAssetCatalogService.find_asset(asset_id)
			var asset: Dictionary = asset_by_id[asset_id]
			if not VisualGeometry.instance_is_occluder(instance, asset):
				continue
			map_sources += 1
			if str(asset.get("asset_type", "")) != "wall_module":
				map_regular_sources += 1
			assert(
				actor_by_instance.has(str(instance.get("instance_id", ""))),
				"%s occluder lacks actor_y_sort command: %s" % [
					map_key, instance.get("instance_id", "")
				]
			)
		assert(map_sources > 0, "%s publishes no occlusion source" % map_key)
		total_sources += map_sources
		total_regular_sources += map_regular_sources
		covered_maps += 1
		print(
			"MAP_OCCLUSION_COVERAGE map=%d key=%s sources=%d ordinary=%d actor_commands=%d"
			% [runtime_map_id, map_key, map_sources, map_regular_sources, actor_by_instance.size()]
		)
	_assert_legacy_profile_coverage()
	assert(covered_maps == PUBLISHED_RUNTIME_MAPS.size())
	assert(total_regular_sources > 0, "published maps lack ordinary occlusion assets")
	print(
		"MAP_ALL_PUBLISHED_OCCLUSION_CONTRACT_PASS contract=%s maps=%d sources=%d ordinary=%d actor_commands=%d"
		% [
			VisualGeometry.OCCLUSION_SORT_CONTRACT_ID,
			covered_maps,
			total_sources,
			total_regular_sources,
			total_actor_commands,
		]
	)
	get_tree().quit(0)


func _assert_synthetic_command_families() -> void:
	var base := {
		"instance_id": "synthetic",
		"tile": [2, 3],
		"footprint_tiles": [4, 6],
		"occlusion": true,
	}
	var regular := VisualGeometry.instance_draw_commands(
		base,
		{"asset_type": "prop", "occlusion": true, "image": "regular.png"}
	)
	assert(regular.size() == 1)
	assert(regular[0].render_domain == VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT)
	assert(Vector2(regular[0].sort_baseline_tile).is_equal_approx(
		VisualGeometry.instance_foot_tile(base, regular[0].asset)
	), "ordinary prop did not default to its independent visual foot")
	assert(not Vector2(regular[0].sort_baseline_tile).is_equal_approx(
		Vector2(regular[0].sort_tile)
	), "ordinary prop reused the build-order far corner")
	var unsplit := VisualGeometry.instance_draw_commands(
		base,
		{"asset_type": "wall_module", "occlusion": false, "image": "wall.png"}
	)
	assert(unsplit.size() == 1)
	assert(unsplit[0].render_domain == VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT)
	var segmented_unsplit := VisualGeometry.instance_draw_commands(base, {
		"asset_type": "wall_module",
		"render_parts": [{
			"base_image": "segment.png",
			"front_image": "",
			"sort_tile_offset": [0, 0],
		}],
	})
	assert(segmented_unsplit.size() == 1)
	assert(
		segmented_unsplit[0].render_domain
		== VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT
	)
	var split := VisualGeometry.instance_draw_commands(base, {
		"asset_type": "wall_module",
		"render_parts": [{
			"base_image": "base.png",
			"front_image": "front.png",
			"sort_tile_offset": [0, 0],
		}],
	})
	assert(split.size() == 2)
	assert(split[0].render_domain == VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT)
	assert(split[1].render_domain == VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT)
	assert(not str(split[0].actor_sort_group).is_empty())
	assert(split[0].actor_sort_group == split[1].actor_sort_group)
	assert(Vector2(split[1].sort_baseline_tile).is_equal_approx(
		Vector2(split[1].sort_tile)
		+ VisualGeometry.WALL_PART_SORT_BASELINE_TILE_OFFSET
	), "split wall foreground did not sort at its occupied cell centre")
	var segmented_prop := VisualGeometry.instance_draw_commands(base, {
		"asset_type": "large_prop",
		"occlusion": true,
		"anchor_px": [96, 160],
		"occlusion_base_image": "house_base.png",
		"occlusion_segments": [
			{
				"image": "house_front_left.png",
				"sort_baseline_tile_offset": [-1.5, 0.0],
				"draw_order_index": 0,
			},
			{
				"image": "house_front_right.png",
				"sort_baseline_tile_offset": [1.5, 0.0],
				"draw_order_index": 1,
			},
		],
	})
	assert(segmented_prop.size() == 3)
	assert(segmented_prop[0].render_domain
		== VisualGeometry.RENDER_DOMAIN_STATIC_BACKGROUND)
	assert(segmented_prop[1].render_domain
		== VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT)
	assert(segmented_prop[2].render_domain
		== VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT)
	assert(not Vector2(segmented_prop[1].sort_baseline_tile).is_equal_approx(
		Vector2(segmented_prop[2].sort_baseline_tile)
	), "wide prop occlusion segments collapsed onto one baseline")


func _assert_legacy_profile_coverage() -> void:
	var configured := EnvironmentCatalog.configured_map_ids()
	assert(configured.has(4))
	for required_map_id: int in [248, 249, 268, 313, 314, 315, 338, 406, 408, 457, 458, 1506, 1507, 1578]:
		assert(configured.has(required_map_id), "profile coverage omits map %d" % required_map_id)
	for map_id: int in configured:
		var profile := EnvironmentCatalog.get_map_profile(map_id)
		assert(not profile.is_empty(), "configured profile missing for map %d" % map_id)
		var props: Array = profile.get("props", [])
		assert(not props.is_empty(), "configured profile has no occlusion props: %d" % map_id)
		for prop: Dictionary in props:
			assert(
				VisualGeometry.legacy_profile_prop_render_domain(prop)
				== VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT,
				"legacy prop must sort with actors on map %d" % map_id
			)
			assert(
				VisualGeometry.legacy_profile_prop_actor_sort_world(prop)
				== prop.get("position", Vector2.ZERO)
			)
