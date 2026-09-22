extends Node

const SkillPanelScript := preload("res://scripts/skill_panel.gd")
const RESOLUTION := Vector2i(1280, 720)
const UI_LAYOUT_CONTRACT := "res://assets/data/ui/manual_layout_overrides.json"


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
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(UI_LAYOUT_CONTRACT))
	var saved_hint: Array = contract["profiles"]["skill"]["nodes"]["AssignmentPanel/AssignmentHint"]["logicalRect"]
	var local_hint := hint.get_rect()
	assert(local_hint.position.is_equal_approx(Vector2(float(saved_hint[0]), float(saved_hint[1]))) and local_hint.size.is_equal_approx(Vector2(float(saved_hint[2]), float(saved_hint[3]))), "AssignmentHint must match saved parent-local logicalRect")
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
	var visible_bounds := panel.get_global_rect()
	assert(visible_bounds.encloses(h), "hint must remain within visible panel bounds")
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
	assert(assignment_panel != null and assignment_panel.size.x == 374.0)
	var attack_slot := assignment_panel.find_child("AttackSkillSlot", true, false) as Button
	var clear_attack := assignment_panel.find_child("ClearAttackSkillSlot", true, false) as Button
	assert(attack_slot != null and clear_attack != null)
	assert(not attack_slot.get_rect().intersection(clear_attack.get_rect()).has_area())
	var attack_content := attack_slot.get_node("Content") as Control
	var attack_content_id := attack_content.get_instance_id()
	var saved_icon: Array = contract["profiles"]["skill"]["nodes"]["AssignmentPanel/AttackSkillSlot/Content/SkillIcon"]["logicalRect"]
	var saved_slot_label: Array = contract["profiles"]["skill"]["nodes"]["AssignmentPanel/AttackSkillSlot/Content/SlotLabel"]["logicalRect"]
	panel.call("_set_assignment_button_content", attack_slot, "攻击主键", "烈火剑法")
	var attack_icon := attack_slot.get_node("Content/SkillIcon") as TextureRect
	assert(attack_icon != null and attack_icon.get_meta("alignment_contract", "") == "primary_attack_inset_centered.v2")
	assert(attack_slot.get_node("Content").get_instance_id() == attack_content_id, "assignment refresh recreated calibrated content")
	assert(attack_icon.position.is_equal_approx(Vector2(float(saved_icon[0]), float(saved_icon[1]))), "primary attack icon lost calibrated position")
	assert(visible_bounds.encloses(attack_slot.get_global_rect()))
	assert(visible_bounds.encloses(clear_attack.get_global_rect()))
	assert(visible_bounds.encloses(hint.get_global_rect()))
	var ring_content_ids: Array[int] = []
	var ring_icon_positions: Array[Vector2] = []
	var ring_slot_label_positions: Array[Vector2] = []
	for index in range(6):
		var ring := assignment_panel.find_child("AttackRingSkillSlot_%d" % (index + 1), true, false) as Control
		assert(ring != null and visible_bounds.encloses(ring.get_global_rect()))
		ring_content_ids.append(ring.get_node("Content").get_instance_id())
		ring_icon_positions.append((ring.get_node("Content/SkillIcon") as TextureRect).position)
		ring_slot_label_positions.append((ring.get_node("Content/SlotLabel") as Label).position)
		var clear_ring := assignment_panel.find_child("ClearAttackRingSkillSlot_%d" % (index + 1), true, false) as Control
		assert(clear_ring != null and visible_bounds.encloses(clear_ring.get_global_rect()))
		if index % 3 < 2:
			var next_ring := assignment_panel.find_child("AttackRingSkillSlot_%d" % (index + 2), true, false) as Control
			assert(not ring.get_rect().intersects(next_ring.get_rect()))
	var slot_label := attack_slot.get_node("Content/SlotLabel") as Label
	var name_label := attack_slot.get_node("Content/SkillName") as Label
	assert(slot_label.position.is_equal_approx(Vector2(float(saved_slot_label[0]), float(saved_slot_label[1]))), "primary attack label lost calibrated position")
	var icon_position_before_refresh := attack_icon.position
	var slot_label_position_before_refresh := slot_label.position
	panel.call("refresh")
	assert(attack_slot.get_node("Content").get_instance_id() == attack_content_id, "phone-style panel refresh recreated calibrated content")
	assert(attack_icon.position == icon_position_before_refresh and slot_label.position == slot_label_position_before_refresh, "phone-style panel refresh shifted primary attack content")
	for index in range(6):
		var ring_button := assignment_panel.get_node("AttackRingSkillSlot_%d" % (index + 1)) as Button
		assert(ring_button.get_node("Content").get_instance_id() == ring_content_ids[index], "phone-style panel refresh recreated ring content %d" % (index + 1))
		assert((ring_button.get_node("Content/SkillIcon") as TextureRect).position == ring_icon_positions[index], "phone-style panel refresh shifted ring icon %d" % (index + 1))
		assert((ring_button.get_node("Content/SlotLabel") as Label).position == ring_slot_label_positions[index], "phone-style panel refresh shifted ring label %d" % (index + 1))
	assert(attack_slot.get_node_or_null("Content/InteractionMode") == null, "retired primary interaction label was recreated")
	for index in range(6):
		var ring_button := assignment_panel.get_node("AttackRingSkillSlot_%d" % (index + 1)) as Button
		assert(ring_button.get_node_or_null("Content/SkillName") == null, "retired ring skill name was recreated")
	assert(assignment_panel.get_node_or_null("AttackSlotTitle") == null, "retired attack title was recreated")
	assert(panel.get_node_or_null("SkillListPanel/SkillCount") == null, "retired skill count was recreated")
	assert(panel.get_node_or_null("SkillDetailPanel/@Label@451") == null, "retired skill detail title was recreated")
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
	assert(panel.get_node_or_null("SkillDetailPanel/SkillDetailV3Frame") == null)
	assert(panel.find_child("AssignButton", true, false) == null)
	viewport.queue_free()
	await get_tree().process_frame
	print("SKILL_PANEL_ASSIGNMENT_HINT_LAYOUT_CONTRACT_PASS")
	get_tree().quit(0)
