class_name EnvironmentCatalog
extends RefCounted

const MapCoordinateMapperScript := preload("res://scripts/map_coordinate_mapper.gd")

const THEMES := {
	"surface": {"asset_set": "bich", "ground_atlas": "res://assets/art/maps/bich/bich_ground_tiles.png", "prop_atlas": "res://assets/art/maps/bich/bich_props.png", "tile_size": Vector2i(64, 32), "prop_size": Vector2i(96, 128), "tile_count": 8, "prop_count": 4, "tint": Color.WHITE},
	"cave": {"asset_set": "orc_tomb", "ground_atlas": "res://assets/art/maps/orc_tomb/orc_tomb_ground_tiles.png", "prop_atlas": "res://assets/art/maps/orc_tomb/orc_tomb_props.png", "light_texture": "res://assets/art/maps/orc_tomb/orc_tomb_fire_glow.png", "tile_size": Vector2i(64, 32), "prop_size": Vector2i(96, 128), "tile_count": 8, "prop_count": 6, "tint": Color(1.0, 0.96, 0.90)},
	"temple": {"asset_set": "wooma_temple", "ground_atlas": "res://assets/art/maps/wooma_temple/wooma_temple_ground_tiles.png", "prop_atlas": "res://assets/art/maps/wooma_temple/wooma_temple_props.png", "light_texture": "res://assets/art/maps/wooma_temple/wooma_temple_fire_glow.png", "tile_size": Vector2i(64, 32), "prop_size": Vector2i(96, 128), "tile_count": 8, "prop_count": 8, "tint": Color(1.0, 0.86, 0.66)},
	"mine": {"asset_set": "mine", "ground_atlas": "res://assets/art/maps/mine/mine_ground_tiles.png", "prop_atlas": "res://assets/art/maps/mine/mine_props.png", "light_texture": "res://assets/art/maps/mine/mine_lamp_glow.png", "tile_size": Vector2i(64, 32), "prop_size": Vector2i(96, 128), "tile_count": 8, "prop_count": 8, "tint": Color(0.92, 0.88, 0.78)},
	"desert": {"asset_set": "bich", "ground_atlas": "res://assets/art/maps/bich/bich_ground_tiles.png", "prop_atlas": "res://assets/art/maps/bich/bich_props.png", "tile_size": Vector2i(64, 32), "prop_size": Vector2i(96, 128), "tile_count": 8, "prop_count": 4, "tint": Color(1.0, 0.82, 0.52)},
}

const BATCH_THEME_MAPS := {
	312: "temple", 313: "temple", 314: "temple", 315: "temple",
	401: "mine", 402: "mine", 403: "mine", 404: "mine", 405: "mine", 406: "mine",
	407: "mine", 408: "mine", 409: "mine", 410: "mine", 411: "mine", 412: "mine",
	478: "desert",
}

const BATCH_PROP_CANDIDATES := [
	Vector2(-720, -420), Vector2(-500, -380), Vector2(-260, -420), Vector2(0, -440), Vector2(260, -420), Vector2(500, -380), Vector2(720, -420),
	Vector2(-760, -110), Vector2(-520, -80), Vector2(520, 80), Vector2(760, 110),
	Vector2(-720, 420), Vector2(-500, 380), Vector2(-260, 420), Vector2(0, 440), Vector2(260, 420), Vector2(500, 380), Vector2(720, 420),
]

# 项目地图ID -> 经典客户端MAP直接解析结果。线路枢纽是把原MAP可行走结构压缩到当前手机战斗场地后的布局骨架。
const MINE_SOURCE_LAYOUTS := {
	401: {"source_map": "D401", "source_size": Vector2i(200, 200), "blocked_ratio": 0.7944, "source_lights": 10, "hubs": [Vector2(0, 180), Vector2(0, -80), Vector2(-300, -170), Vector2(310, -170)], "props": [0, 1, 2, 3, 5, 6, 7]},
	402: {"source_map": "D411", "source_size": Vector2i(100, 100), "blocked_ratio": 0.7898, "source_lights": 9, "hubs": [Vector2(-260, 150), Vector2(-40, -40), Vector2(280, -150)], "props": [1, 0, 3, 2, 5, 6]},
	403: {"source_map": "D413", "source_size": Vector2i(100, 100), "blocked_ratio": 0.7868, "source_lights": 3, "hubs": [Vector2(-270, 170), Vector2(80, 70), Vector2(290, -170)], "props": [0, 3, 1, 5, 7, 2]},
	404: {"source_map": "D402", "source_size": Vector2i(200, 200), "blocked_ratio": 0.8055, "source_lights": 5, "hubs": [Vector2(-300, 180), Vector2(-100, -80), Vector2(220, 110), Vector2(350, -190)], "props": [3, 0, 5, 1, 2, 6, 7]},
	405: {"source_map": "D414", "source_size": Vector2i(100, 100), "blocked_ratio": 0.9117, "source_lights": 11, "hubs": [Vector2(-280, 160), Vector2(0, 20), Vector2(300, -170)], "props": [5, 3, 0, 7, 6, 1]},
	406: {"source_map": "D403", "source_size": Vector2i(200, 200), "blocked_ratio": 0.7680, "source_lights": 8, "hubs": [Vector2(-310, 170), Vector2(-120, -120), Vector2(160, 80), Vector2(310, -170)], "props": [1, 2, 0, 3, 5, 6, 7]},
	407: {"source_map": "D412", "source_size": Vector2i(100, 100), "blocked_ratio": 0.7262, "source_lights": 4, "hubs": [Vector2(-330, 170), Vector2(0, 0), Vector2(330, -170)], "props": [4, 4, 0, 3, 6]},
	408: {"source_map": "D404", "source_size": Vector2i(200, 200), "blocked_ratio": 0.8018, "source_lights": 4, "hubs": [Vector2(-310, 180), Vector2(-130, -100), Vector2(130, 100), Vector2(310, -180)], "props": [3, 1, 0, 2, 5, 7, 6]},
	409: {"source_map": "D415", "source_size": Vector2i(100, 100), "blocked_ratio": 0.8761, "source_lights": 5, "hubs": [Vector2(-330, 170), Vector2(-50, -20), Vector2(330, -170)], "props": [4, 0, 4, 3, 6]},
	410: {"source_map": "D405", "source_size": Vector2i(200, 200), "blocked_ratio": 0.7930, "source_lights": 19, "hubs": [Vector2(-310, 180), Vector2(-130, -70), Vector2(0, 120), Vector2(150, -80), Vector2(310, -180)], "props": [2, 1, 2, 0, 3, 5, 6, 7]},
	411: {"source_map": "D416", "source_size": Vector2i(100, 100), "blocked_ratio": 0.8774, "source_lights": 5, "hubs": [Vector2(-330, 170), Vector2(60, 20), Vector2(330, -170)], "props": [4, 3, 4, 0, 6]},
	412: {"source_map": "D406", "source_size": Vector2i(200, 200), "blocked_ratio": 0.7930, "source_lights": 3, "hubs": [Vector2(-320, 180), Vector2(-170, -120), Vector2(80, -20), Vector2(300, 170)], "props": [3, 5, 0, 1, 2, 7, 6]},
	1578: {"source_map": "Q004", "source_size": Vector2i(30, 30), "blocked_ratio": 0.8000, "source_lights": 0, "hubs": [Vector2(0, 120), Vector2.ZERO], "props": [3, 5, 6]},
}

