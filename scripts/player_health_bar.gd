class_name PlayerHealthBar
extends Node2D

const BAR_SIZE := Vector2(50.0, 5.0)
const BACKGROUND := Color(0.12, 0.05, 0.04, 0.92)
const HEALTH := Color(0.75, 0.12, 0.08, 1.0)
const LABEL_GAP := 3.0
const LABEL_FONT_SIZE := 10
# The fallback font's descent includes transparent leading below the visible
# glyphs. Three logical pixels close the measured device crop gap at the current
# 1598->2664 scale without moving the metric layout edge or bar/group geometry.
const LABEL_OPTICAL_NUDGE_Y := 3.0

var current_hp := 1
var max_hp := 1
var _level_label := "Lv1"
var _label_width := 0.0
var _label_font: Font
var _label_ascent := float(LABEL_FONT_SIZE)
var _label_descent := 0.0
var _label_height := float(LABEL_FONT_SIZE)


func setup(current_value: int, maximum_value: int) -> void:
	set_health(current_value, maximum_value)
	_refresh_level_label()


func _ready() -> void:
	_label_font = ThemeDB.fallback_font
	if not PlayerState.profile_changed.is_connected(_on_player_profile_changed):
		PlayerState.profile_changed.connect(_on_player_profile_changed)
	_refresh_level_label()


func _on_player_profile_changed() -> void:
	_refresh_level_label()


func _refresh_level_label() -> void:
	_level_label = "Lv%d" % maxi(1, int(PlayerState.level))
	if _label_font == null:
		_label_font = ThemeDB.fallback_font
	if _label_font != null:
		_label_width = _label_font.get_string_size(_level_label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x
		_label_ascent = _label_font.get_ascent(LABEL_FONT_SIZE)
		_label_descent = _label_font.get_descent(LABEL_FONT_SIZE)
		_label_height = _label_ascent + _label_descent
	else:
		_label_width = 0.0
		_label_ascent = float(LABEL_FONT_SIZE)
		_label_descent = 0.0
		_label_height = float(LABEL_FONT_SIZE)
	queue_redraw()


func set_health(current_value: int, maximum_value: int) -> void:
	max_hp = maxi(1, maximum_value)
	current_hp = clampi(current_value, 0, max_hp)
	queue_redraw()


func level_label_text() -> String:
	return _level_label


func layout_snapshot() -> Dictionary:
	var total_width := _label_width + LABEL_GAP + BAR_SIZE.x
	var group_left := -total_width * 0.5
	var bar_left := group_left + _label_width + LABEL_GAP
	var bar_bottom := BAR_SIZE.y
	var label_top := bar_bottom - _label_height
	return {
		"label_text": _level_label,
		"label_rect": Rect2(group_left, label_top, _label_width, _label_height),
		"label_baseline": bar_bottom - _label_descent,
		"label_draw_baseline": bar_bottom - _label_descent + LABEL_OPTICAL_NUDGE_Y,
		"label_optical_nudge_y": LABEL_OPTICAL_NUDGE_Y,
		"label_ascent": _label_ascent,
		"label_descent": _label_descent,
		"gap": LABEL_GAP,
		"bar_rect": Rect2(bar_left, 0.0, BAR_SIZE.x, BAR_SIZE.y),
		"group_rect": Rect2(group_left, 0.0, total_width, BAR_SIZE.y),
		"group_center_x": group_left + total_width * 0.5,
		"bar_size": BAR_SIZE,
		"background_color": BACKGROUND,
		"health_color": HEALTH,
	}


func _draw() -> void:
	var snapshot := layout_snapshot()
	var rect: Rect2 = snapshot["bar_rect"]
	if _label_font != null:
		var label_rect: Rect2 = snapshot["label_rect"]
		var label_baseline := float(snapshot["label_draw_baseline"])
		draw_string(_label_font, Vector2(label_rect.position.x, label_baseline), _level_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_FONT_SIZE, Color.WHITE)
	draw_rect(rect, BACKGROUND)
	var ratio := float(current_hp) / float(max_hp)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), HEALTH)
