extends Node

## R61-REV-01 follow-up diagnostic: capture precise overflow evidence for the
## R6.1 docked presenter inside the REAL ShopPanel with the REAL gothic theme
## at 1598x720. Evidence only (untracked fixture); saves JSON + screenshots.

const ShopScript := preload("res://scripts/shop_panel.gd")

func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(OS.get_environment("R6_SHOT_DIR") + "/" + name + ".png")
	print("R6_SHOT saved=", name)

func _run() -> void:
	if not GameData.ensure_loaded():
		get_tree().quit(1)
		return
	var records: Array[String] = ["匕首", "金疮药(小量)", "古铜戒指", "木剑"]
	var out: Array = []
	var shop: Panel = ShopScript.new()
	add_child(shop)
	await get_tree().process_frame
	var stock: Array = []
	for name_value: String in records:
		stock.append({"name": name_value, "item_id": name_value, "count": 1})
	shop.call("open_for", "比奇省商人", stock, {"mode": "sell"})
	await get_tree().process_frame
	for index: int in records.size():
		shop.call("_on_item_selected", index)
		await get_tree().process_frame
		await get_tree().process_frame
		var presenter: Control = shop.get("item_detail_presenter")
		var spec: Dictionary = shop.call("_ui_detail_region", {})
		var snapshot: Dictionary = presenter.debug_layout_snapshot()
		out.append({
			"item": records[index],
			"layout_valid": snapshot.valid,
			"layout_error": snapshot.error,
			"region": str(spec.get("region", {})),
			"expanded_region": str(spec.get("expanded_region", {})),
			"detail_rect": str(snapshot.rect),
			"title_rect": str(snapshot.title_rect),
			"body_rect": str(snapshot.body_rect),
			"body_content_height": snapshot.body_content_height,
			"body_rect_height": (snapshot.body_rect as Rect2).size.y,
			"scroll_active": snapshot.scroll_active,
			"alpha": presenter.modulate.a,
			"title_text": snapshot.title,
			"title_color": str(snapshot.title_color),
		})
		await _snap("overflow_evidence_%d_%s" % [index, records[index]])
	var file := FileAccess.open(OS.get_environment("R6_OVERFLOW_JSON"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"viewport": "1598x720", "theme": "real_gothic", "rows": out}, "  ", false))
	file.close()
	print("R6_OVERFLOW_EVIDENCE_DONE rows=", out.size())
	get_tree().quit(0)
