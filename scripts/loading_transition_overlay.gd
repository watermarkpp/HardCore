class_name LoadingTransitionOverlay
extends Control

signal transition_covered(request: Dictionary)
signal transition_finished(request: Dictionary)

const CONTRACT_ID := "ui.loading.transition.v1"
const LOADING_TEXT := "Loading......"

var shade: ColorRect
var loading_label: Label
var transition_id := ""
var _fade_tween: Tween
var _pulse_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_meta("stable_id", "ui.loading.overlay")
	shade = ColorRect.new()
	shade.name = "LoadingShade"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.095, 0.095, 0.09, 0.94)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	loading_label = Label.new()
	loading_label.name = "LoadingText"
	loading_label.text = LOADING_TEXT
	loading_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading_label.add_theme_font_size_override("font_size", 25)
	loading_label.add_theme_color_override("font_color", Color("ddd7ce"))
	loading_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.018, 0.8))
	loading_label.add_theme_constant_override("outline_size", 1)
	loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(loading_label)
	hide()


func _process(delta: float) -> void:
	if not visible:
		return
	_pulse_time += delta
	loading_label.modulate.a = 0.78 + sin(_pulse_time * 2.6) * 0.14


func begin_loading(next_transition_id := "") -> void:
	_stop_fade()
	transition_id = str(next_transition_id)
	_pulse_time = 0.0
	loading_label.text = LOADING_TEXT
	modulate.a = 0.0
	show()
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(self, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_callback(_emit_covered)


func show_loading_immediately(next_transition_id := "") -> void:
	_stop_fade()
	transition_id = str(next_transition_id)
	_pulse_time = 0.0
	loading_label.text = LOADING_TEXT
	modulate.a = 1.0
	show()


func finish_loading() -> void:
	if not visible:
		return
	_stop_fade()
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(self, "modulate:a", 0.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade_tween.tween_callback(_finish_hide)


func _emit_covered() -> void:
	transition_covered.emit({
		"contract_id": CONTRACT_ID,
		"transition_id": transition_id,
	})


func _finish_hide() -> void:
	hide()
	modulate.a = 1.0
	transition_finished.emit({
		"contract_id": CONTRACT_ID,
		"transition_id": transition_id,
	})


func _stop_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
