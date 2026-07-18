extends Node

const CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/profession_selection_contract_v1.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "战士"
	PlayerState.level = 40
	var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	assert(contract is Dictionary, "职业选择 UI 契约无法解析")
	assert(contract.get("contractId", "") == "ui.profession.selection.v1", "职业选择契约 ID 不稳定")
	assert(contract.get("professionIds", []) == ["warrior", "wizard", "taoist"], "职业稳定 ID 不完整")
	var panel := ProfessionPanel.new()
	add_child(panel)
	await get_tree().process_frame

	assert(panel.size == Vector2(1100, 636), "职业面板没有使用既定横屏尺寸")
	assert(panel.theme_type_variation == "GothicModalFrame", "职业面板没有使用公共哥特外框")
	assert(panel.get_node("ProfessionTabs").theme_type_variation == "GothicInsetFrame", "职业分页没有使用公共内框")
	assert(panel.get_node("ProfessionIdentity").theme_type_variation == "GothicInsetFrame", "职业定位没有使用公共内框")
	assert(panel.get_node("GrowthPath").theme_type_variation == "GothicInsetFrame", "成长路线没有使用公共内框")
	assert(panel.get_node("Unlocks").theme_type_variation == "GothicInsetFrame", "技能解锁没有使用公共内框")
	assert(panel.profession_tabs.size() == 3, "职业分页数量不是 3")
	assert(panel.profession_tabs["战士"].get_meta("stable_tab_id", "") == "profession.tab.warrior", "战士分页稳定 ID 错误")
	assert(panel.profession_tabs["法师"].get_meta("stable_tab_id", "") == "profession.tab.wizard", "法师分页稳定 ID 错误")
	assert(panel.profession_tabs["道士"].get_meta("stable_tab_id", "") == "profession.tab.taoist", "道士分页稳定 ID 错误")
	assert(panel.growth_cards.size() == 4, "成长路线没有显示 4 个阶段")
	assert(panel.get_node("ProfessionIdentity/ProfessionEmblemFrame").get_meta("preview_kind", "") == "profession_emblem", "职业素材应明确标识为徽记预览")

	panel._preview_profession("法师")
	await get_tree().process_frame
	assert(panel.selected_profession == "法师", "法师分页没有切换预览")
	assert(PlayerState.profession == "战士", "点击职业分页不应立即修改人物职业")
	assert(not panel.confirm_button.disabled, "预览其他职业后确认按钮应可用")
	assert(panel.unlock_list.get_child_count() == GameData.get_profession_skills("法师").size(), "法师解锁列表没有读取实际技能数据")
	assert(panel.unlock_list.get_child_count() == 14, "法师应显示现有 14 项一级技能记录")
	assert(panel.identity_icon.texture != null, "法师职业徽记素材没有加载")
	assert(panel.identity_icon.get_meta("source_path", "") == "res://assets/art/characters/wizard/effects/area_burst.png", "法师职业徽记来源错误")
	var wizard_stats := ProfessionRules.stats_for_level("法师", 40)
	assert(str(wizard_stats.get("max_hp", 0)) in panel.stats_label.text, "法师生命预览没有读取玩法数据")
	assert(str(wizard_stats.get("max_mp", 0)) in panel.stats_label.text, "法师魔法预览没有读取玩法数据")
	assert("确认前不会修改角色数据" in panel.detail_label.text, "职业预览缺少非破坏提示")

	panel._request_confirmation()
	assert(panel.confirmation_popup.visible, "改变职业前没有打开二次确认")
	assert(PlayerState.profession == "战士", "打开确认窗口时不应修改职业")
	assert(panel.confirmation_apply_button.get_meta("profession_id", "") == "wizard", "确认请求没有保留职业稳定 ID")
	panel._apply_selected_profession()
	await get_tree().process_frame
	assert(PlayerState.profession == "法师", "确认后没有调用人物职业接口")
	assert(panel.selected_profession == "法师", "人物职业变化后预览没有同步")
	assert(panel.confirm_button.disabled, "应用职业后确认按钮没有切换为当前职业状态")
	assert("职业已切换为法师" in panel.detail_label.text, "职业切换结果没有显示")

	panel._preview_profession("道士")
	await get_tree().process_frame
	assert(panel.unlock_list.get_child_count() == GameData.get_profession_skills("道士").size(), "道士解锁列表没有读取实际技能数据")
	assert(panel.identity_icon.texture != null, "道士职业徽记素材没有加载")
	print("PROFESSION_GOTHIC_UI_PASS：三职业预览、玩法数据成长、滚动解锁和二次确认均正常")
	get_tree().quit(0)
