extends RefCounted
## Canvas-only shortcut, leaving normal arrows and text-editing behavior alone.
const Binding := preload("res://scripts/map_editor/polygon/poly_instance_binding.gd")
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Coord := preload("res://scripts/map_editor/map_editor_coordinate.gd")

static func nudged(instance: Dictionary, delta_px: Vector2, asset: Dictionary = {}) -> Dictionary:
	var result := instance.duplicate(true)
	var offset := Binding.pair(instance.get("offset_px", [0, 0]), Vector2.INF)
	if not offset.is_finite() or not delta_px.is_finite():
		return {}
	result["offset_px"] = [offset.x + delta_px.x, offset.y + delta_px.y]
	result["hc_pixel_offset_authored"] = true
	# The default sorting offset already follows offset_px. Only explicit cuts
	# need adjustment; adding it twice would create a fresh art/collision drift.
	if instance.has("sort_baseline_offset_px"):
		var sort_offset := Binding.pair(instance.sort_baseline_offset_px, Vector2.INF)
		if not sort_offset.is_finite():
			return {}
		result["sort_baseline_offset_px"] = [sort_offset.x + delta_px.x, sort_offset.y + delta_px.y]
	elif asset.has("sort_baseline_offset_px"):
		var asset_offset := Binding.pair(asset.sort_baseline_offset_px, Vector2.INF)
		if not asset_offset.is_finite():
			return {}
		result["sort_baseline_offset_px"] = [asset_offset.x + delta_px.x, asset_offset.y + delta_px.y]
	return result

static func handle(app: Variant, event: InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed or not event.ctrl_pressed or event.alt_pressed:
		return false
	var delta: Vector2 = {KEY_UP: Vector2(0, -1), KEY_DOWN: Vector2(0, 1),
		KEY_LEFT: Vector2(-1, 0), KEY_RIGHT: Vector2(1, 0)}.get(event.keycode, Vector2.ZERO)
	if delta == Vector2.ZERO:
		return false
	var canvas: Variant = app.preview
	if canvas.get_viewport().gui_get_focus_owner() != canvas:
		return false
	if canvas.is_clipboard_paste_active():
		return true
	var id := str(canvas.selected_selectable_id)
	if id.is_empty():
		return false
	var document: Dictionary = app.current_document
	var found := Binding.locate(document, id)
	if not found.ok:
		app.status_label.text = "像素微调只用于素材；功能标注继续使用自己的位置工具。"
		return true
	var before: Dictionary = found.instance.duplicate(true)
	if bool(before.get("selection_locked", false)) or not bool(before.get("movable", true)):
		app.status_label.text = "该素材已锁定，不能移动。"
		return true
	if bool(before.get("editor_visual_only", false)):
		app.status_label.text = "这是功能标注的占位显示，请移动对应功能标注，不能单独移走占位图。"
		return true
	if not Geo.enabled(document) and str(before.get("collision_policy", "none")) not in ["none", "manual"]:
		app.status_label.text = "该旧素材仍使用格子生成碰撞；先升级本地图，再进行像素微调，避免图和碰撞分离。"
		return true
	var asset := MapAssetCatalogService.find_asset(str(before.get("asset_id", "")))
	var after := nudged(before, delta, asset)
	if after.is_empty():
		app.status_label.text = "素材位置数据无效，未执行移动。"
		return true
	var size_gu := Geo.parse_size(document.get("design", {}).get("design_size", []))
	var transform := Binding.frame(after, asset, size_gu)
	if not transform.ok:
		app.status_label.text = "素材变换无效，未执行移动。"
		return true
	var foot := Coord.screen_position_px_to_ground_position_gu(transform.foot_world_px, size_gu)
	if foot.x < 0.0 or foot.y < 0.0 or foot.x > size_gu.x or foot.y > size_gu.y:
		app.status_label.text = "素材脚点不能移出地图。"
		return true
	for row: Dictionary in after.get(Binding.FIELD, []):
		var points := Binding.to_ground(Geo.decode(row.get("points", [])), after, asset, size_gu)
		if not Geo.validate(Geo.encode(points), size_gu).ok:
			app.status_label.text = "移动会使绑定碰撞无效或越界，未执行。"
			return true
	# Snapshot only this instance, not an entire large map per pixel/key repeat.
	app.command_stack.execute({"label": "素材像素微调",
		"do": func() -> void: _apply(app, document, id, after, "素材微调 1 像素"),
		"undo": func() -> void: _apply(app, document, id, before, "撤销素材像素微调")})
	return true

static func _apply(app: Variant, document: Dictionary, id: String, instance: Dictionary, label: String) -> void:
	if not is_same(app.current_document, document):
		app.status_label.text = "文档已更换，拒绝跨地图撤销。"
		return
	var found := Binding.locate(document, id)
	if not found.ok:
		app.status_label.text = "素材已不存在，拒绝把旧撤销记录应用到其他素材。"
		return
	document.layers[found.layer][found.index] = instance.duplicate(true)
	var meta: Dictionary = document.get("editor_meta", {})
	meta["revision"] = int(meta.get("revision", 1)) + 1
	meta["runtime_approved"] = false
	document.editor_meta = meta
	app._last_build_candidate = {}
	app.preview.set_document(document)
	app.status_label.text = "%s；offset_px=%s。地图级碰撞不会自动跟随，素材绑定碰撞会跟随。" % [label, str(instance.get("offset_px", []))]
