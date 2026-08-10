extends Node

const SkillPanelScript := preload("res://scripts/skill_panel.gd")
const RESOLUTION := Vector2i(1280, 720)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.learned_skills["基本剑术"] = 0
	var viewport := SubViewport.new()
	viewport.size = RESOLUTION
	var root := Control.new()
	root.size = Vector2(RESOLUTION)
	viewport.add_child(root)
	add_child(viewport)
	var panel: Control = SkillPanelScript.new()
	root.add_child(panel)
	await get_tree().process_frame
	panel.call("open_for", "测试导师")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var hint := panel.find_child("AssignmentHint", true, false) as Label
	var parent := hint.get_parent() as Control
	assert(hint != null and parent != null)
	# Real formal Chinese hint text (both lines).
	assert(hint.text.contains("主动技能可配置到攻击主键或六个环形技能位"))
	assert(hint.text.contains("被动技能仅在技能列表中展示"))
	# Correct wrap contract: width constrained by the parent slot, height grows.
	assert(
		hint.autowrap_mode != TextServer.AUTOWRAP_OFF,
		"AssignmentHint must wrap within the parent slot"
	)
	assert(not hint.clip_text, "AssignmentHint must not hide overflow via clip")
	# 1280x720 layout contract: hint rect inside the direct parent.
	var h := hint.get_global_rect()
	var p := parent.get_global_rect()
	var overflow_x := h.end.x - p.end.x
	print(
		"SKILL_PANEL_ASSIGNMENT_HINT text_chars=%d parent=%s hint=%s min=%s autowrap=%d clip=%s overflow_x=%.2f font_size=%d"
		% [
			hint.text.length(),
			str(p),
			str(h),
			str(hint.get_combined_minimum_size()),
			hint.autowrap_mode,
			str(hint.clip_text),
			overflow_x,
			hint.get_theme_font_size("font_size"),
		]
	)
	assert(overflow_x <= 1.0, "no horizontal overflow: %.2f px" % overflow_x)
	assert(h.position.x >= p.position.x - 1.0, "hint must not escape parent left")
	assert(h.position.y >= p.position.y - 1.0, "hint must not escape parent top")
	# Text fully visible: the label's height accommodates the wrapped minimum.
	assert(
		hint.size.y >= hint.get_combined_minimum_size().y,
		"hint height must fit wrapped text"
	)
	assert(
		hint.size.x >= hint.get_combined_minimum_size().x,
		"hint width must fit text minimum"
	)
	assert(panel.find_child("AssignButton", true, false) == null, "center detail assignment button must be removed")
	var assignment_panel := panel.find_child("AssignmentPanel", true, false) as Control
	assert(assignment_panel != null and assignment_panel.size == Vector2(434.0, 524.0))
	var attack_slot := assignment_panel.find_child("AttackSkillSlot", true, false) as Button
	var clear_attack := assignment_panel.find_child("ClearAttackSkillSlot", true, false) as Button
	assert(attack_slot != null and clear_attack != null)
	assert(not attack_slot.get_rect().intersection(clear_attack.get_rect()).has_area())
	panel.call("_set_assignment_button_content", attack_slot, "攻击主键", "烈火剑法")
	var attack_icon := attack_slot.get_node("Content/SkillIcon") as TextureRect
	assert(attack_icon != null and attack_icon.get_meta("alignment_contract", "") == "primary_attack_inset_centered.v2")
	assert(attack_icon.position.x >= 24.0 and attack_icon.position.x < 32.0)
	var assignment_bounds := Rect2(Vector2.ZERO, assignment_panel.size)
	assert(assignment_bounds.encloses(attack_slot.get_rect()))
	assert(assignment_bounds.encloses(clear_attack.get_rect()))
	assert(assignment_bounds.encloses(hint.get_rect()))
	for index in range(6):
		var ring := assignment_panel.find_child("AttackRingSkillSlot_%d" % (index + 1), true, false) as Control
		assert(ring != null and assignment_bounds.encloses(ring.get_rect()))
		var clear_ring := assignment_panel.find_child("ClearAttackRingSkillSlot_%d" % (index + 1), true, false) as Control
		assert(clear_ring != null and assignment_bounds.encloses(clear_ring.get_rect()))
		if index % 3 < 2:
			var next_ring := assignment_panel.find_child("AttackRingSkillSlot_%d" % (index + 2), true, false) as Control
			assert(not ring.get_rect().intersects(next_ring.get_rect()))
	var mode_label := attack_slot.get_node("Content/InteractionMode") as Label
	var slot_label := attack_slot.get_node("Content/SlotLabel") as Label
	var name_label := attack_slot.get_node("Content/SkillName") as Label
	assert(mode_label.position.x == slot_label.position.x and mode_label.position.x == name_label.position.x)
	var title := panel.get_node("SkillDetailPanel/SkillName") as Label
	assert(title != null)
	var learned_index := -1
	var entries: Array = panel.get("skill_entries")
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		if PlayerState.is_skill_learned(str(entry.get("skillName", ""))):
			learned_index = index
			break
	assert(learned_index >= 0, "fixture must contain an actually learned skill")
	panel.call("_show_skill_detail", learned_index)
	assert(title.text.contains("（已学会）"))
	assert(panel.find_child("LearnButton", true, false) == null)
	assert(panel.find_child("AssignButton", true, false) == null)
	viewport.queue_free()
	await get_tree().process_frame
	print("SKILL_PANEL_ASSIGNMENT_HINT_LAYOUT_CONTRACT_PASS")
	get_tree().quit(0)
