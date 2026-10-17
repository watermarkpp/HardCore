extends "res://scripts/hud.gd"
var _source_profile_ui_view: RefCounted
func configure_original_profile_view(view: RefCounted) -> bool:
	if _source_profile_ui_view != null or OS.get_thread_caller_id()!=OS.get_main_thread_id() or view == null or view.owner_thread_id()!=OS.get_main_thread_id() or view.actual_source_snapshot().is_empty(): return false
	_source_profile_ui_view=view
	return true

func _build_approved_hud() -> void:
	var loading_profile_enabled := OS.is_debug_build()
	var profile_started_usec := 0
	if loading_profile_enabled:
		profile_started_usec = Time.get_ticks_usec()
	var loading_profile: Dictionary = {}
	if loading_profile_enabled:
		loading_profile = {
			"origin": "GameHUD._ready",
			"pre_ready_boundary": (
				"GameHUD_static_script_preloads_before_ready_not_instrumented"
			),
			"stages_ms": {},
		}
	var stage_started_usec := profile_started_usec
	var root := Control.new()
	root.name = "MobileSafeRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = GothicUIThemeScript.build()
	add_child(root)
	if loading_profile_enabled:
		stage_started_usec = _hud_loading_profile_mark(
			loading_profile,
			"root_and_theme",
			stage_started_usec,
			profile_started_usec,
		)
	MobileLayoutRules.apply_display_safe_area(root, get_viewport())
	_safe_area_size_changed_callable = (
		_on_safe_area_size_changed
		.bind(root, get_viewport())
	)
	get_viewport().size_changed.connect(_safe_area_size_changed_callable)
	if loading_profile_enabled:
		stage_started_usec = _hud_loading_profile_mark(
			loading_profile,
			"safe_area_setup",
			stage_started_usec,
			profile_started_usec,
		)

	_build_hidden_compatibility_info(root)
	if loading_profile_enabled:
		stage_started_usec = _hud_loading_profile_mark(
			loading_profile,
			"build_hidden_compatibility_info",
			stage_started_usec,
			profile_started_usec,
		)
	_build_target_bar(root)
	if loading_profile_enabled:
		stage_started_usec = _hud_loading_profile_mark(
			loading_profile,
			"build_target_bar",
			stage_started_usec,
			profile_started_usec,
		)
	_build_loot_feedback(root)
	if loading_profile_enabled:
		stage_started_usec = _hud_loading_profile_mark(
			loading_profile,
			"build_loot_feedback",
			stage_started_usec,
			profile_started_usec,
		)
	_build_right_utility_stack(root)
	if loading_profile_enabled:
		stage_started_usec = _hud_loading_profile_mark(
			loading_profile,
			"build_right_utility_stack",
			stage_started_usec,
			profile_started_usec,
		)
	_build_bottom_chassis(root)
	if loading_profile_enabled:
		stage_started_usec = _hud_loading_profile_mark(
			loading_profile,
			"build_bottom_chassis",
			stage_started_usec,
			profile_started_usec,
		)
	_build_combat_controls(root)
	if loading_profile_enabled:
		stage_started_usec = _hud_loading_profile_mark(
			loading_profile,
			"build_combat_controls",
			stage_started_usec,
			profile_started_usec,
		)
	_build_item_quick_slot_menu()
	if loading_profile_enabled:
		stage_started_usec = _hud_loading_profile_mark(
			loading_profile,
			"build_item_quick_slot_menu",
			stage_started_usec,
			profile_started_usec,
		)
	# P1-C: panels are now lazy-loaded on first open
	_touch_scroll_support = TouchScrollSupportScript.attach_tree(self)
	if loading_profile_enabled:
		stage_started_usec = _hud_loading_profile_mark(
			loading_profile,
			"attach_touch_scroll_support",
			stage_started_usec,
			profile_started_usec,
		)
	_build_loading_transition()
	if loading_profile_enabled:
		stage_started_usec = _hud_loading_profile_mark(
			loading_profile,
			"build_loading_transition",
			stage_started_usec,
			profile_started_usec,
		)

	_source_profile_ui_view.profile_changed.connect(update_profile)
	_source_profile_ui_view.profile_changed.connect(update_experience_bar)
	_source_profile_ui_view.quests_changed.connect(update_quest_tracker)
	_source_profile_ui_view.skills_changed.connect(update_quick_slots)
	_source_profile_ui_view.inventory_changed.connect(update_item_quick_slots)
	if loading_profile_enabled:
		stage_started_usec = _hud_loading_profile_mark(
			loading_profile,
			"wire_player_state_signals",
			stage_started_usec,
			profile_started_usec,
		)
	update_profile()
	update_experience_bar()
	update_quest_tracker()
	update_quick_slots()
	update_item_quick_slots()
	update_resources(_last_hp, _last_max_hp, _last_mp, _last_max_mp)
	_apply_center_alignment()
	if loading_profile_enabled:
		stage_started_usec = _hud_loading_profile_mark(
			loading_profile,
			"initial_state_sync",
			stage_started_usec,
			profile_started_usec,
		)
		loading_profile["total_ms"] = (
			float(Time.get_ticks_usec() - profile_started_usec) / 1000.0
		)
		print("[InitialHUDProfile] ", JSON.stringify(loading_profile))


