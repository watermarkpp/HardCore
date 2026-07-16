class_name EnvironmentValidator
extends RefCounted

const Catalog := preload("res://scripts/environment_catalog.gd")


static func validate_all() -> PackedStringArray:
	var errors := PackedStringArray()
	if Catalog.theme_ids().size() != 5:
		errors.append("环境主题数量不是5")
	for theme_id: String in Catalog.theme_ids():
		_validate_theme(theme_id, Catalog.get_theme(theme_id), errors)
	_validate_resource_reuse(errors)
	_validate_coverage(errors)
	for map_id: int in Catalog.configured_map_ids():
		var profile := Catalog.get_map_profile(map_id)
		var content := RegionContent.get_map_content(map_id)
		_validate_profile_resource_overrides(profile, errors)
		errors.append_array(Catalog.validate_profile(profile, content.get("portals", [])))
		_validate_counts(profile, errors)
		_validate_portal_routes(profile, content.get("portals", []), errors)
		var node_budget := Catalog.expected_runtime_nodes(profile)
		if node_budget <= 0 or node_budget > 48:
			errors.append("地图%d环境节点预算异常：%d" % [map_id, node_budget])
	return errors


static func _validate_profile_resource_overrides(profile: Dictionary, errors: PackedStringArray) -> void:
	var map_id := int(profile.get("map_id", -1))
	for key in ["ground_atlas_override", "prop_atlas_override"]:
		if not profile.has(key):
			continue
		var path := str(profile.get(key, ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			errors.append("地图%d覆盖资源不存在：%s" % [map_id, path])
	var light_path := str(profile.get("light_texture_override", ""))
	if not light_path.is_empty() and not ResourceLoader.exists(light_path):
		errors.append("地图%d覆盖灯光资源不存在：%s" % [map_id, light_path])


static func _validate_coverage(errors: PackedStringArray) -> void:
	var report := Catalog.coverage_report()
	if int(report.get("configured_maps", 0)) < 23:
		errors.append("环境模板覆盖地图不足23张")
	for theme_id: String in Catalog.theme_ids():
		if int(report.get("by_theme", {}).get(theme_id, 0)) <= 0:
			errors.append("主题%s没有运行地图样板" % theme_id)


static func _validate_resource_reuse(errors: PackedStringArray) -> void:
	var specifications := {}
	for theme_id: String in Catalog.theme_ids():
		var theme := Catalog.get_theme(theme_id)
		for pair in [["ground_atlas", "tile_size", "tile_count"], ["prop_atlas", "prop_size", "prop_count"]]:
			var path := str(theme.get(pair[0], ""))
			var signature := "%s:%s" % [theme.get(pair[1], Vector2i.ZERO), theme.get(pair[2], 0)]
			if specifications.has(path) and str(specifications[path]) != signature:
				errors.append("复用资源规格冲突：%s" % path)
			specifications[path] = signature


static func _validate_theme(theme_id: String, theme: Dictionary, errors: PackedStringArray) -> void:
	for asset_key in ["ground_atlas", "prop_atlas"]:
		var path := str(theme.get(asset_key, ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			errors.append("主题%s资源不存在：%s" % [theme_id, path])
	var ground := load(str(theme.get("ground_atlas", ""))) as Texture2D
	var props := load(str(theme.get("prop_atlas", ""))) as Texture2D
	var tile_size: Vector2i = theme.get("tile_size", Vector2i.ZERO)
	var prop_size: Vector2i = theme.get("prop_size", Vector2i.ZERO)
	var expected_ground_size := Vector2(tile_size.x * int(theme.get("tile_count", 0)), tile_size.y)
	var expected_prop_size := Vector2(prop_size.x * int(theme.get("prop_count", 0)), prop_size.y)
	if ground != null and ground.get_size() != expected_ground_size:
		errors.append("主题%s地砖图集尺寸不符" % theme_id)
	if props != null and props.get_size() != expected_prop_size:
		errors.append("主题%s物件图集尺寸不符" % theme_id)
	if theme.has("light_texture") and not ResourceLoader.exists(str(theme.light_texture)):
		errors.append("主题%s灯光资源不存在" % theme_id)


static func _validate_counts(profile: Dictionary, errors: PackedStringArray) -> void:
	var collision_count := 0
	for prop: Dictionary in profile.get("props", []):
		if str(prop.get("shape", "")) in ["circle", "rect"]:
			collision_count += 1
	if collision_count != int(profile.get("expected_collisions", -1)):
		errors.append("地图%d碰撞数量配置不符" % int(profile.get("map_id", -1)))
	if profile.get("braziers", []).size() != int(profile.get("expected_lights", -1)):
		errors.append("地图%d灯光数量配置不符" % int(profile.get("map_id", -1)))


static func _validate_portal_routes(profile: Dictionary, portals: Array, errors: PackedStringArray) -> void:
	var endpoints: Array[Vector2] = []
	for route: Variant in profile.get("routes", []):
		if route is Vector2:
			endpoints.append(route)
		elif route is Array and route.size() >= 2:
			endpoints.append(route[0])
			endpoints.append(route[1])
	for portal: Variant in portals:
		if not portal is Dictionary:
			continue
		var position: Vector2 = portal.get("position", Vector2.ZERO)
		var connected := false
		for endpoint: Vector2 in endpoints:
			if endpoint.distance_to(position) <= 80.0:
				connected = true
				break
		if not connected:
			errors.append("地图%d门点缺少地表路线：%s" % [int(profile.get("map_id", -1)), position])