const WOOMA_TEMPLE_SOURCE_LAYOUTS := {
	312: {"source_map": "D021", "source_size": Vector2i(100, 100), "blocked_ratio": 0.6774, "source_lights": 17, "hubs": [Vector2(-300, 170), Vector2(0, 0), Vector2(300, -170), Vector2(260, 180)], "props": [4, 0, 1, 5, 6, 2]},
	313: {"source_map": "D022", "source_size": Vector2i(500, 500), "blocked_ratio": 0.8750, "source_lights": 62, "hubs": [Vector2(-330, 170), Vector2(-130, -100), Vector2(130, 100), Vector2(330, -170)], "props": [1, 0, 2, 4, 5, 6, 3]},
	314: {"source_map": "D023", "source_size": Vector2i(400, 400), "blocked_ratio": 0.7923, "source_lights": 51, "hubs": [Vector2(-330, 180), Vector2(-80, 80), Vector2(80, -80), Vector2(330, -180)], "props": [0, 1, 6, 2, 4, 5, 3]},
	315: {"source_map": "D024", "source_size": Vector2i(100, 100), "blocked_ratio": 0.6785, "source_lights": 14, "hubs": [Vector2(-330, 170), Vector2(-80, 20), Vector2(190, -20)], "props": [7, 3, 2, 0, 5, 6, 4]},
}

const WOOMA_REGION_SOURCE_LAYOUTS := {
	268: {"source_map": "1", "source_size": Vector2i(600, 600), "blocked_ratio": 0.5514, "source_lights": 1, "asset_set": "wooma_forest", "theme": "surface", "hubs": [Vector2(-300, 180), Vector2(0, 0), Vector2(300, -180), Vector2(250, 180)], "props": [0, 1, 2, 3, 4, 5, 6, 7]},
	1506: {"source_map": "E001", "source_size": Vector2i(100, 100), "blocked_ratio": 0.8127, "source_lights": 2, "asset_set": "wooma_cave", "theme": "cave", "hubs": [Vector2(-310, 180), Vector2(-90, -70), Vector2(130, 80), Vector2(310, -180)], "props": [0, 1, 2, 3, 4, 5, 6, 7]},
	1507: {"source_map": "E002", "source_size": Vector2i(100, 100), "blocked_ratio": 0.7891, "source_lights": 6, "asset_set": "wooma_cave", "theme": "cave", "hubs": [Vector2(-310, 180), Vector2(40, 40), Vector2(280, -130)], "props": [1, 0, 4, 2, 6, 3, 7, 5]},
}

const SNAKE_VALLEY_SOURCE_LAYOUTS := {
	338: {"source_map": "2", "source_size": Vector2i(600, 600), "blocked_ratio": 0.5850, "source_lights": 7, "asset_set": "snake_valley", "theme": "surface", "hubs": [Vector2(-310, 180), Vector2(-80, -60), Vector2(160, 70), Vector2(310, -180)], "props": [0, 1, 2, 3, 4, 5, 6, 7]},
	457: {"source_map": "D421", "source_size": Vector2i(400, 400), "blocked_ratio": 0.8724, "source_lights": 61, "asset_set": "snake_mine", "theme": "mine", "hubs": [Vector2(-310, 180), Vector2(-150, -100), Vector2(80, 20), Vector2(310, -180)], "props": [0, 1, 2, 3, 4, 5, 6, 7]},
	458: {"source_map": "D422", "source_size": Vector2i(400, 400), "blocked_ratio": 0.8251, "source_lights": 9, "asset_set": "snake_mine", "theme": "mine", "hubs": [Vector2(-320, 180), Vector2(-100, 80), Vector2(120, -80), Vector2(320, -180)], "props": [1, 0, 4, 2, 6, 3, 7, 5]},
}

const NATURAL_CAVE_SOURCE_LAYOUTS := {
	248: {"source_map": "D011", "source_size": Vector2i(400, 400), "blocked_ratio": 0.8026, "source_lights": 19, "source_doors": 0, "asset_set": "natural_cave", "hubs": [Vector2(-310, 180), Vector2(-120, -80), Vector2(100, 70), Vector2(310, -180)], "props": [0, 1, 2, 3, 4, 5, 6, 7]},
	249: {"source_map": "D012", "source_size": Vector2i(400, 400), "blocked_ratio": 0.7258, "source_lights": 3, "source_doors": 12, "asset_set": "natural_cave", "hubs": [Vector2(-310, 180), Vector2(-80, 40), Vector2(120, -60), Vector2(300, -170)], "props": [3, 0, 4, 1, 6, 2, 7, 5]},
}

const ORC_TOMB_SOURCE_LAYOUTS := {
	217: {"source_map": "D001", "source_size": Vector2i(400, 400), "blocked_ratio": 0.6908, "source_lights": 32, "source_doors": 0, "hubs": [Vector2(-310, 180), Vector2(-120, -70), Vector2(110, 70), Vector2(310, -180)], "props": [0, 1, 2, 3, 4, 5, 6, 7]},
	218: {"source_map": "D002", "source_size": Vector2i(400, 400), "blocked_ratio": 0.8241, "source_lights": 19, "source_doors": 12, "hubs": [Vector2(-310, 180), Vector2(-120, -70), Vector2(100, 40), Vector2(500, 220), Vector2(310, -180)], "props": [3, 0, 4, 1, 6, 2, 7, 5]},
	221: {"source_map": "D003", "source_size": Vector2i(400, 400), "blocked_ratio": 0.6788, "source_lights": 31, "source_doors": 0, "hubs": [Vector2(-310, 180), Vector2(-80, 20), Vector2(160, -60), Vector2(500, 190)], "props": [1, 4, 0, 6, 2, 5, 3, 7]},
}

const BICH_SOURCE_LAYOUT := {
	"source_map": "0", "source_size": Vector2i(700, 700), "blocked_ratio": 0.3318,
	"source_lights": 85, "source_doors": 182, "service_map_id": 0,
	"service_home_coordinate": Vector2i(289, 618),
}
const BICH_LEGACY_HOME_POSITION := Vector2(0, 80)

