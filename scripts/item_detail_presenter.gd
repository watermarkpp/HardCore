class_name ItemDetailPresenter
extends PanelContainer

## Shared, read-only item detail view used by inventory, warehouse and shop
## panels.  The owner supplies the selected item and global layout anchors; this
## node never owns an item list or mutates gameplay state.

const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")
const PlayerCopy := preload("res://scripts/ui_item_player_copy.gd")

const MAX_OUTER_WIDTH := 340.0
const SAFE_MARGIN := 18.0
const GAP := 12.0
const CONTENT_MARGIN := 20.0
const TITLE_SIZE := 20
const BODY_SIZE := 14
const LAYOUT_REVISION := 1
const MODIFIER_LABELS := {
	"attack": "攻击", "attack_min": "攻击下限", "attackMin": "攻击下限",
	"attack_max": "攻击上限", "attackMax": "攻击上限",
	"magic": "魔法", "magic_min": "魔法下限", "magicMin": "魔法下限",
	"magic_max": "魔法上限", "magicMax": "魔法上限",
	"tao": "道术", "tao_min": "道术下限", "taoMin": "道术下限",
	"tao_max": "道术上限", "taoMax": "道术上限",
	"defense": "防御", "defense_min": "防御下限", "defenseMin": "防御下限",
	"defense_max": "防御上限", "defenseMax": "防御上限",
	"mdef": "魔防", "mdef_min": "魔防下限", "mdefMin": "魔防下限",
	"mdef_max": "魔防上限", "mdefMax": "魔防上限",
	"accuracy": "准确", "agility": "敏捷", "luck": "幸运",
	"hpBonus": "生命", "hp_bonus": "生命", "mpBonus": "魔法值", "mp_bonus": "魔法值",
	"magicEvasionPercent": "魔法躲避", "magic_evasion_percent": "魔法躲避",
	"attackSpeedTier": "攻击速度", "attack_speed_tier": "攻击速度",
	"attack_speed_percent": "攻击速度", "cast_speed_percent": "施法速度",
	"criticalChance": "暴击", "critical_chance": "暴击",
	"criticalDamageBonus": "暴击伤害", "critical_damage_bonus": "暴击伤害",
	"skill_level": "技能等级",
}

var title_label: Label
var detail_label: RichTextLabel
var _last_anchor := Rect2()


func _init() -> void:
	name = "ItemDetailPresenter"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_meta("calibration_runtime_text", true)
	set_meta("calibration_layout_revision", LAYOUT_REVISION)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_label.add_theme_font_size_override("font_size", TITLE_SIZE)
	title_label.add_theme_color_override("font_color", Color("f2c783"))
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title_label)
	detail_label = RichTextLabel.new()
	detail_label.name = "Body"
	detail_label.bbcode_enabled = true
	detail_label.fit_content = false
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.scroll_active = true
	detail_label.custom_minimum_size = Vector2.ZERO
	detail_label.add_theme_font_size_override("normal_font_size", BODY_SIZE)
	detail_label.add_theme_color_override("default_color", Color("ddc9a9"))
	detail_label.theme_type_variation = "GothicDetailText"
	# The root is transparent to game input.  Only the bounded body may consume
	# wheel/drag input when the detail text itself needs scrolling.
	detail_label.mouse_filter = Control.MOUSE_FILTER_STOP
	detail_label.set_meta("calibration_runtime_text", true)
	content.add_child(detail_label)


func _ready() -> void:
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color(0.055, 0.039, 0.027, 0.96)
	surface.border_color = Color("8a6336")
	surface.set_border_width_all(1)
	surface.corner_radius_top_left = 6
	surface.corner_radius_top_right = 6
	surface.corner_radius_bottom_left = 6
	surface.corner_radius_bottom_right = 6
	surface.content_margin_left = CONTENT_MARGIN
	surface.content_margin_right = CONTENT_MARGIN
	surface.content_margin_top = 14.0
	surface.content_margin_bottom = 14.0
	add_theme_stylebox_override("panel", surface)
	hide_detail()


