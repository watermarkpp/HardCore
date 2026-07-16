extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(WorldContent.maps.size() == 142, "WorldContent没有接管142张地图")
	var bich := WorldContent.map_content(4)
	assert(not bich.get("spawns", []).is_empty() and not bich.get("npcs", []).is_empty() and not bich.get("portals", []).is_empty(), "刷新/NPC/地图连接未从Vanilla表装配")
	assert(not WorldContent.monster_drops("骷髅").is_empty(), "区域掉落未迁入WorldContent")
	var skill_profile := ProfessionRules.skill_profile("基本剑术")
	var stats := ProfessionRules.stats_for_level("战士", 10)
	assert(not ProfessionRules._runtime_data.is_empty() and not skill_profile.is_empty() and int(stats.get("max_hp", 0)) > 0, "职业成长仍未读取Vanilla表")
	assert(PresentationAssets.player_texture("walk") != null, "角色表现没有走Presentation Registry")
	assert(not PresentationAssets.monster_resources("稻草人").is_empty(), "怪物表现没有走Presentation Registry")
	assert(DomainRuntime.map_content(4).get("name", "") == bich.get("name", ""), "领域服务没有接管地图读取")
	var target: Array = [{"id": "same", "value": 1}]
	ContentLayers.merge_diagnostics.clear()
	ContentLayers._merge_record(target, {"id": "same", "value": 2}, "items", "explicit_override", "bad_package")
	assert(int(target[0].value) == 1 and not ContentLayers.merge_diagnostics.is_empty(), "未声明目标的扩展覆盖没有被拒绝")
	ContentLayers.merge_diagnostics.clear()
	ContentLayers._merge_record(target, {"id": "same", "overrideTargetId": "same", "value": 2}, "items", "explicit_override", "good_package")
	assert(int(target[0].value) == 2 and str(target[0].contentLayer) == "expansion_layer", "显式扩展覆盖没有记录来源层")
	var modified := ModifierEffectRuntime.apply_modifiers({"attack_max": 100.0}, [
		{"stat": "attack_max", "op": "add", "value": 15},
		{"stat": "attack_max", "op": "percent", "value": 20},
	])
	assert(is_equal_approx(float(modified.attack_max), 138.0), "Modifier通用运算顺序错误")
	var set_effects := ModifierEffectRuntime.active_set_effects({"flame": 4}, [{
		"setId": "flame", "bonuses": [
			{"pieces": 2, "effects": [{"stat": "hp_max", "op": "percent", "value": 10}]},
			{"pieces": 4, "effects": [{"trigger": "on_attack", "effect": "burn_area", "chance": 1.0}]},
		]
	}])
	assert(set_effects.size() == 2 and ModifierEffectRuntime.triggered_effects("on_attack", set_effects, {}).size() == 1, "套装或Trigger执行器未接管")
	assert(ModifierEffectRuntime.condition_matches({"key": "level", "op": "gte", "value": 20}, {"level": 22}), "Condition执行器错误")
	assert(not BossMechanics.profile("骷髅精灵").is_empty() and not BossMechanics.skill("cone_warning_slam").is_empty(), "Boss技能库没有注册")
	assert(GameModes.apply_mode("enhanced_loot") and ContentLayers.is_expansion_enabled("personal_expansion_001"), "增强模式没有启用扩展包")
	assert(GameModes.apply_mode("modded_expansion") and ContentLayers.is_expansion_enabled("user_equipment"), "魔改模式没有启用用户扩展")
	assert(GameModes.apply_mode("classic_176") and ContentLayers.enabled_package_ids().is_empty(), "经典模式没有恢复纯Vanilla")
	var player_state_source := FileAccess.get_file_as_string("res://scripts/player_state.gd")
	assert("content_packages" in player_state_source and "content_schema_version" in player_state_source and "game_mode_id" in player_state_source, "存档没有记录模式和扩展包版本")
	print("ARCHITECTURE_FINAL_PASS：五层、通用规则、Boss技能库、三模式与存档兼容全部接管")
	get_tree().quit(0)