const BICH_TREES := [
	{"position": Vector2(-760, -80), "kind": 0}, {"position": Vector2(-710, 190), "kind": 1},
	{"position": Vector2(-470, -430), "kind": 1}, {"position": Vector2(-310, 455), "kind": 0},
	{"position": Vector2(315, 465), "kind": 0}, {"position": Vector2(485, -430), "kind": 1},
	{"position": Vector2(725, 125), "kind": 0}, {"position": Vector2(770, -105), "kind": 1},
]
const BICH_BOULDERS := [Vector2(-575, -70), Vector2(-505, 345), Vector2(555, 75), Vector2(505, 350)]
const BICH_WALL_X := [-800.0, -680.0, -560.0, -440.0, 440.0, 560.0, 680.0, 800.0]

const LEGACY_ORC_TOMB_LAYOUTS := {
	217: {
		"props": [
			{"kind": 0, "position": Vector2(-760, -430), "shape": "rect", "size": Vector2(88, 34)}, {"kind": 0, "position": Vector2(-640, -430), "shape": "rect", "size": Vector2(88, 34)}, {"kind": 0, "position": Vector2(-520, -430), "shape": "rect", "size": Vector2(88, 34)},
			{"kind": 0, "position": Vector2(520, 430), "shape": "rect", "size": Vector2(88, 34)}, {"kind": 0, "position": Vector2(640, 430), "shape": "rect", "size": Vector2(88, 34)}, {"kind": 0, "position": Vector2(760, 430), "shape": "rect", "size": Vector2(88, 34)},
			{"kind": 1, "position": Vector2(-650, -80), "shape": "circle", "radius": 22.0, "canopy": true}, {"kind": 1, "position": Vector2(650, 80), "shape": "circle", "radius": 22.0, "canopy": true},
			{"kind": 4, "position": Vector2(-120, 330), "shape": "circle", "radius": 25.0}, {"kind": 4, "position": Vector2(150, -330), "shape": "circle", "radius": 25.0},
			{"kind": 3, "position": Vector2(-500, -310)}, {"kind": 3, "position": Vector2(500, 310)}, {"kind": 5, "position": Vector2(-650, 300), "canopy": true}, {"kind": 5, "position": Vector2(650, -300), "canopy": true},
		],
		"braziers": [Vector2(-270, -40), Vector2(270, 40)],
	},
	218: {
		"props": [
			{"kind": 0, "position": Vector2(-760, -420), "shape": "rect", "size": Vector2(88, 34)}, {"kind": 0, "position": Vector2(-640, -420), "shape": "rect", "size": Vector2(88, 34)}, {"kind": 0, "position": Vector2(720, -430), "shape": "rect", "size": Vector2(88, 34)},
			{"kind": 1, "position": Vector2(330, 55), "shape": "circle", "radius": 22.0, "canopy": true}, {"kind": 1, "position": Vector2(795, 55), "shape": "circle", "radius": 22.0, "canopy": true}, {"kind": 1, "position": Vector2(330, 465), "shape": "circle", "radius": 22.0, "canopy": true}, {"kind": 1, "position": Vector2(795, 465), "shape": "circle", "radius": 22.0, "canopy": true},
			{"kind": 4, "position": Vector2(-380, 350), "shape": "circle", "radius": 25.0}, {"kind": 4, "position": Vector2(-220, -330), "shape": "circle", "radius": 25.0}, {"kind": 3, "position": Vector2(410, 80)}, {"kind": 3, "position": Vector2(725, 405)}, {"kind": 5, "position": Vector2(-650, 300), "canopy": true}, {"kind": 5, "position": Vector2(650, -300), "canopy": true},
		],
		"braziers": [Vector2(390, 155), Vector2(730, 155), Vector2(560, 430)],
	},
	221: {
		"props": [
			{"kind": 0, "position": Vector2(-760, -420), "shape": "rect", "size": Vector2(88, 34)}, {"kind": 0, "position": Vector2(-640, -420), "shape": "rect", "size": Vector2(88, 34)}, {"kind": 0, "position": Vector2(-520, -420), "shape": "rect", "size": Vector2(88, 34)},
			{"kind": 1, "position": Vector2(320, 25), "shape": "circle", "radius": 22.0, "canopy": true}, {"kind": 1, "position": Vector2(805, 25), "shape": "circle", "radius": 22.0, "canopy": true}, {"kind": 1, "position": Vector2(320, 450), "shape": "circle", "radius": 22.0, "canopy": true}, {"kind": 1, "position": Vector2(805, 450), "shape": "circle", "radius": 22.0, "canopy": true},
			{"kind": 3, "position": Vector2(400, 65)}, {"kind": 3, "position": Vector2(730, 390)}, {"kind": 4, "position": Vector2(-320, 345), "shape": "circle", "radius": 25.0}, {"kind": 4, "position": Vector2(-110, -345), "shape": "circle", "radius": 25.0}, {"kind": 5, "position": Vector2(-650, 300), "canopy": true},
		],
		"braziers": [Vector2(385, 140), Vector2(735, 140), Vector2(390, 365), Vector2(735, 365)],
	},
}

static func theme_ids() -> Array:
	return THEMES.keys()


static func get_theme(theme_id: String) -> Dictionary:
	return THEMES.get(theme_id, {}).duplicate(true)


static func get_map_profile(map_id: int) -> Dictionary:
	if map_id == 4:
		return _bich_profile()
	if ORC_TOMB_SOURCE_LAYOUTS.has(map_id):
		return _build_orc_tomb_source_profile(map_id)
	if LEGACY_ORC_TOMB_LAYOUTS.has(map_id):
		var profile: Dictionary = LEGACY_ORC_TOMB_LAYOUTS[map_id].duplicate(true)
		profile.merge(_dungeon_ground_profile(map_id), true)
		profile["expected_collisions"] = {217: 10, 218: 9, 221: 9}[map_id]
		profile["expected_lights"] = {217: 2, 218: 3, 221: 4}[map_id]
		return profile
	if NATURAL_CAVE_SOURCE_LAYOUTS.has(map_id):
		return _build_natural_cave_profile(map_id)
	if MINE_SOURCE_LAYOUTS.has(map_id):
		return _build_mine_profile(map_id)
	if WOOMA_TEMPLE_SOURCE_LAYOUTS.has(map_id):
		return _build_wooma_temple_profile(map_id)
	if WOOMA_REGION_SOURCE_LAYOUTS.has(map_id):
		return _build_wooma_region_profile(map_id)
	if SNAKE_VALLEY_SOURCE_LAYOUTS.has(map_id):
		return _build_snake_valley_profile(map_id)
	if BATCH_THEME_MAPS.has(map_id):
		return _build_batch_profile(map_id, str(BATCH_THEME_MAPS[map_id]))
	return {}