func show_item(item: Dictionary, instance: Dictionary = {}, context: Dictionary = {}) -> void:
	if item.is_empty():
		hide_detail()
		return
	if title_label == null or detail_label == null:
		return
	title_label.text = str(instance.get("name", item.get("name", "未知物品")))
	detail_label.text = format_item(item, instance, context)
	visible = true
	_place_from_context(context)


func show_multi(count: int, context: Dictionary = {}) -> void:
	if title_label == null or detail_label == null:
		return
	title_label.text = "已选择 %d 件物品" % maxi(0, count)
	detail_label.text = "多选状态下不可直接穿戴。\n请保留需要查看的最后一件物品。"
	visible = count > 0
	_place_from_context(context)


func show_message(message: String, context: Dictionary = {}) -> void:
	if title_label == null or detail_label == null:
		return
	title_label.text = "物品属性"
	detail_label.text = message
	visible = not message.is_empty()
	_place_from_context(context)


func show_text(title: String, body: String, context: Dictionary = {}) -> void:
	if title_label == null or detail_label == null:
		return
	title_label.text = title
	detail_label.text = body
	visible = not title.is_empty() or not body.is_empty()
	_place_from_context(context)


func hide_detail() -> void:
	visible = false
	_last_anchor = Rect2()


func _place_from_context(context: Dictionary) -> void:
	if not is_inside_tree():
		return
	var selected_rect: Rect2 = context.get("selected_rect", Rect2())
	var safe_rect: Rect2 = context.get("safe_rect", _owner_safe_rect())
	var avoid_rects: Array = context.get("avoid_rects", [])
	var preferred_rect: Rect2 = context.get("preferred_rect", Rect2())
	var preferred_rects: Array = context.get("preferred_rects", [])
	var placement_constraints: Dictionary = context.get("placement_constraints", {})
	place_for_rects(selected_rect, safe_rect, avoid_rects, preferred_rect, preferred_rects, placement_constraints)


func place_for_rects(
	selected_rect: Rect2,
	safe_rect: Rect2,
	avoid_rects: Array = [],
	preferred_rect := Rect2(),
	preferred_rects: Array = [],
	placement_constraints: Dictionary = {}
) -> void:
	if safe_rect.size.x <= 0.0 or safe_rect.size.y <= 0.0:
		return
	_last_anchor = selected_rect
	var width_cap := minf(safe_rect.size.x, float(placement_constraints.get("max_width", MAX_OUTER_WIDTH)))
	var measured_size := _measure_content_size(width_cap, safe_rect.size.y)
	var desired_width := clampf(measured_size.x, 1.0, width_cap)
	var desired_height := clampf(measured_size.y, 1.0, safe_rect.size.y)
	size = Vector2(minf(desired_width, safe_rect.size.x), desired_height)
	var candidates: Array[Rect2] = []
	if preferred_rect.size.x > 0.0 and preferred_rect.size.y > 0.0:
		candidates.append(Rect2(preferred_rect.position, size))
	for preferred_variant: Variant in preferred_rects:
		if preferred_variant is Rect2 and (preferred_variant as Rect2).has_area():
			var region: Rect2 = preferred_variant
			if region.size.x + 0.5 < size.x or region.size.y + 0.5 < size.y:
				continue
			candidates.append(Rect2(region.position + (region.size - size) * 0.5, size))
	if selected_rect.size.x > 0.0 and selected_rect.size.y > 0.0:
		candidates.append(Rect2(Vector2(selected_rect.position.x - size.x - GAP, selected_rect.position.y), size))
		candidates.append(Rect2(Vector2(selected_rect.end.x + GAP, selected_rect.position.y), size))
		candidates.append(Rect2(Vector2(selected_rect.position.x, selected_rect.position.y - size.y - GAP), size))
		candidates.append(Rect2(Vector2(selected_rect.position.x, selected_rect.end.y + GAP), size))
	# The center/edge candidate is useful when all four item-adjacent positions
	# intersect the paper doll or a dense grid.
	candidates.append(Rect2(safe_rect.position + (safe_rect.size - size) * 0.5, size))
	var best := candidates[0]
	var best_score := INF
	var legal_candidates: Array[Rect2] = []
	for candidate in candidates:
		var candidate_rect := _clamp_rect(candidate, safe_rect)
		if _placement_is_legal(candidate_rect, safe_rect, avoid_rects, selected_rect, placement_constraints):
			legal_candidates.append(candidate_rect)
	# An empty-cell region is preferred, but it must never force a violating
	# fallback when all hand-authored anchors intersect an occupied cell. Scan
	# the safe rectangle at a small deterministic step before considering an
	# invalid candidate; this keeps the selected cell and other occupied cells
	# actionable in dense inventories.
	if legal_candidates.is_empty():
		for candidate in _fallback_candidates(safe_rect, size):
			var fallback_rect := _clamp_rect(candidate, safe_rect)
			if _placement_is_legal(fallback_rect, safe_rect, avoid_rects, selected_rect, placement_constraints):
				legal_candidates.append(fallback_rect)
			if not legal_candidates.is_empty():
				break
	var candidates_to_score: Array[Rect2] = legal_candidates if not legal_candidates.is_empty() else candidates
	for candidate in candidates_to_score:
		var scored_rect := _clamp_rect(candidate, safe_rect)
		var uses_preferred_region := _rect_fits_preferred_region(scored_rect, preferred_rect, preferred_rects)
		var score := _placement_score(scored_rect, safe_rect, avoid_rects, selected_rect, placement_constraints, uses_preferred_region)
		if score < best_score:
			best_score = score
			best = scored_rect
	global_position = best.position


