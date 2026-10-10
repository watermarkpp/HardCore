extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Service := preload("res://scripts/map_editor/map_editor_wall_render_plan_runtime_service.gd")
const Geometry := preload("res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd")
const MAP_KEY := "bich_mine_f1"
const PLAN_PATH := "res://assets/data/runtime/map_editor/wall_render_plans/bich_mine_f1.wall_render_plan.json"
const RUNTIME_PATH := "res://assets/data/runtime/map_editor/bich_mine_f1.runtime.json"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var proof := Proof.new()
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLAN_PATH))
	var runtime: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RUNTIME_PATH))
	var design_size: Array = plan.get("design_size", [])
	var commands: Array = Geometry.sorted_draw_commands(
		runtime.get("instances", []), runtime.get("visual_asset_snapshot", {})
	)
	var size := Vector2i(int(design_size[0]), int(design_size[1]))
	var formal := Service.load_candidate(PLAN_PATH, RUNTIME_PATH, MAP_KEY, size, commands)
	proof.record(bool(formal.get("ok", false)), "formal load_candidate accepts the real ordered plan")

	var scratch := plan.duplicate(true)
	var pages: Array = scratch.get("atlas_pages", [])
	var heights: Array = scratch.get("atlas_page_heights", [])
	var extra: Dictionary = pages[0].duplicate(true)
	extra["page_index"] = 1
	pages.append(extra)
	heights.append(heights[0])
	scratch["atlas_pages"] = pages
	scratch["atlas_page_heights"] = heights
	var ordered_path := "user://v109_wall_pages_ordered.json"
	var reordered_path := "user://v109_wall_pages_reordered.json"
	_write_json(ordered_path, scratch)
	proof.record(
		bool(Service.load_candidate(ordered_path, RUNTIME_PATH, MAP_KEY, size, commands).get("ok", false)),
		"formal load_candidate accepts a real-input scratch plan with ordered pages"
	)
	var reordered := scratch.duplicate(true)
	var reordered_pages: Array = reordered["atlas_pages"]
	reordered_pages.reverse()
	reordered["atlas_pages"] = reordered_pages
	_write_json(reordered_path, reordered)
	var reversed_result := Service.load_candidate(reordered_path, RUNTIME_PATH, MAP_KEY, size, commands)
	proof.record(
		not bool(reversed_result.get("ok", false))
		and str(reversed_result.get("reason", "")).contains("page array order mismatch"),
		"formal load_candidate rejects reordered pages before entry consumption"
	)

	var real_page_a := str(pages[0].get("path", ""))
	var real_page_b := str(pages[1].get("path", ""))
	proof.record(
		ResourceLoader.exists(Service._resource_path(real_page_a))
		and ResourceLoader.exists(Service._resource_path(real_page_b)),
		"scratch pages retain real published store resources"
	)
	proof.record(Service._validate_page_order(pages) == "", "ordered pages retain exact indices")
	proof.record(Service._validate_page_order(reordered_pages) != "", "reordered pages are fail-closed")
	var failures := proof.records.filter(func(item: Dictionary) -> bool: return not bool(item.get("passed", false))).size()
	var receipt_ok: bool = proof.write_receipt("v109_wall_page_order_contract_test", proof.records.size(), failures)
	print("V109_WALL_PAGE_ORDER_%s" % ("PASS" if receipt_ok else "FAIL"))
	get_tree().quit(0 if receipt_ok else 1)

func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
