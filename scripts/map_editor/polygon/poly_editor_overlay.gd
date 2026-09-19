extends Control
var controller: Variant

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	if is_instance_valid(controller):
		controller.draw_overlay(self)