func _rect_fits_preferred_region(rect: Rect2, preferred_rect: Rect2, preferred_rects: Array) -> bool:
	if preferred_rect.has_area() and preferred_rect.encloses(rect):
		return true
	for preferred_variant: Variant in preferred_rects:
		if preferred_variant is Rect2 and (preferred_variant as Rect2).encloses(rect):
			return true
	return false


func _fallback_candidates(safe_rect: Rect2, panel_size: Vector2) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var max_x := safe_rect.end.x - panel_size.x
	var max_y := safe_rect.end.y - panel_size.y
	if max_x < safe_rect.position.x or max_y < safe_rect.position.y:
		return result
	var step := 8.0
	var y := safe_rect.position.y
	while y <= max_y + 0.5:
		var x := safe_rect.position.x
		while x <= max_x + 0.5:
			result.append(Rect2(Vector2(x, y), panel_size))
			x += step
		y += step
	return result


func _owner_safe_rect() -> Rect2:
	var owner_control := get_parent() as Control
	if owner_control == null:
		return Rect2(global_position, Vector2(640, 480))
	var owner_rect := Rect2(owner_control.get_global_transform_with_canvas().origin, owner_control.size)
	return owner_rect.grow(-SAFE_MARGIN)


func _clamp_rect(rect: Rect2, safe_rect: Rect2) -> Rect2:
	var result := rect
	result.position.x = clampf(result.position.x, safe_rect.position.x, safe_rect.end.x - result.size.x)
	result.position.y = clampf(result.position.y, safe_rect.position.y, safe_rect.end.y - result.size.y)
	return result