static func configured_map_ids() -> Array:
	# Keep coverage derived from every published profile family. The former
	# hand-written subset silently omitted Wooma Forest/Caves and Snake maps,
	# allowing shared rendering regressions to escape the environment suite.
	var configured := {4: true}
	for family: Dictionary in [
		BATCH_THEME_MAPS,
		MINE_SOURCE_LAYOUTS,
		WOOMA_TEMPLE_SOURCE_LAYOUTS,
		WOOMA_REGION_SOURCE_LAYOUTS,
		SNAKE_VALLEY_SOURCE_LAYOUTS,
		NATURAL_CAVE_SOURCE_LAYOUTS,
		ORC_TOMB_SOURCE_LAYOUTS,
	]:
		for map_id: Variant in family.keys():
			configured[int(map_id)] = true
	var result := configured.keys()
	result.sort()
	return result


static func coverage_report() -> Dictionary:
	var by_theme := {}
	for theme_id: String in theme_ids():
		by_theme[theme_id] = 0
	for map_id: int in configured_map_ids():
		var theme_id := str(get_map_profile(map_id).get("theme", ""))
		by_theme[theme_id] = int(by_theme.get(theme_id, 0)) + 1
	var resource_users := {}
	for theme_id: String in theme_ids():
		var theme := get_theme(theme_id)
		for key in ["ground_atlas", "prop_atlas", "light_texture"]:
			if not theme.has(key):
				continue
			var path := str(theme[key])
			if not resource_users.has(path):
				resource_users[path] = []
			(resource_users[path] as Array).append(theme_id)
	return {"configured_maps": configured_map_ids().size(), "by_theme": by_theme, "resource_users": resource_users}


static func expected_runtime_nodes(profile: Dictionary) -> int:
	var count := 0
	for prop: Dictionary in profile.get("props", []):
		# One complete prop is one actor-domain Y-sort unit. Canopies are no
		# longer duplicated as an always-on-top fixed-z sprite.
		count += 1
		if str(prop.get("shape", "")) in ["circle", "rect"]:
			count += 1
	count += profile.get("braziers", []).size() * 3
	return count


static func _dungeon_ground_profile(map_id: int) -> Dictionary:
	var result := {"map_id": map_id, "theme": "cave", "ground_style": "dungeon", "seed": map_id, "routes": []}
	match map_id:
		217:
			result.routes = [[Vector2(-650, 300), Vector2(650, -300), 66.0]]
		218:
			result.routes = [[Vector2(-650, 300), Vector2(560, 260), 62.0], [Vector2(560, 260), Vector2(650, -300), 62.0]]
			result["arena"] = {"center": Vector2(560, 260), "inner": 205.0, "outer": 250.0}
		221:
			result.routes = [[Vector2(-650, 300), Vector2(560, 230), 62.0]]
			result["arena"] = {"center": Vector2(560, 230), "inner": 205.0, "outer": 250.0}
	return result


static func _bich_profile() -> Dictionary:
	var props: Array[Dictionary] = []
	for tree: Dictionary in BICH_TREES:
		var tree_source := _legacy_bich_source_coordinate(tree.position)
		props.append({"kind": int(tree.kind), "source_coordinate": tree_source, "position": _bich_world(tree_source), "canopy": true, "shape": "circle", "radius": 27.0})
	for legacy_position: Vector2 in BICH_BOULDERS:
		var boulder_source := _legacy_bich_source_coordinate(legacy_position)
		props.append({"kind": 2, "source_coordinate": boulder_source, "position": _bich_world(boulder_source), "shape": "circle", "radius": 25.0})
	for wall_x: float in BICH_WALL_X:
		var wall_source := _legacy_bich_source_coordinate(Vector2(wall_x, -535.0))
		props.append({"kind": 3, "source_coordinate": wall_source, "position": _bich_world(wall_source), "shape": "rect", "size": Vector2(88, 34), "collision_offset": Vector2(0, -8)})
	var content := RegionContent.get_map_content(4)
	var route_positions: Array = []
	for portal: Dictionary in content.get("portals", []):
		route_positions.append(portal.get("position", Vector2.ZERO))
	var home_position := _bich_world(BICH_SOURCE_LAYOUT.service_home_coordinate)
	return {
		"map_id": 4, "theme": "surface", "ground_style": "bich", "props": props,
		"routes": route_positions, "route_origin": home_position,
		"expected_collisions": 24, "expected_lights": 0,
		"source_map_code": BICH_SOURCE_LAYOUT.source_map,
		"source_size": BICH_SOURCE_LAYOUT.source_size,
		"collision_mask_path": "res://assets/art/maps/bich/source_masks/0_walkability.png",
		"collision_mask_confidence": "A",
		"coordinate_projection": "isometric_64x32_full_size",
		"world_bounds": MapCoordinateMapperScript.world_bounds(BICH_SOURCE_LAYOUT.source_size),
		"world_corners": MapCoordinateMapperScript.world_corners(BICH_SOURCE_LAYOUT.source_size),
		"blocked_ratio": BICH_SOURCE_LAYOUT.blocked_ratio,
		"source_lights": BICH_SOURCE_LAYOUT.source_lights,
		"source_doors": BICH_SOURCE_LAYOUT.source_doors,
		"service_map_id": BICH_SOURCE_LAYOUT.service_map_id,
		"service_home_coordinate": BICH_SOURCE_LAYOUT.service_home_coordinate,
		"runtime_home_position": home_position,
	}


static func _legacy_bich_source_coordinate(legacy_position: Vector2) -> Vector2i:
	var source_delta := MapCoordinateMapperScript.world_delta_to_source(legacy_position - BICH_LEGACY_HOME_POSITION)
	return Vector2i(Vector2(BICH_SOURCE_LAYOUT.service_home_coordinate) + source_delta.round())


static func _bich_world(source_coordinate: Vector2) -> Vector2:
	return MapCoordinateMapperScript.source_to_world(source_coordinate, BICH_SOURCE_LAYOUT.source_size)


