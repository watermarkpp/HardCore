class_name PlayerHealthBar
extends Node2D

const BAR_SIZE := Vector2(50.0, 5.0)
const BACKGROUND := Color(0.12, 0.05, 0.04, 0.92)
const HEALTH := Color(0.75, 0.12, 0.08, 1.0)
const LABEL_GAP := 3.0
const LABEL_FONT_SIZE := 10

var current_hp := 1
var max_hp := 1
var _level_label := "Lv1"
var _label_width := 0.0
var _label_font: Font


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
	_label_width = _label_font.get_string_size(_level_label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x if _label_font != null else 0.0
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
	return {
		"label_text": _level_label,
		"label_rect": Rect2(group_left, 0.0, _label_width, float(LABEL_FONT_SIZE)),
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
		draw_string(_label_font, Vector2(label_rect.position.x, LABEL_FONT_SIZE - 1.0), _level_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_FONT_SIZE, Color.WHITE)
	draw_rect(rect, BACKGROUND)
	var ratio := float(current_hp) / float(max_hp)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), HEALTH)