func _placement_score(
	rect: Rect2,
	safe_rect: Rect2,
	avoid_rects: Array,
	selected_rect: Rect2 = Rect2(),
	placement_constraints: Dictionary = {},
	preferred_region := false
) -> float:
	if not _placement_is_legal(rect, safe_rect, avoid_rects, selected_rect, placement_constraints):
		return INF
	var score := 0.0
	if not safe_rect.encloses(rect):
		score += 5000.0
	var selected_overlap_limit := float(placement_constraints.get("selected_overlap_ratio", 1.0))
	if selected_rect.has_area() and rect.intersects(selected_rect):
		var selected_intersection := rect.intersection(selected_rect)
		var selected_overlap_ratio := selected_intersection.get_area() / selected_rect.get_area()
		if selected_overlap_ratio > selected_overlap_limit:
			# Keep at least the user-approved continuous half of the selected cell
			# clickable when the empty-cell candidates are unavailable.
			score += 500000.0 + (selected_overlap_ratio - selected_overlap_limit) * 100000.0
		if bool(placement_constraints.get("continuous_selected_remainder", false)):
			var touches_boundary := (
				selected_intersection.position.x <= selected_rect.position.x + 0.5
				or selected_intersection.end.x >= selected_rect.end.x - 0.5
				or selected_intersection.position.y <= selected_rect.position.y + 0.5
				or selected_intersection.end.y >= selected_rect.end.y - 0.5
			)
			if not touches_boundary:
				# A centred overlap can leave two thin, disconnected click strips
				# even when its total area is under half the cell.
				score += 500000.0
	var full_overlap_limit := float(placement_constraints.get("avoid_full_overlap_ratio", 0.98))
	for avoid_variant: Variant in avoid_rects:
		if avoid_variant is Rect2:
			var avoid: Rect2 = avoid_variant
			if rect.intersects(avoid):
				var overlap_area := rect.intersection(avoid).get_area()
				var avoid_area := avoid.get_area()
				if avoid_area > 0.0 and overlap_area / avoid_area >= full_overlap_limit:
					# A fully covered occupied cell loses its selection/operation
					# surface; prefer any candidate that leaves it actionable.
					score += 400000.0 + overlap_area
				else:
					score += 1000.0 + overlap_area
	# Keep a small preference for positions close to the selected item so the
	# tooltip continues to follow a successful equip/unequip transaction.
	if preferred_region:
		score -= 10000.0
	if _last_anchor.size.x > 0.0:
		score += rect.get_center().distance_squared_to(_last_anchor.get_center()) * 0.0001
	return score


func _placement_is_legal(
	rect: Rect2,
	safe_rect: Rect2,
	avoid_rects: Array,
	selected_rect: Rect2 = Rect2(),
	placement_constraints: Dictionary = {}
) -> bool:
	if not safe_rect.encloses(rect):
		return false
	var selected_overlap_limit := float(placement_constraints.get("selected_overlap_ratio", 1.0))
	if selected_rect.has_area() and rect.intersects(selected_rect):
		var selected_intersection := rect.intersection(selected_rect)
		if selected_intersection.get_area() / selected_rect.get_area() > selected_overlap_limit + 0.0001:
			return false
		if bool(placement_constraints.get("continuous_selected_remainder", false)):
			var touches_boundary := (
				selected_intersection.position.x <= selected_rect.position.x + 0.5
				or selected_intersection.end.x >= selected_rect.end.x - 0.5
				or selected_intersection.position.y <= selected_rect.position.y + 0.5
				or selected_intersection.end.y >= selected_rect.end.y - 0.5
			)
			if not touches_boundary:
				return false
	var full_overlap_limit := float(placement_constraints.get("avoid_full_overlap_ratio", 0.98))
	for avoid_variant: Variant in avoid_rects:
		if avoid_variant is Rect2:
			var avoid: Rect2 = avoid_variant
			if not rect.intersects(avoid):
				continue
			var avoid_area := avoid.get_area()
			if avoid_area > 0.0 and rect.intersection(avoid).get_area() / avoid_area >= full_overlap_limit:
				return false
	return true