static func _build_batch_profile(map_id: int, theme_id: String) -> Dictionary:
	var content := RegionContent.get_map_content(map_id)
	var portals: Array = content.get("portals", [])
	var routes: Array = []
	for portal: Variant in portals:
		if portal is Dictionary:
			routes.append([Vector2.ZERO, portal.get("position", Vector2.ZERO), 62.0 if theme_id != "desert" else 44.0])
	var props: Array[Dictionary] = []
	var desired_count := 7 if theme_id == "mine" else (8 if theme_id == "temple" else 6)
	var prop_kinds := [0, 1, 4, 3, 1, 4] if theme_id != "desert" else [0, 2, 1, 2, 0, 1]
	var start := posmod(map_id * 7, BATCH_PROP_CANDIDATES.size())
	for offset in range(BATCH_PROP_CANDIDATES.size()):
		var position: Vector2 = BATCH_PROP_CANDIDATES[(start + offset) % BATCH_PROP_CANDIDATES.size()]
		if not _is_safe_prop_position(position, portals, routes):
			continue
		var kind := int(prop_kinds[props.size() % prop_kinds.size()])
		var prop := {"kind": kind, "position": position, "canopy": kind in [0, 1]}
		if kind in [0, 1, 4] or theme_id == "desert":
			prop.merge({"shape": "circle", "radius": 24.0})
		else:
			prop.merge({"shape": "rect", "size": Vector2(82, 30), "collision_offset": Vector2(0, -8)})
		props.append(prop)
		if props.size() >= desired_count:
			break
	var light_count := 2 if theme_id == "mine" else (3 if theme_id == "temple" else 0)
	var light_candidates := [Vector2(-220, 90), Vector2(220, -90), Vector2(0, 250), Vector2(0, -250)]
	var braziers: Array[Vector2] = []
	for position: Vector2 in light_candidates:
		if braziers.size() >= light_count:
			break
		var portal_safe := true
		for portal: Variant in portals:
			if portal is Dictionary and position.distance_to(portal.get("position", Vector2.ZERO)) < 120.0:
				portal_safe = false
		if portal_safe:
			braziers.append(position)
	return {"map_id": map_id, "theme": theme_id, "ground_style": "desert" if theme_id == "desert" else "dungeon", "seed": map_id, "routes": routes, "props": props, "braziers": braziers, "expected_collisions": props.size(), "expected_lights": braziers.size(), "generated": true}


static func _build_mine_profile(map_id: int) -> Dictionary:
	var source: Dictionary = MINE_SOURCE_LAYOUTS[map_id]
	var content := RegionContent.get_map_content(map_id)
	var portals: Array = content.get("portals", [])
	var spawns: Array = content.get("spawns", [])
	var bosses: Array = content.get("bosses", [])
	var hubs: Array = source.get("hubs", [])
	var routes: Array = []
	for index in range(portals.size()):
		var portal: Dictionary = portals[index]
		var hub: Vector2 = hubs[index % hubs.size()] if not hubs.is_empty() else Vector2.ZERO
		routes.append([portal.get("position", Vector2.ZERO), hub, 58.0])
	for index in range(maxi(0, hubs.size() - 1)):
		routes.append([hubs[index], hubs[index + 1], 54.0])

	var kinds: Array = source.get("props", [0, 1, 2, 3, 5, 6, 7])
	var desired_count := clampi(7 + int(round((float(source.get("blocked_ratio", 0.8)) - 0.75) * 12.0)), 7, 10)
	if map_id in [407, 409, 411]:
		desired_count = 7
	elif map_id == 1578:
		desired_count = 3
	var props: Array[Dictionary] = []
	var start := posmod(map_id * 11, BATCH_PROP_CANDIDATES.size())
	for offset in range(BATCH_PROP_CANDIDATES.size()):
		var position: Vector2 = BATCH_PROP_CANDIDATES[(start + offset) % BATCH_PROP_CANDIDATES.size()]
		if not _is_safe_prop_position(position, portals, routes):
			continue
		var actor_safe := true
		for actor: Variant in spawns + bosses:
			if actor is Dictionary and position.distance_to(actor.get("position", Vector2.ZERO)) < (170.0 if actor in bosses else 80.0):
				actor_safe = false
		if not actor_safe:
			continue
		var kind := int(kinds[props.size() % kinds.size()])
		var prop := {"kind": kind, "position": position, "canopy": kind in [0, 3, 7]}
		if kind in [2, 5, 6]:
			prop.merge({"shape": "circle", "radius": 24.0})
		else:
			prop.merge({"shape": "rect", "size": Vector2(76, 28), "collision_offset": Vector2(0, -8)})
		props.append(prop)
		if props.size() >= desired_count:
			break

	var desired_lights := 0 if map_id == 1578 else clampi(int(round(float(source.get("source_lights", 0)) / 5.0)), 1, 4)
	var braziers: Array[Vector2] = []
	for candidate: Vector2 in [Vector2(-240, 100), Vector2(240, -100), Vector2(0, 260), Vector2(0, -260)]:
		if braziers.size() >= desired_lights:
			break
		var safe := true
		for portal: Variant in portals:
			if portal is Dictionary and candidate.distance_to(portal.get("position", Vector2.ZERO)) < 120.0:
				safe = false
		if safe:
			braziers.append(candidate)
	var profile := {
		"map_id": map_id, "theme": "mine", "ground_style": "mine", "seed": map_id,
		"source_map_code": source.get("source_map", ""), "source_size": source.get("source_size", Vector2i.ZERO),
		"collision_mask_path": "res://assets/art/maps/mine/source_masks/%d_%s.png" % [map_id, source.get("source_map", "")],
		"collision_mask_confidence": "A",
		"coordinate_projection": "isometric_64x32_full_size",
		"world_bounds": MapCoordinateMapperScript.world_bounds(source.get("source_size", Vector2i.ZERO)),
		"world_corners": MapCoordinateMapperScript.world_corners(source.get("source_size", Vector2i.ZERO)),
		"source_blocked_ratio": source.get("blocked_ratio", 0.0), "source_light_cells": source.get("source_lights", 0),
		"source_evidence": "客户端MAP直接解析+服务端地图结构定义",
		"layout_hubs": hubs.duplicate(true), "routes": routes, "props": props, "braziers": braziers,
		"expected_collisions": props.size() + 4, "expected_lights": braziers.size(), "generated": false,
	}
	if map_id == 1578 and not bosses.is_empty():
		profile["arena"] = {"center": bosses[0].get("position", Vector2.ZERO).lerp(bosses[-1].get("position", Vector2.ZERO), 0.5), "inner": 250.0, "outer": 340.0}
	return profile