## 2026-09-20 user order: the dragon chassis and the top enemy bar must sit
## on the TRUE screen midline (the vertical line through the camera-centered
## character), not on the safe-area center. Devices with asymmetric left/right
## safe insets push the safe-area center sideways; these controls get a
## horizontal exemption of (right - left) / 2 so their center lands exactly on
## the viewport center. Desktop insets are 0 -> delta 0, behavior unchanged.

func _build_experience_bar(chassis_root: Control) -> void:
	var chassis_design: Dictionary = ChassisDesignsScript.active_design()
	var experience_size: Vector2
	var experience_position: Vector2
	var geometry_policy: String
	var outer_frame_source: String
	if chassis_design["experience_bar_policy"] == "chassis_design_xp_slot.v1":
		# The design art provides a dedicated experience slot: a wide thin alpha
		# hole inside the bottom plaque. The bar is drawn UNDER the frame art
		# and oversized so the opaque frame masks its edges; the pointed well
		# shape is what stays visible.
		var slot_rect: Rect2 = ChassisDesignsScript.source_rect_to_local(
			chassis_design,
			chassis_design["experience_slot_source_rect"],
		)
		var render_bleed: Vector2 = chassis_design.get("experience_slot_render_bleed", Vector2.ZERO)
		experience_size = slot_rect.size + render_bleed
		experience_position = slot_rect.position - render_bleed * 0.5
		geometry_policy = "chassis_design_xp_slot.v1"
		outer_frame_source = chassis_design["chassis_stable_id"]
	else:
		var item_slot_bounds := _item_quick_slot_outer_bounds()
		experience_size = Vector2(
			item_slot_bounds.size.x if item_slot_bounds.size.x > 0.0 else HUD_EXPERIENCE_BAR_SIZE.x,
			HUD_EXPERIENCE_BAR_HEIGHT,
		)
		experience_position = Vector2(
			item_slot_bounds.position.x
				if item_slot_bounds.size.x > 0.0
				else (HUD_CHASSIS_SIZE.x - experience_size.x) * 0.5,
			HUD_CHASSIS_SIZE.y - HUD_EXPERIENCE_BOTTOM_GAP - experience_size.y,
		)
		geometry_policy = "item_quick_slot_outer_frame_union.v1"
		outer_frame_source = "ItemSlot1.left_to_ItemSlot4.right"
	experience_bar = Control.new()
	experience_bar.name = "ExperienceBar"
	experience_bar.size = experience_size
	experience_bar.position = experience_position
	experience_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	experience_bar.set_meta("stable_id", HUD_EXPERIENCE_BAR_STABLE_ID)
	experience_bar.set_meta("segment_count", HUD_EXPERIENCE_SEGMENT_COUNT)
	experience_bar.set_meta("geometry_policy", geometry_policy)
	experience_bar.set_meta("outer_frame_source", outer_frame_source)
	experience_bar.set_meta("calibrated_height", experience_size.y)
	experience_bar.set_meta("data_source", "_source_profile_ui_view.experience / experience_to_next_level()")
	chassis_root.add_child(experience_bar)
	if geometry_policy == "chassis_design_xp_slot.v1":
		var backdrop := ColorRect.new()
		backdrop.name = "Backdrop"
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		backdrop.color = HUD_EXPERIENCE_BACKDROP_COLOR
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backdrop.set_meta("stable_id", "%s.backdrop" % HUD_EXPERIENCE_BAR_STABLE_ID)
		experience_bar.add_child(backdrop)
	experience_segments.clear()
	var gap := HUD_EXPERIENCE_SEGMENT_GAP
	var segment_width := (experience_bar.size.x - gap * (HUD_EXPERIENCE_SEGMENT_COUNT - 1)) / HUD_EXPERIENCE_SEGMENT_COUNT
	for index in range(HUD_EXPERIENCE_SEGMENT_COUNT):
		var segment := ColorRect.new()
		segment.name = "Segment%02d" % (index + 1)
		segment.position = Vector2(index * (segment_width + gap), 0)
		# 2026-09-20 user order: the visible segments must FILL the reserved
		# experience slot. Height follows the bar control (slot rect + bleed)
		# instead of the legacy fixed 10px constant; the legacy policy branch
		# still derives size.y = HUD_EXPERIENCE_BAR_HEIGHT, so it is unchanged.
		segment.size = Vector2(segment_width, experience_bar.size.y)
		segment.color = HUD_EXPERIENCE_EMPTY_COLOR
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		segment.set_meta("stable_id", "%s.segment.%02d" % [HUD_EXPERIENCE_BAR_STABLE_ID, index + 1])
		var fill := ColorRect.new()
		fill.name = "Fill"
		fill.position = Vector2.ZERO
		fill.size = Vector2.ZERO
		fill.color = HUD_EXPERIENCE_FILL_COLOR
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.set_meta("stable_id", "%s.fill.%02d" % [HUD_EXPERIENCE_BAR_STABLE_ID, index + 1])
		segment.add_child(fill)
		experience_bar.add_child(segment)
		experience_segments.append(segment)



