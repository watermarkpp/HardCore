extends Node

const CATALOG_PATH := "res://outputs/resource_catalog/complete_client_frame_catalog/manifest.json"
const HELMET_SOURCE_PATH := "res://assets/art/characters/warrior/wear/helmet/black_iron_helmet.source.json"


func _ready() -> void:
	var catalog := _read_json(CATALOG_PATH)
	assert(int(catalog.get("libraryCount", 0)) == 122, "完整客户端资源库数量不完整")
	assert(int(catalog.get("indexedFramesScanned", 0)) == 962251, "完整客户端索引帧没有全部扫描")
	assert(int(catalog.get("validFrames", 0)) == 962250, "完整客户端有效帧统计变化")
	assert(int(catalog.get("decodedHeadCandidates", 0)) == 332460, "头部几何候选没有全部解码")
	assert(str(catalog.get("database", "")).ends_with("frame_catalog.sqlite"), "逐帧SQLite目录缺失")

	var helmet := _read_json(HELMET_SOURCE_PATH)
	assert(str(helmet.get("classification", "")).begins_with("project-generated"), "生成头盔没有明确与原客户端资源隔离")
	assert(int(helmet.get("referenceIconImage", -1)) == 344, "黑铁头盔装备栏身份没有绑定已核实的StateItem #344")
	assert(bool(helmet.get("generation", {}).get("aiGenerated", false)), "用户确认的生成式后向参考没有如实记录")
	assert(helmet.get("generation", {}).get("aiPixelsLimitedTo", []) == ["N", "NE", "E", "SE", "S", "SW", "W", "NW"], "运行图集没有完整使用新生成的八方向外观")
	assert(not bool(helmet.get("generation", {}).get("oldDerivedStateItemWorldPixelsUsed", true)), "运行图集仍混入旧StateItem派生外观")
	var direction_references: Dictionary = helmet.get("approvedDirectionReferences", {})
	assert(str(direction_references.get("rearNNeNw", "")).ends_with("rear_n_ne_nw_transparent.png"), "黑铁头后向参考没有写入来源记录")
	assert(str(direction_references.get("canonicalManifest", "")).ends_with("canonical_directions/manifest.json"), "新生成八方向母版没有写入来源记录")
	assert(is_equal_approx(float(helmet.get("generation", {}).get("runtimeEnvelopeScale", 0.0)), 0.7225), "黑铁头没有在0.85基础上再次缩小15%")
	assert(int(helmet.get("completeClientCoverage", {}).get("indexedFrames", 0)) == 962251, "头盔来源记录没有绑定完整客户端扫描")
	for action_name in ["idle", "walk", "attack", "hit", "death"]:
		var action: Dictionary = helmet.get("actions", {}).get(action_name, {})
		assert(int(action.get("directions", 0)) == 8, "%s头盔不是八方向" % action_name)
		assert((action.get("directionSignatures", []) as Array).size() == 8, "%s头盔方向签名缺失" % action_name)
	assert(ArtSpec.PLAYER_HEALTH_BAR_OFFSET == Vector2(-8.0, -95.0), "人物血条没有对齐经典战士可见中心")
	print("COMPLETE_CLIENT_RESOURCE_CATALOG_PASS")
	get_tree().quit(0)


func _read_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "文件不存在：%s" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary, "JSON格式错误：%s" % path)
	return parsed