func _measure_content_size(width_cap: float, height_cap: float) -> Vector2:
	if width_cap <= 0.0 or height_cap <= 0.0:
		return Vector2.ONE
	var title_font := title_label.get_theme_font("font")
	var body_font := detail_label.get_theme_font("normal_font")
	var title_text := _strip_bbcode(title_label.text)
	var body_text := _strip_bbcode(detail_label.text)
	var title_width := title_font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TITLE_SIZE).x if not title_text.is_empty() else 0.0
	var longest_body_line := 0.0
	for line: String in body_text.split("\n"):
		longest_body_line = maxf(longest_body_line, body_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, BODY_SIZE).x)
	var natural_width := maxf(title_width, longest_body_line) + CONTENT_MARGIN * 2.0
	var outer_width := minf(width_cap, maxf(1.0, natural_width))
	var body_width := maxf(1.0, outer_width - CONTENT_MARGIN * 2.0)
	var body_line_height := maxf(1.0, body_font.get_height(BODY_SIZE) + 2.0)
	var body_line_count := 0
	for line: String in body_text.split("\n"):
		var line_width := body_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, BODY_SIZE).x
		body_line_count += maxi(1, ceili(line_width / body_width))
	if body_text.is_empty():
		body_line_count = 1
	var title_height := maxf(1.0, title_font.get_height(TITLE_SIZE))
	var natural_height := 14.0 + title_height + 8.0 + body_line_count * body_line_height + 14.0
	var outer_height := minf(height_cap, natural_height)
	title_label.custom_minimum_size = Vector2(0.0, title_height)
	detail_label.custom_minimum_size = Vector2(body_width, maxf(0.0, outer_height - title_height - 36.0))
	detail_label.scroll_active = natural_height > outer_height + 0.5
	return Vector2(outer_width, outer_height)


func _strip_bbcode(value: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\[[^\\]]+\\]")
	return regex.sub(value, "", true)


static func format_item(item: Dictionary, instance: Dictionary = {}, context: Dictionary = {}) -> String:
	var kind := str(item.get("kind", ""))
	var lines: Array[String] = []
	var category := str(item.get("category", item.get("type", "")))
	var weight := int(item.get("weight", 0))
	var count := int(instance.get("count", context.get("count", 1)))
	if not category.is_empty() or weight != 0:
		lines.append("类别：%s　重量 %d" % [category if not category.is_empty() else "物品", weight])
	if kind == "equipment":
		var slot := str(context.get("slot", ""))
		if not slot.is_empty():
			lines.append("部位：%s" % slot)
		var current_durability := int(instance.get("durability", item.get("maxDurability", item.get("max_durability", 0))))
		var maximum_durability := int(instance.get("max_durability", item.get("maxDurability", item.get("max_durability", 0))))
		if maximum_durability > 0:
			lines.append("耐久：%d/%d" % [current_durability, maximum_durability])
		lines.append(_stat_line(item))
		var advanced_line := _advanced_stat_line(item, instance)
		if not advanced_line.is_empty():
			lines.append(advanced_line)
		var requirement := _requirement_label(item)
		if not requirement.is_empty():
			lines.append("穿戴要求：%s" % requirement)
		var luck := int(instance.get("luck", instance.get("weapon_luck", 0)))
		var curse := int(instance.get("curse", instance.get("weapon_curse", 0)))
		if luck != 0 or curse != 0:
			lines.append("幸运 %+d　诅咒 %+d" % [luck, curse])
		var modifier_parts := _instance_modifier_lines(instance)
		if not modifier_parts.is_empty():
			lines.append("追加属性：%s" % "　".join(modifier_parts))
	elif count > 1:
		lines.append("数量：%d" % count)
	var description := PlayerCopy.description(item.get("description", context.get("description", "")))
	if not description.is_empty():
		lines.append(description)
	if lines.is_empty():
		lines.append("暂无可显示属性")
	return "\n".join(lines)


static func _stat_line(item: Dictionary) -> String:
	return "攻击 %s-%s　魔法 %s-%s\n道术 %s-%s　防御 %s-%s\n魔防 %s-%s" % [
		_value(item.get("attackMin")), _value(item.get("attackMax")), _value(item.get("magicMin")), _value(item.get("magicMax")),
		_value(item.get("taoMin")), _value(item.get("taoMax")), _value(item.get("defenseMin")), _value(item.get("defenseMax")),
		_value(item.get("mdefMin")), _value(item.get("mdefMax")),
	]


