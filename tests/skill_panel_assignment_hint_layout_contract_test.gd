extends Node

const SkillPanelScript := preload("res://scripts/skill_panel.gd")
const RESOLUTION := Vector2i(1280, 720)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	var viewport := SubViewport.new()
	viewport.size = RESOLUTION
	var root := Control.new()
	root.size = Vector2(RESOLUTION)
	viewport.add_child(root)
	add_child(viewport)
	var panel: Control = SkillPanelScript.new()
	root.add_child(panel)
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
	viewport.queue_free()
	await get_tree().process_frame
	print("SKILL_PANEL_ASSIGNMENT_HINT_LAYOUT_CONTRACT_PASS")
	get_tree().quit(0)