func update_experience_bar() -> void:
	if experience_segments.is_empty():
		return
	var required := maxi(1, int(_source_profile_ui_view.experience_to_next_level()))
	var progress := experience_progress_ratio(_source_profile_ui_view.experience, required)
	for index in range(experience_segments.size()):
		var segment_progress := clampf(progress * HUD_EXPERIENCE_SEGMENT_COUNT - index, 0.0, 1.0)
		var segment := experience_segments[index]
		segment.color = HUD_EXPERIENCE_EMPTY_COLOR
		var fill := segment.get_node("Fill") as ColorRect
		fill.size = Vector2(segment.size.x * segment_progress, segment.size.y)
		segment.set_meta("fill_ratio", segment_progress)



func update_item_quick_slots() -> void:
	for index in range(ITEM_QUICK_SLOT_COUNT):
		var item_id := item_quick_slots[index] if index < item_quick_slots.size() else ""
		var record := GameData.get_entity_record(item_id)
		var item_name := str(record.get("name", ""))
		var count: int = _source_profile_ui_view.item_count_by_entity_id(item_id) if not item_id.is_empty() else 0
		var button: Button = hud_item_buttons[index] if index < hud_item_buttons.size() else null
		var icon: TextureRect = item_quick_slot_icons[index] if index < item_quick_slot_icons.size() else null
		var count_label: Label = item_quick_slot_count_labels[index] if index < item_quick_slot_count_labels.size() else null
		if button == null:
			continue
		button.set_meta("item_quick_slot_name", item_name)
		button.set_meta("item_quick_slot_entity_id", item_id)
		button.set_meta("item_quick_slot_count", count)
		button.set_meta("item_quick_slot_available", count > 0)
		if item_name.is_empty():
			button.text = str(index + 1)
			if icon != null:
				icon.texture = null
				icon.visible = false
				icon.modulate = Color.WHITE
			if count_label != null:
				count_label.text = ""
				count_label.visible = false
			button.tooltip_text = "快捷物品 %d：长按从背包选择" % (index + 1)
			continue
		var texture := UIItemTextureCacheScript.texture_for(record, "inventoryIcon")
		texture = QuickItemIconLayout.prepare_texture(texture, item_id)
		button.text = ""
		if icon != null:
			icon.texture = texture
			icon.visible = texture != null
			icon.modulate = Color(1, 1, 1, 0.45) if count <= 0 else Color.WHITE
			_layout_native_item_icon(icon, texture, button.size, GameData.get_item_art_display_size(record))
			if texture != null:
				icon.position = button.size * 0.5 - QuickItemIconLayout.visible_center(texture) * (icon.size / texture.get_size())
		if count_label != null:
			count_label.text = str(count)
			count_label.visible = true
		button.tooltip_text = "%s × %d" % [item_name, count] if count > 0 else "%s（暂无库存，补货后恢复）" % item_name