static func _advanced_stat_line(item: Dictionary, instance: Dictionary = {}) -> String:
	var parts: Array[String] = []
	for pair: Array in [["accuracy", "准确"], ["agility", "敏捷"], ["luck", "幸运"], ["hpBonus", "生命"], ["mpBonus", "魔法值"]]:
		var value_variant: Variant = instance.get(pair[0], item.get(pair[0], null))
		if value_variant != null and float(value_variant) != 0.0:
			parts.append("%s %+d" % [pair[1], int(value_variant)])
	var evasion := int(item.get("magicEvasionPercent", 0))
	if evasion != 0:
		parts.append("魔法躲避 %+d%%" % evasion)
	var speed := int(item.get("attackSpeedTier", 0))
	if speed != 0:
		parts.append("攻击速度 %+d" % speed)
	var modifiers: Variant = item.get("modifiers", {})
	if modifiers is Dictionary:
		var critical := float((modifiers as Dictionary).get("criticalChance", 0.0))
		if critical != 0.0:
			parts.append("暴击 +%d%%" % int(critical * 100.0))
	elif modifiers is Array:
		parts.append_array(_modifier_lines_from_container(modifiers))
	return "　".join(parts)


static func _instance_modifier_lines(instance: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var seen: Dictionary = {}
	for container: Variant in [instance.get("modifiers", null), instance.get("random_modifiers", null)]:
		for line: String in _modifier_lines_from_container(container):
			if not seen.has(line):
				seen[line] = true
				lines.append(line)
	var drop_affix: Variant = instance.get("drop_affix", {})
	if drop_affix is Dictionary and bool((drop_affix as Dictionary).get("applied", false)):
		for line: String in _modifier_lines_from_container([drop_affix]):
			if not seen.has(line):
				seen[line] = true
				lines.append(line)
	return lines


static func _modifier_lines_from_container(container: Variant) -> Array[String]:
	var entries: Array[Dictionary] = []
	if container is Array:
		for raw_entry: Variant in container:
			if raw_entry is Dictionary:
				entries.append(raw_entry as Dictionary)
	elif container is Dictionary:
		for key_variant: Variant in (container as Dictionary).keys():
			var raw_value: Variant = (container as Dictionary).get(key_variant, 0)
			if raw_value is int or raw_value is float:
				entries.append({"stat": str(key_variant), "op": "add", "value": raw_value})
	var result: Array[String] = []
	for entry: Dictionary in entries:
		var stat := str(entry.get("stat", ""))
		if stat.is_empty() or not entry.has("value"):
			continue
		var value_variant: Variant = entry.get("value")
		if not (value_variant is int or value_variant is float):
			continue
		var value := float(value_variant)
		if is_zero_approx(value):
			continue
		var label := str(MODIFIER_LABELS.get(stat, stat))
		var operation := str(entry.get("op", "add"))
		var value_text := _modifier_value_text(stat, operation, value)
		result.append("%s %s" % [label, value_text])
	return result


static func _modifier_value_text(stat: String, operation: String, value: float) -> String:
	var percent_stat := stat in [
		"criticalChance", "critical_chance", "attack_speed_percent", "cast_speed_percent",
		"magicEvasionPercent", "magic_evasion_percent",
	]
	if operation in ["percent", "percentage", "multiply", "mul"] or percent_stat:
		var percent_value := value * 100.0 if absf(value) <= 1.0 else value
		return "%+.0f%%" % percent_value
	if is_equal_approx(value, round(value)):
		return "%+d" % roundi(value)
	return "%+.2f" % value


static func _requirement_label(item: Dictionary) -> String:
	var requirement: Dictionary = EquipmentRulesScript.requirement_for(item)
	if requirement.is_empty():
		return ""
	var labels := {
		EquipmentRulesScript.NEED_LEVEL: "等级",
		EquipmentRulesScript.NEED_ATTACK: "攻击",
		EquipmentRulesScript.NEED_MAGIC: "魔法",
		EquipmentRulesScript.NEED_TAO: "道术",
	}
	return "%s%d" % [str(labels.get(int(requirement.get("type", EquipmentRulesScript.NEED_LEVEL)), "特殊条件")), maxi(0, int(requirement.get("value", 0)))]


static func _value(value: Variant) -> String:
	return "0" if value == null else str(int(value))
