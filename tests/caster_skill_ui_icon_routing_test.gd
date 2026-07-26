extends Node

const Catalog := preload("res://scripts/hud_skill_icon_catalog.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_assert_warrior_catalog_is_locked()
	var caster_ids := CasterSkillVisualRegistry.active_skill_ids()
	assert(caster_ids.size() == 26, "法师/道士主资料主动技能图标覆盖必须为26项")
	for skill_id: String in caster_ids:
		_assert_caster_catalog_entry(skill_id)
	_assert_passive_keeps_compatibility_fallback()

	var hud := GameHUD.new()
	add_child(hud)
	await get_tree().process_frame
	for skill_id: String in caster_ids:
		_assert_hud_uses_caster_icon(hud, skill_id)
	for skill_name: String in ["攻杀剑术", "刺杀剑术", "半月弯刀", "烈火剑法"]:
		_assert_hud_keeps_warrior_icon(hud, skill_name)
	for profession_id: String in ["wizard", "taoist"]:
		await _assert_skill_panel_uses_caster_icons(profession_id)

	print("CASTER_SKILL_UI_ICON_ROUTING_PASS: 26个法师/道士主动技能使用主资料动画选帧图标；战士4图标保持不变；被动精神力战法不伪造施法图标")
	get_tree().quit(0)


func _assert_warrior_catalog_is_locked() -> void:
	var expected := {
		"攻杀剑术": "ui.hud.skill_icon.warrior.power_hit",
		"刺杀剑术": "ui.hud.skill_icon.warrior.long_hit",
		"半月弯刀": "ui.hud.skill_icon.warrior.wide_hit",
		"烈火剑法": "ui.hud.skill_icon.warrior.fire_hit",
	}
	assert(Catalog.SKILL_TEXTURES.size() == 4, "战士HUD图标目录不得扩写或替换")
	for skill_name: String in expected:
		assert(Catalog.texture_for(skill_name) == Catalog.SKILL_TEXTURES[skill_name], "%s战士图标优先级发生回归" % skill_name)
		assert(Catalog.source_id_for(skill_name) == expected[skill_name], "%s战士稳定图标ID发生回归" % skill_name)
		assert(Catalog.source_path_for(skill_name).begins_with("res://assets/ui/gothic_hud/v2/runtime/skill_icons/"), "%s战士图标路径发生回归" % skill_name)


func _assert_caster_catalog_entry(skill_id: String) -> void:
	var skill_name := ProfessionRules.skill_display_name(skill_id)
	var profile := CasterSkillVisualRegistry.profile(skill_id)
	var expected_path := "res://%s" % str(profile.get("icon_path", ""))
	var icon := Catalog.texture_for(skill_name)
	assert(not skill_name.is_empty() and icon != null, "%s未得到主资料动画选帧图标" % skill_id)
	assert(Catalog.source_id_for(skill_name) == "ui.hud.skill_icon.caster.%s" % skill_id, "%s没有声明稳定caster HUD图标ID" % skill_id)
	assert(Catalog.source_path_for(skill_name) == expected_path, "%s没有使用主资料图标路径" % skill_id)
	assert(expected_path.contains("/assets/art/characters/") and expected_path.contains("/skill_icons/"), "%s错误回退为物品图标" % skill_id)


func _assert_passive_keeps_compatibility_fallback() -> void:
	var passive_name := ProfessionRules.skill_display_name("taoist.spiritual_warfare")
	assert(CasterSkillVisualRegistry.profile(passive_name).get("status", "") == "no_runtime_visual")
	assert(Catalog.texture_for(passive_name) == null, "精神力战法不得伪造主资料施法动画图标")
	assert(Catalog.source_id_for(passive_name).is_empty() and Catalog.source_path_for(passive_name).is_empty(), "精神力战法不得标记为主资料施法图标")


func _assert_hud_uses_caster_icon(hud: GameHUD, skill_id: String) -> void:
	var skill_name := ProfessionRules.skill_display_name(skill_id)
	var expected_id := Catalog.source_id_for(skill_name)
	var expected_path := Catalog.source_path_for(skill_name)
	PlayerState.quick_slots = [skill_name, "", "", ""]
	hud.update_quick_slots()
	for icon: TextureRect in [hud.quick_slot_icons[0], hud.attack_ring_skill_icons[0]]:
		assert(icon.texture != null and icon.visible, "%s在HUD快捷栏或攻击环回退为空/物品图标" % skill_id)
		assert(str(icon.get_meta("skill_icon_id", "")) == expected_id, "%s HUD图标ID错误" % skill_id)
		assert(str(icon.get_meta("skill_icon_path", "")) == expected_path, "%s HUD没有使用主资料图标路径" % skill_id)


func _assert_hud_keeps_warrior_icon(hud: GameHUD, skill_name: String) -> void:
	PlayerState.quick_slots = [skill_name, "", "", ""]
	hud.update_quick_slots()
	for icon: TextureRect in [hud.quick_slot_icons[0], hud.attack_ring_skill_icons[0]]:
		assert(icon.texture == Catalog.SKILL_TEXTURES[skill_name], "%s HUD战士图标被caster接线覆盖" % skill_name)
		assert(str(icon.get_meta("skill_icon_id", "")) == Catalog.source_id_for(skill_name), "%s HUD战士图标ID发生回归" % skill_name)


func _assert_skill_panel_uses_caster_icons(profession_id: String) -> void:
	PlayerState.profession = ProfessionRules.profession_display_name(profession_id)
	var panel := SkillPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open_for("技能导师")
	for index in range(panel.skill_entries.size()):
		var skill_name := str(panel.skill_entries[index].get("skillName", ""))
		var skill_id := ProfessionRules.skill_id(skill_name)
		panel._on_skill_selected(index)
		if skill_id == "taoist.spiritual_warfare":
			assert(str(panel.skill_icon.get_meta("skill_icon_id", "")).is_empty(), "精神力战法详情不得伪造施法图标来源")
			continue
		assert(skill_id in CasterSkillVisualRegistry.active_skill_ids(), "%s不应离开法师/道士主动技能主资料范围" % skill_name)
		assert(panel.skill_icon.texture != null, "%s技能面板回退为物品图标/空图标" % skill_id)
		assert(str(panel.skill_icon.get_meta("skill_icon_id", "")) == Catalog.source_id_for(skill_name), "%s技能面板没有使用caster图标ID" % skill_id)
		assert(str(panel.skill_icon.get_meta("skill_icon_path", "")) == Catalog.source_path_for(skill_name), "%s技能面板没有使用主资料图标路径" % skill_id)
	panel.queue_free()
