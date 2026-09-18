class_name PlayerStatusMarkerStrip
extends Node2D

## Status marker row under the player overhead HP bar (R1.1 closure).
##
## The player presents 麻痹/中毒 the same way monsters present their overhead
## status dots (see enemy.gd POISON_INDICATOR_*): one compact dot per active
## status in a fixed slot below the health bar, never as a ground ring. Slots
## are fixed so the row order is stable: paralysis always the left slot,
## poison always the right slot. Timers and gameplay values are only read.

const MARKER_DOT_RADIUS := 3.0
const MARKER_SLOT_OFFSET_X := 5.0
const PARALYSIS_MARKER_COLOR := Color(0.42, 0.62, 1.0, 0.90)
const POISON_MARKER_COLOR := Color(0.36, 0.92, 0.28, 0.90)

var _status_source: Node = null
var _last_signature := ""


func bind_status_source(source: Node) -> void:
	_status_source = source
	queue_redraw()


## Fixed-order marker contract for tests and diagnostics: the returned array
## lists active markers in slot order ("paralysis", then "poison").
func active_status_markers() -> Array[String]:
	var markers: Array[String] = []
	if _paralysis_active():
		markers.append("paralysis")
	if _poison_active():
		markers.append("poison")
	return markers


func marker_slot_center(marker: String) -> Vector2:
	var offset_x := -MARKER_SLOT_OFFSET_X if marker == "paralysis" else MARKER_SLOT_OFFSET_X
	return Vector2(offset_x, 0.0)


func _paralysis_active() -> bool:
	if _status_source == null or not is_instance_valid(_status_source):
		return false
	if int(_status_source.get("current_hp")) <= 0:
		return false
	return float(_status_source.get("control_time")) > 0.0


func _poison_active() -> bool:
	if _status_source == null or not is_instance_valid(_status_source):
		return false
	if not _status_source.has_method("poison_status_remaining"):
		return false
	if int(_status_source.get("current_hp")) <= 0:
		return false
	return float(_status_source.poison_status_remaining()) > 0.0


func _process(_delta: float) -> void:
	var signature := ",".join(active_status_markers())
	if signature != _last_signature:
		_last_signature = signature
		queue_redraw()


func _draw() -> void:
	for marker in active_status_markers():
		var marker_color := PARALYSIS_MARKER_COLOR if marker == "paralysis" else POISON_MARKER_COLOR
		draw_circle(marker_slot_center(marker), MARKER_DOT_RADIUS, marker_color)
