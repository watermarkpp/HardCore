extends Node
## Data-wide presenter coverage. Real panel/screenshots remain a separate gate.
@export var zone := "inventory"
const Presenter := preload("res://scripts/item_detail_docked_presenter.gd")
var failures: Array[String] = []
class Scope:
	extends Control
	var region := Rect2(30, 30, 230, 600)
	func _ui_detail_region(_context: Dictionary) -> Dictionary:
		return {"region": region, "side": "center"}
func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()
func _run() -> void:
	if not GameData.ensure_loaded():
		push_error("R6_CATALOG_DATA_NOT_LOADED")
		get_tree().quit(1)
		return
	var host := Scope.new()
	host.size = Vector2(1600, 720)
	if zone == "equipment":
		host.region = Rect2(30, 30, 180, 440)
	elif zone == "shop":
		host.region = Rect2(30, 30, 250, 350)
	add_child(host)
	var view := Presenter.new()
	host.add_child(view)
	var checked := 0
	var rows: Array = []
	for value: Variant in GameData.item_catalog:
		if not value is Dictionary or (value as Dictionary).is_empty():
			continue
		var item: Dictionary = value
		if zone == "equipment" and str(item.get("kind", "")) != "equipment":
			continue
		var instance := {"name": str(item.get("name", "")), "count": 1}
		view.show_item(item, instance, {"count": 1, "presentation_zone": zone})
		await get_tree().process_frame
		var snapshot: Dictionary = view.debug_layout_snapshot()
		var good := bool(snapshot["valid"]) and view.title_label.visible and not view.title_label.text.strip_edges().is_empty() and not view.detail_label.scroll_active and float(view.detail_label.get_content_height()) <= view.detail_label.size.y
		checked += 1
		rows.append({"name": view.title_label.text, "valid": good, "rect": str(snapshot["rect"]), "error": snapshot["error"]})
		if not good:
			failures.append(str(item.get("name", "")) + ": " + str(snapshot["error"]))
	if checked == 0:
		failures.append("ZERO_CATALOG_COVERAGE")
	var file := FileAccess.open("user://r6_catalog_" + zone + ".json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"zone": zone, "checked": checked, "failures": failures, "rows": rows}))
		file.close()
	host.queue_free()
	await get_tree().process_frame
	for message: String in failures:
		push_error("R6_CATALOG " + zone + " " + message)
	print("R6_1_CATALOG_%s_%s checked=%d failures=%d" % [zone.to_upper(), "PASS" if failures.is_empty() else "FAIL", checked, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
