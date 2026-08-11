class_name GothicFrameFactory
extends RefCounted

const GothicFrameFillScript := preload("res://scripts/gothic_frame_fill.gd")

const MODAL_INNER_POSITION := Vector2(41, 59)
const MODAL_INNER_END_INSET := Vector2(41, 64)
const MODAL_INNER_RADIUS := 42.0
const INSET_FRAME_VARIATION := &"GothicInsetFrame"
## Reserved local planes for sealed modal chrome.  Close controls deliberately
## sit above the safety overlay without lifting their sibling content.
const MODAL_OVERLAY_Z_INDEX := 100
const MODAL_CLOSE_CONTROL_Z_INDEX := 200


## Adds the code-drawn background for a level-1 double-ring modal frame. The
## measured opening is shared by every modal because the frame uses fixed
## nine-slice corner margins. The fill is rendered behind the parent frame, so
## it cannot cover either ring or the central ornaments.
static func add_modal_fill(parent: Control, panel_size: Vector2, node_name := "ModalSurface") -> Control:
	var fill := GothicFrameFillScript.new()
	fill.name = node_name
	fill.position = MODAL_INNER_POSITION
	fill.size = panel_size - MODAL_INNER_POSITION - MODAL_INNER_END_INSET
	fill.shape_mode = GothicFrameFillScript.ShapeMode.ROUNDED_INNER
	fill.corner_radius = MODAL_INNER_RADIUS
	fill.show_behind_parent = true
	fill.set_meta("calibration_internal_visual", true)
	parent.add_child(fill)
	return fill


## Repeats only the transparent modal-frame artwork above all content. This is
## the final safety layer: even while a section is being manually calibrated,
## neither its background nor its content can visually cover the two outer
## rings. Call this after the modal's root-level children have been built.
static func seal_modal_rings(parent: Control) -> Panel:
	var overlay := Panel.new()
	overlay.name = "ModalFrameSafetyOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = MODAL_OVERLAY_Z_INDEX
	overlay.theme_type_variation = "GothicModalFrameOverlay"
	overlay.set_meta("calibration_internal_visual", true)
	parent.add_child(overlay)
	_raise_close_controls(parent)
	return overlay


## Raise only close controls in this modal tree.  Setting the control's own
## local z-index (rather than reordering or lifting an ancestor) keeps section
## content below the overlay and leaves unrelated popups untouched.
static func _raise_close_controls(root: Control) -> void:
	for child in root.get_children():
		_raise_close_controls_recursive(child)


static func _raise_close_controls_recursive(node: Node) -> void:
	if node is Control:
		var control := node as Control
		if control.name == &"CloseButton" or control.theme_type_variation == &"GothicComponentCloseButton":
			control.z_index = maxi(control.z_index, MODAL_CLOSE_CONTROL_Z_INDEX)
	for child in node.get_children():
		_raise_close_controls_recursive(child)


## Builds a level-2 section as three independent logical layers: a neutral
## content root, a selectable decoration root, and its internal fill/frame.
## The chamfered fill follows the frame at every size instead of inserting a
## separate rounded rectangle behind it.
static func add_filled_section(
	parent: Control,
	node_name: String,
	rect: Rect2,
	frame_variation: StringName = INSET_FRAME_VARIATION,
) -> Control:
	var section := Control.new()
	section.name = node_name
	section.position = rect.position
	section.size = rect.size
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Preserve the semantic theme contract used by existing UI tests/tools even
	# though the visible style is owned by the decoration child.
	section.theme_type_variation = frame_variation
	parent.add_child(section)

	var decoration := Control.new()
	decoration.name = "%sDecoration" % node_name
	decoration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.set_meta("calibration_layer", "filled_single_ring_decoration")
	section.add_child(decoration)

	var fill := GothicFrameFillScript.new()
	fill.name = "%sFill" % node_name
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.set_meta("calibration_internal_visual", true)
	decoration.add_child(fill)

	var frame := Panel.new()
	frame.name = "%sFrame" % node_name
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.theme_type_variation = frame_variation
	frame.set_meta("calibration_internal_visual", true)
	decoration.add_child(frame)
	return section


## Fills an existing level-2 Panel without changing its public type/path. This
## is used by compact reusable dialogs whose Panel reference is a stable API.
static func add_inset_fill(frame: Panel, node_name := "InnerFill") -> Control:
	var fill := GothicFrameFillScript.new()
	fill.name = node_name
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.show_behind_parent = true
	fill.set_meta("calibration_internal_visual", true)
	frame.add_child(fill)
	return fill