# Only pointers whose DOWN was admitted by GUI hit testing are routed here.
# Convert viewport coordinates with the live Control transform exactly once;
# held movement/attack pointers neither own nor cancel quick-item pointers.

func _item_quick_slot_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for stack: Variant in _source_profile_ui_view.inventory:
		if not stack is Dictionary:
			continue
		var item_id := GameData.item_entity_id(stack)
		if item_id.is_empty() or seen.has(item_id):
			continue
		var record := GameData.get_entity_record(item_id)
		if not _is_quick_slot_candidate(record):
			continue
		seen[item_id] = true
		result.append({"entity_id": item_id, "item_name": str(record.get("name", "")), "count": _source_profile_ui_view.item_count_by_entity_id(item_id)})
	return result



func update_profile() -> void:
	if profile_label == null:
		return
	var stats: Dictionary = _source_profile_ui_view.computed_stats
	profile_label.text = "%s  等级%d  经验%d/%d  金币%d  攻%d-%d 魔%d-%d 道%d-%d" % [
		_source_profile_ui_view.profession, _source_profile_ui_view.level, _source_profile_ui_view.experience, _source_profile_ui_view.experience_to_next_level(), _source_profile_ui_view.gold,
		int(stats.get("attack_min", 2)), int(stats.get("attack_max", 5)),
		int(stats.get("magic_min", 0)), int(stats.get("magic_max", 0)),
		int(stats.get("tao_min", 0)), int(stats.get("tao_max", 0)),
	]



func update_quest_tracker() -> void:
	if quest_tracker_label == null:
		return
	var quest_id: String = _source_profile_ui_view.current_bich_quest_id()
	if quest_id.is_empty():
		quest_tracker_label.text = "比奇主线：全部完成"
		return
	var quest := GameData.get_bich_quest(quest_id)
	var accepted: bool = _source_profile_ui_view.quest_states.has(quest_id)
	var state: Dictionary = _source_profile_ui_view.quest_states.get(quest_id, {})
	var marker := "可接" if not accepted else ("可领取" if str(state.get("status", "")) == "ready" else "进行中")
	quest_tracker_label.text = "任务[%s] %s｜%s" % [marker, quest.get("name", quest_id), "；".join(_source_profile_ui_view.quest_objective_lines(quest_id))]



func _skill_name_for_slot(slot_group: String, slot_index: int) -> String:
	if not _skill_button_assignments.is_empty():
		if _skill_button_assignments.has(slot_group):
			return _skill_name_from_group(_skill_button_assignments.get(slot_group), slot_index)
		return ""
	if _source_profile_ui_view.has_method("skill_name_for_slot"):
		return str(_source_profile_ui_view.call("skill_name_for_slot", slot_group, slot_index))
	var assignments := _active_skill_button_assignments()
	if assignments.has(slot_group):
		return _skill_name_from_group(assignments.get(slot_group), slot_index)
	if not assignments.is_empty():
		return ""
	# Compatibility for builds predating the grouped center[4] + attack_ring[3]
	# contract. Once the grouped snapshot exists, an intentionally empty attack
	# ring slot remains empty and is never mirrored from the center group.
	if slot_index >= 0 and slot_index < _source_profile_ui_view.quick_slots.size():
		return str(_source_profile_ui_view.quick_slots[slot_index])
	return ""



func _active_skill_button_assignments() -> Dictionary:
	if not _skill_button_assignments.is_empty():
		return _skill_button_assignments
	if _source_profile_ui_view.has_method("skill_button_assignments_snapshot"):
		var snapshot: Variant = _source_profile_ui_view.call("skill_button_assignments_snapshot")
		if snapshot is Dictionary:
			return snapshot
	return {}



func update_warrior_states(snapshot: Dictionary) -> void:
	_warrior_snapshot = snapshot.duplicate(true)
	if warrior_state_label == null:
		return
	warrior_state_label.visible = _source_profile_ui_view.profession_id == "hc.profession.warrior"
	if not warrior_state_label.visible:
		return
	var fire_text := _fire_sword_charge_label(snapshot)
	warrior_state_label.text = "攻杀:%s　刺杀:%s　半月:%s　烈火:%s" % [
		"几率" if bool(snapshot.get("slaying_auto", false)) else "未学",
		"开" if bool(snapshot.get("thrusting", false)) else "关",
		"开" if bool(snapshot.get("half_moon", false)) else "关",
		fire_text,
	]
	update_quick_slots()


