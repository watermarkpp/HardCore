extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var status := ContentLayers.architecture_status()
	assert(bool(status.get("valid", false)), "五层内容注册表未通过校验：%s" % [status.get("errors", [])])
	assert(ContentLayers.manifests.size() == 5, "五层清单数量不是5")
	for layer_id: String in ["vanilla_core", "expansion_layer", "rule_systems", "presentation_layer", "runtime_services"]:
		assert(not ContentLayers.manifest(layer_id).is_empty(), "缺少架构层：%s" % layer_id)
	assert(ContentLayers.vanilla_dataset("maps") == "res://assets/data/vanilla_176/maps.json", "GameData未由拆分基准层定位")
	var merged := ContentLayers.build_merged_database()
	assert(merged.get("maps", []).size() == 142 and merged.get("monsters", []).size() == 217, "Merged Game Database基准数量错误")
	assert(str(merged.maps[0].get("contentLayer", "")) == "vanilla_core" and not bool(merged.maps[0].get("editable", true)), "基准记录缺少只读层标记")
	var attack_policy := ContentLayers.policy_override("warrior_basic_attack_mobile")
	assert(int(attack_policy.get("vanillaValue", 0)) == 600 and int(attack_policy.get("overrideValue", 0)) == 850, "手机战斗调整没有保存为policyOverride")
	assert(not ContentLayers.is_expansion_enabled("later_176_content"), "后期扩展不应默认启用")
	assert(ContentLayers.set_expansion_enabled("later_176_content", true), "扩展包无法独立启用")
	assert(ContentLayers.is_expansion_enabled("later_176_content"), "扩展包启用状态未保存")
	ContentLayers.set_expansion_enabled("later_176_content", false)
	var skin := ContentLayers.active_skin()
	assert(str(skin.get("characterMappings", "")).contains("warrior_client_art"), "表现层没有独立角色映射")
	assert(not RuntimeServices.content_status().is_empty(), "运行时服务门面没有接入内容注册表")
	print("FIVE_LAYER_ARCHITECTURE_PASS：五层清单、基准数据、扩展开关、表现皮肤与运行时门面正常")
	get_tree().quit(0)