static func _build_natural_cave_profile(map_id: int) -> Dictionary:
	var source: Dictionary = NATURAL_CAVE_SOURCE_LAYOUTS[map_id]
	var content := RegionContent.get_map_content(map_id)
	var portals: Array = content.get("portals", [])
	var spawns: Array = content.get("spawns", [])
	var hubs: Array = source.get("hubs", [])
	var routes: Array = []
	for index in range(portals.size()):
		routes.append([portals[index].get("position", Vector2.ZERO), hubs[index % hubs.size()], 62.0])
	for index in range(maxi(0, hubs.size() - 1)):
		routes.append([hubs[index], hubs[index + 1], 56.0])
	var kinds: Array = source.get("props", [])
	var props: Array[Dictionary] = []
	var desired_count := 10 if map_id == 248 else 9
	var start := posmod(map_id * 23, BATCH_PROP_CANDIDATES.size())
	for offset in range(BATCH_PROP_CANDIDATES.size()):
		var position: Vector2 = BATCH_PROP_CANDIDATES[(start + offset) % BATCH_PROP_CANDIDATES.size()]
		if not _is_safe_prop_position(position, portals, routes):
			continue
		var spawn_safe := true
		for spawn: Variant in spawns:
			if spawn is Dictionary and position.distance_to(spawn.get("position", Vector2.ZERO)) < 90.0:
				spawn_safe = false
		if not spawn_safe:
			continue
		var kind := int(kinds[props.size() % kinds.size()])
		var prop := {"kind": kind, "position": position, "canopy": kind in [0, 1, 3, 4, 5, 6]}
		if kind in [2, 5, 7]:
			prop.merge({"shape": "circle", "radius": 24.0})
		else:
			prop.merge({"shape": "rect", "size": Vector2(76, 30), "collision_offset": Vector2(0, -8)})
		props.append(prop)
		if props.size() >= desired_count:
			break
	var braziers: Array[Vector2] = []
	var desired_lights := 3 if map_id == 248 else 1
	for candidate: Vector2 in [Vector2(-240, 100), Vector2(240, -100), Vector2(0, 250), Vector2(0, -250)]:
		if braziers.size() >= desired_lights:
			break
		var safe := true
		for portal: Variant in portals:
			if portal is Dictionary and candidate.distance_to(portal.get("position", Vector2.ZERO)) < 120.0:
				safe = false
		if safe:
			braziers.append(candidate)
	return {
		"map_id": map_id, "theme": "cave", "asset_set": "natural_cave",
		"ground_atlas_override": "res://assets/art/maps/natural_cave/natural_cave_ground_tiles.png",
		"prop_atlas_override": "res://assets/art/maps/natural_cave/natural_cave_props.png",
		"light_texture_override": "res://assets/art/maps/natural_cave/natural_cave_glow.png",
		"tile_count_override": 8, "prop_count_override": 8, "ground_style": "natural_cave", "seed": map_id,
		"source_map_code": source.get("source_map", ""), "source_size": source.get("source_size", Vector2i.ZERO),
		"collision_mask_path": "res://assets/art/maps/natural_cave/source_masks/%d_%s_walkability.png" % [map_id, source.get("source_map", "")],
		"collision_mask_confidence": "A",
		"coordinate_projection": "isometric_64x32_full_size",
		"world_bounds": MapCoordinateMapperScript.world_bounds(source.get("source_size", Vector2i.ZERO)),
		"world_corners": MapCoordinateMapperScript.world_corners(source.get("source_size", Vector2i.ZERO)),
		"source_blocked_ratio": source.get("blocked_ratio", 0.0), "source_light_cells": source.get("source_lights", 0),
		"source_door_cells": source.get("source_doors", 0), "source_evidence": "客户端D011/D012 MAP直接解析",
		"layout_hubs": hubs.duplicate(true), "routes": routes, "props": props, "braziers": braziers,
		"expected_collisions": props.size() + 4, "expected_lights": braziers.size(), "generated": false,
	}


static func _build_orc_tomb_source_profile(map_id: int) -> Dictionary:
	var source: Dictionary = ORC_TOMB_SOURCE_LAYOUTS[map_id]
	var content := RegionContent.get_map_content(map_id)
	var portals: Array = content.get("portals", [])
	var spawns: Array = content.get("spawns", [])
	var bosses: Array = content.get("bosses", [])
	var hubs: Array = source.get("hubs", [])
	var routes: Array = []
	for index in range(portals.size()):
		routes.append([portals[index].get("position", Vector2.ZERO), hubs[index % hubs.size()], 62.0])
	for index in range(maxi(0, hubs.size() - 1)):
		routes.append([hubs[index], hubs[index + 1], 58.0])
	var kinds: Array = source.get("props", [])
	var props: Array[Dictionary] = []
	var desired_count := {217: 10, 218: 9, 221: 9}[map_id] as int
	var start := posmod(map_id * 29, BATCH_PROP_CANDIDATES.size())
	for offset in range(BATCH_PROP_CANDIDATES.size()):
		var position: Vector2 = BATCH_PROP_CANDIDATES[(start + offset) % BATCH_PROP_CANDIDATES.size()]
		if not _is_safe_prop_position(position, portals, routes):
			continue
		var actor_safe := true
		for spawn: Variant in spawns:
			if spawn is Dictionary and position.distance_to(spawn.get("position", Vector2.ZERO)) < 90.0:
				actor_safe = false
		for boss: Variant in bosses:
			if boss is Dictionary and position.distance_to(boss.get("position", Vector2.ZERO)) < 190.0:
				actor_safe = false
		if not actor_safe:
			continue
		var kind := int(kinds[props.size() % kinds.size()])
		var prop := {"kind": kind, "position": position, "canopy": kind in [0, 1, 3, 4, 5, 6]}
		if kind in [2, 5, 7]:
			prop.merge({"shape": "circle", "radius": 24.0})
		else:
			prop.merge({"shape": "rect", "size": Vector2(76, 30), "collision_offset": Vector2(0, -8)})
		props.append(prop)
		if props.size() >= desired_count:
			break
	var braziers: Array[Vector2] = []
	var desired_lights := {217: 3, 218: 2, 221: 3}[map_id] as int
	for candidate: Vector2 in [Vector2(-240, 100), Vector2(240, -100), Vector2(0, 250), Vector2(0, -250)]:
		if braziers.size() >= desired_lights:
			break
		var safe := true
		for portal: Variant in portals:
			if portal is Dictionary and candidate.distance_to(portal.get("position", Vector2.ZERO)) < 120.0:
				safe = false
		for boss: Variant in bosses:
			if boss is Dictionary and candidate.distance_to(boss.get("position", Vector2.ZERO)) < 150.0:
				safe = false
		if safe:
			braziers.append(candidate)
	var profile := {
		"map_id": map_id, "theme": "cave", "asset_set": "orc_tomb",
		"ground_atlas_override": "res://assets/art/maps/orc_tomb/orc_tomb_ground_tiles.png",
		"prop_atlas_override": "res://assets/art/maps/orc_tomb/orc_tomb_props.png",
		"light_texture_override": "res://assets/art/maps/orc_tomb/orc_tomb_fire_glow.png",
		"tile_count_override": 8, "prop_count_override": 8, "ground_style": "orc_tomb_client", "seed": map_id,
		"source_map_code": source.get("source_map", ""), "source_size": source.get("source_size", Vector2i.ZERO),
		"collision_mask_path": "res://assets/art/maps/orc_tomb/source_masks/%d_%s_walkability.png" % [map_id, source.get("source_map", "")],
		"collision_mask_confidence": "A",
		"coordinate_projection": "isometric_64x32_full_size",
		"world_bounds": MapCoordinateMapperScript.world_bounds(source.get("source_size", Vector2i.ZERO)),
		"world_corners": MapCoordinateMapperScript.world_corners(source.get("source_size", Vector2i.ZERO)),
		"source_blocked_ratio": source.get("blocked_ratio", 0.0), "source_light_cells": source.get("source_lights", 0),
		"source_door_cells": source.get("source_doors", 0), "source_evidence": "客户端D001/D002/D003 MAP直接解析",
		"layout_hubs": hubs.duplicate(true), "routes": routes, "props": props, "braziers": braziers,
		"expected_collisions": props.size() + 4, "expected_lights": braziers.size(), "generated": false,
	}
	if map_id in [218, 221] and not bosses.is_empty():
		profile["arena"] = {"center": bosses[0].get("position", Vector2.ZERO), "inner": 205.0, "outer": 250.0}
	return profile


