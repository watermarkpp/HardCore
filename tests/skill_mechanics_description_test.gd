extends Node

const CalibrationOverlay := preload("res://scripts/ui_layout_calibration_overlay.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var panel := SkillPanel.new()
	add_child(panel)
	await get_tree().process_frame
	var detail := panel.get_node("SkillDetailPanel") as Control
	var decoration := detail.get_node("SkillDetailPanelDecoration") as Control
	var fill := decoration.get_node("SkillDetailPanelFill") as GothicFrameFill
	var frame := decoration.get_node("SkillDetailPanelFrame") as Panel
	assert(detail != null and decoration != null and fill != null and frame != null)
	assert(detail.find_children("SkillDetailPanelDecoration", "Control", true, false).size() == 1)
	assert(detail.find_children("SkillDetailPanelFill", "GothicFrameFill", true, false).size() == 1)
	assert(detail.find_children("SkillDetailPanelFrame", "Panel", true, false).size() == 1)
	assert(panel.get_node_or_null("SkillDetailPanel/SkillDetailV3Frame") == null)
	assert(panel.find_child("LearnButton", true, false) == null)
	assert(fill.shape_mode == GothicFrameFill.ShapeMode.V3_INNER and fill.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	assert(frame.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var overlay := CalibrationOverlay.new()
	add_child(overlay)
	overlay.target = panel
	assert(overlay._is_calibratable(detail), "semantic detail panel must be selectable")
	assert(overlay._is_calibratable(decoration), "semantic decoration root must be selectable")
	assert(not overlay._is_calibratable(fill) and not overlay._is_calibratable(frame), "internal frame visuals must not be independently selectable")
	overlay.selected = decoration
	overlay.delete_selected()
	assert(not decoration.visible and detail.visible, "delete must affect the selected semantic layer only")
	overlay.undo_last_change()
	assert(decoration.visible)
	var descriptions := preload("res://scripts/skills/skill_player_description.gd")
	var source := preload("res://scripts/skills/skill_data_loader.gd")
	var before := JSON.stringify(PlayerState.computed_stats)
	var count := 0
	var evidence := {}
	for skill_id: String in source.skill_ids():
		for rank: int in [0, 1, 2, 3, 5, 7]:
			var text := descriptions.describe(skill_id, rank, PlayerState.computed_stats, 40)
			assert(text.length() > 20, "%s missing readable explanation" % skill_id)
			for forbidden: String in ["训练等级", "基础威力", "魔法威力基础值", "技能ID", "来源", "可信度", "formula_id", "source_anchor", "source_", "confidence", "random", "round", "get_power", "_formula", "GU"]:
				assert(not text.contains(forbidden), "%s leaked %s: %s" % [skill_id, forbidden, text])
			evidence["%s:%d" % [skill_id, rank]] = text
			count += 1
	assert(count == 198)
	var stats := {"magic_min": 20, "magic_max": 20, "tao_min": 20, "tao_max": 20}
	var lightning := descriptions.describe("wizard.lightning", 3, stats, 40)
	assert(lightning.contains("40～43") and lightning.contains("1.5 倍"), lightning)
	var enhanced := descriptions.describe("wizard.lightning", 5, stats, 40)
	assert(enhanced.contains("48～52"), enhanced)
	var shield := descriptions.describe("wizard.magic_shield", 3, stats, 40)
	assert(shield.contains("减少 60%") and shield.contains("35 秒"), shield)
	assert(shield.contains("吸收容量") and shield.contains("提前破盾"))
	var group_heal := descriptions.describe("taoist.mass_healing", 3, stats, 40)
	var heal_plan := descriptions.preview_effects("taoist.mass_healing", 3, stats, 40)
	assert(int(heal_plan[0].raw_heal_per_target) > 40 and int(heal_plan[0].affected_count) == 1)
	assert(group_heal.contains(str(heal_plan[0].raw_heal_per_target)) and group_heal.contains("全部满血"), group_heal)
	assert(descriptions.describe("taoist.spiritual_warfare", 2, stats, 40).contains("准确 5 点"))
	var skeleton := descriptions.describe("taoist.summon_skeleton", 7, stats, 40)
	assert(skeleton.contains("3 只") and skeleton.contains("初始宠物等级 3") and skeleton.contains("成长上限 7"), skeleton)
	assert(descriptions.describe("taoist.revelation", 0, stats, 40).contains("66.7%"))
	assert(descriptions.describe("wizard.teleport", 0, stats, 40).contains("36.4%"))
	assert(descriptions.describe("warrior.slaying_swordsmanship", 5, stats, 40).contains("35.0%"))
	assert(descriptions.mana_cost("wizard.lightning", 3) == 15)
	var poison_cost := int(source.rank_record("taoist.poison", 3).mp_cost)
	assert(descriptions.mana_cost("taoist.poison", 3) == poison_cost * 2)
	assert(descriptions.mana_cost("taoist.defense", 3, 3) == descriptions.mana_cost("taoist.defense", 3) + descriptions.mana_cost("taoist.magic_defense", 3))
	assert(JSON.stringify(PlayerState.computed_stats) == before, "description mutated player stats")
	var output := FileAccess.open("res://outputs/test_logs/skill_descriptions_verified.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(evidence, "\t"))
	output.close()
	print("SKILL_MECHANICS_DESCRIPTION_PASS")
	get_tree().quit(0)