static func _build_wooma_temple_profile(map_id: int) -> Dictionary:
	var source: Dictionary = WOOMA_TEMPLE_SOURCE_LAYOUTS[map_id]
	var content := RegionContent.get_map_content(map_id)
	var portals: Array = content.get("portals", [])
	var hubs: Array = source.get("hubs", [])
	var routes: Array = []
	for index in range(portals.size()):
		var portal: Dictionary = portals[index]
		routes.append([portal.get("position", Vector2.ZERO), hubs[index % hubs.size()], 58.0])
	for index in range(maxi(0, hubs.size() - 1)):
		routes.append([hubs[index], hubs[index + 1], 56.0])

	var kinds: Array = source.get("props", [0, 1, 2, 3, 4, 5, 6])
	var props: Array[Dictionary] = []
	var desired_count := 10 if map_id in [313, 314] else 8
	var start := posmod(map_id * 13, BATCH_PROP_CANDIDATES.size())
	for offset in range(BATCH_PROP_CANDIDATES.size()):
		var position: Vector2 = BATCH_PROP_CANDIDATES[(start + offset) % BATCH_PROP_CANDIDATES.size()]
		if not _is_safe_prop_position(position, portals, routes):
			continue
		var kind := int(kinds[props.size() % kinds.size()])
		var prop := {"kind": kind, "position": position, "canopy": kind in [0, 1, 2, 4, 6]}
		if kind in [3, 5, 7]:
			prop.merge({"shape": "circle", "radius": 25.0})
		else:
			prop.merge({"shape": "rect", "size": Vector2(78, 30), "collision_offset": Vector2(0, -8)})
		props.append(prop)
		if props.size() >= desired_count:
			break

	var desired_lights := clampi(int(round(float(source.get("source_lights", 0)) / 15.0)), 2, 4)
	var braziers: Array[Vector2] = []
	for candidate: Vector2 in [Vector2(-240, 100), Vector2(240, -100), Vector2(0, 260), Vector2(0, -260)]:
		if braziers.size() >= desired_lights:
			break
		var safe := true
		for portal: Variant in portals:
			if portal is Dictionary and candidate.distance_to(portal.get("position", Vector2.ZERO)) < 120.0:
				safe = false
		if safe:
			braziers.append(candidate)
	var profile := {
		"map_id": map_id, "theme": "temple", "ground_style": "temple", "seed": map_id,
		"source_map_code": source.get("source_map", ""), "source_size": source.get("source_size", Vector2i.ZERO),
		"source_blocked_ratio": source.get("blocked_ratio", 0.0), "source_light_cells": source.get("source_lights", 0),
		"source_evidence": "客户端MAP直接解析+服务端地图结构定义",
		"layout_hubs": hubs.duplicate(true), "routes": routes, "props": props, "braziers": braziers,
		"expected_collisions": props.size(), "expected_lights": braziers.size(), "generated": false,
	}
	if map_id == 315:
		profile["arena"] = {"center": Vector2(30, 15), "inner": 230.0, "outer": 280.0}
	return profile


static func _build_wooma_region_profile(map_id: int) -> Dictionary:
	var source: Dictionary = WOOMA_REGION_SOURCE_LAYOUTS[map_id]
	var content := RegionContent.get_map_content(map_id)
	var portals: Array = content.get("portals", [])
	var hubs: Array = source.get("hubs", [])
	var routes: Array = []
	for index in range(portals.size()):
		var portal: Dictionary = portals[index]
		routes.append([portal.get("position", Vector2.ZERO), hubs[index % hubs.size()], 58.0])
	for index in range(maxi(0, hubs.size() - 1)):
		routes.append([hubs[index], hubs[index + 1], 54.0])
	var kinds: Array = source.get("props", [])
	var props: Array[Dictionary] = []
	var desired_count := 10 if map_id == 268 else 9
	var start := posmod(map_id * 17, BATCH_PROP_CANDIDATES.size())
	for offset in range(BATCH_PROP_CANDIDATES.size()):
		var position: Vector2 = BATCH_PROP_CANDIDATES[(start + offset) % BATCH_PROP_CANDIDATES.size()]
		if not _is_safe_prop_position(position, portals, routes):
			continue
		var kind := int(kinds[props.size() % kinds.size()])
		var prop := {"kind": kind, "position": position, "canopy": kind in ([0, 4, 5, 6] if map_id == 268 else [0, 1, 4, 6, 7])}
		if kind in [3, 5, 6]:
			prop.merge({"shape": "circle", "radius": 25.0})
		else:
			prop.merge({"shape": "rect", "size": Vector2(78, 30), "collision_offset": Vector2(0, -8)})
		props.append(prop)
		if props.size() >= desired_count:
			break
	var braziers: Array[Vector2] = []
	if map_id != 268:
		var desired_lights := 2 if map_id == 1506 else 3
		for candidate: Vector2 in [Vector2(-240, 100), Vector2(240, -100), Vector2(0, 250)]:
			if braziers.size() >= desired_lights:
				break
			braziers.append(candidate)
	var asset_set := str(source.get("asset_set", ""))
	return {
		"map_id": map_id, "theme": source.get("theme", "cave"), "asset_set": asset_set,
		"ground_atlas_override": "res://assets/art/maps/wooma_region/%s_ground_tiles.png" % asset_set,
		"prop_atlas_override": "res://assets/art/maps/wooma_region/%s_props.png" % asset_set,
		"light_texture_override": "res://assets/art/maps/wooma_region/wooma_cave_glow.png" if map_id != 268 else "",
		"tile_count_override": 8, "prop_count_override": 8,
		"ground_style": "forest" if map_id == 268 else "wooma_cave", "seed": map_id,
		"source_map_code": source.get("source_map", ""), "source_size": source.get("source_size", Vector2i.ZERO),
		"source_blocked_ratio": source.get("blocked_ratio", 0.0), "source_light_cells": source.get("source_lights", 0),
		"source_evidence": "客户端MAP直接解析+服务端地图结构定义",
		"layout_hubs": hubs.duplicate(true), "routes": routes, "props": props, "braziers": braziers,
		"expected_collisions": props.size(), "expected_lights": braziers.size(), "generated": false,
	}


static func _build_snake_valley_profile(map_id: int) -> Dictionary:
	var source: Dictionary = SNAKE_VALLEY_SOURCE_LAYOUTS[map_id]
	var portals: Array = RegionContent.get_map_content(map_id).get("portals", [])
	var hubs: Array = source.get("hubs", [])
	var routes: Array = []
	for index in range(portals.size()):
		var portal: Dictionary = portals[index]
		routes.append([portal.get("position", Vector2.ZERO), hubs[index % hubs.size()], 58.0])
	for index in range(maxi(0, hubs.size() - 1)):
		routes.append([hubs[index], hubs[index + 1], 54.0])
	var kinds: Array = source.get("props", [])
	var props: Array[Dictionary] = []
	var desired_count := 10 if map_id == 338 else 9
	var start := posmod(map_id * 19, BATCH_PROP_CANDIDATES.size())
	for offset in range(BATCH_PROP_CANDIDATES.size()):
		var position: Vector2 = BATCH_PROP_CANDIDATES[(start + offset) % BATCH_PROP_CANDIDATES.size()]
		if not _is_safe_prop_position(position, portals, routes):
			continue
		var kind := int(kinds[props.size() % kinds.size()])
		var prop := {"kind": kind, "position": position, "canopy": kind in ([0, 1, 3, 4] if map_id == 338 else [0, 1, 2, 5, 7])}
		if kind in [2, 4, 5]:
			prop.merge({"shape": "circle", "radius": 25.0})
		else:
			prop.merge({"shape": "rect", "size": Vector2(78, 30), "collision_offset": Vector2(0, -8)})
		props.append(prop)
		if props.size() >= desired_count:
			break
	var braziers: Array[Vector2] = []
	if map_id != 338:
		var desired_lights := 4 if map_id == 457 else 2
		for candidate: Vector2 in [Vector2(-240, 100), Vector2(240, -100), Vector2(0, 250), Vector2(0, -250)]:
			if braziers.size() >= desired_lights:
				break
			braziers.append(candidate)
	var asset_set := str(source.get("asset_set", ""))
	return {
		"map_id": map_id, "theme": source.get("theme", "surface"), "asset_set": asset_set,
		"ground_atlas_override": "res://assets/art/maps/snake_valley/%s_ground_tiles.png" % asset_set,
		"prop_atlas_override": "res://assets/art/maps/snake_valley/%s_props.png" % asset_set,
		"light_texture_override": "res://assets/art/maps/snake_valley/snake_mine_glow.png" if map_id != 338 else "",
		"tile_count_override": 8, "prop_count_override": 8,
		"ground_style": "snake_valley" if map_id == 338 else "snake_mine", "seed": map_id,
		"source_map_code": source.get("source_map", ""), "source_size": source.get("source_size", Vector2i.ZERO),
		"source_blocked_ratio": source.get("blocked_ratio", 0.0), "source_light_cells": source.get("source_lights", 0),
		"source_evidence": "客户端MAP直接解析+服务端地图结构定义",
		"layout_hubs": hubs.duplicate(true), "routes": routes, "props": props, "braziers": braziers,
		"expected_collisions": props.size(), "expected_lights": braziers.size(), "generated": false,
	}


static func _is_safe_prop_position(position: Vector2, portals: Array, routes: Array) -> bool:
	if position.length() < 170.0:
		return false
	for portal: Variant in portals:
		if portal is Dictionary and position.distance_to(portal.get("position", Vector2.ZERO)) < 145.0:
			return false
	for route: Array in routes:
		if _distance_to_segment(position, route[0], route[1]) < float(route[2]) + 38.0:
			return false
	return true


static func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	if segment.length_squared() < 0.01:
		return point.distance_to(start)
	var ratio := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * ratio)


static func validate_profile(profile: Dictionary, portals: Array = []) -> PackedStringArray:
	var errors := PackedStringArray()
	var map_id := int(profile.get("map_id", -1))
	var theme_id := str(profile.get("theme", ""))
	if not THEMES.has(theme_id):
		errors.append("地图%d主题不存在：%s" % [map_id, theme_id])
		return errors
	var theme: Dictionary = THEMES[theme_id]
	for key in ["ground_atlas", "prop_atlas", "tile_size", "prop_size", "tile_count", "prop_count"]:
		if not theme.has(key):
			errors.append("主题%s缺少%s" % [theme_id, key])
	for override_key in ["ground_atlas_override", "prop_atlas_override", "light_texture_override"]:
		var override_path := str(profile.get(override_key, ""))
		if not override_path.is_empty() and not ResourceLoader.exists(override_path):
			errors.append("地图%d覆盖资源不存在：%s" % [map_id, override_path])
	var prop_limit := int(profile.get("prop_count_override", theme.get("prop_count", 0)))
	for prop: Dictionary in profile.get("props", []):
		var kind := int(prop.get("kind", -1))
		if kind < 0 or kind >= prop_limit:
			errors.append("地图%d物件索引越界：%d" % [map_id, kind])
		if not prop.get("position", null) is Vector2:
			errors.append("地图%d物件位置无效" % map_id)
		if str(prop.get("shape", "")) not in ["", "circle", "rect"]:
			errors.append("地图%d碰撞类型无效" % map_id)
	for portal: Variant in portals:
		if portal is Dictionary and _point_blocked(portal.get("position", Vector2.ZERO), profile):
			errors.append("地图%d门点被环境碰撞占用：%s" % [map_id, portal.get("position", Vector2.ZERO)])
	return errors


static func _point_blocked(point: Vector2, profile: Dictionary) -> bool:
	for prop: Dictionary in profile.get("props", []):
		var position: Vector2 = prop.get("position", Vector2.ZERO) + prop.get("collision_offset", Vector2.ZERO)
		if str(prop.get("shape", "")) == "circle" and point.distance_to(position) <= float(prop.get("radius", 0.0)):
			return true
		if str(prop.get("shape", "")) == "rect":
			var size: Vector2 = prop.get("size", Vector2.ZERO)
			if Rect2(position - size * 0.5, size).has_point(point):
				return true
	return false
