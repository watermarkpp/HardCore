class_name WallRuntimePerfProbe
extends Node

## WALL-P0 read-only performance probe (no visual or renderer changes).
##
## Collects, per measurement window:
##   logical layer  - total / y-sort / static command counts from the frozen
##                    sorted_draw_commands authority held by WorldBackground
##   physical layer - Y-sort segment wrappers (editor_runtime_actor_occluder),
##                    their dynamic children, bridge overlays, and static
##                    EditorRuntimeInstance sprites, each also counted as
##                    visible-in-tree and visible-in-camera
##   engine layer   - Performance RENDER_TOTAL_OBJECTS_IN_FRAME,
##                    RENDER_TOTAL_DRAW_CALLS_IN_FRAME,
##                    RENDER_TOTAL_PRIMITIVES_IN_FRAME, OBJECT_NODE_COUNT,
##                    PHYSICS_2D_COLLISION_PAIRS (avg/max over the window)
##   frame timing   - avg / P50 / P95 / P99 / max frame delta
##
## Output: one JSON document per window printed as a single
## WALL_PERF_SUMMARY {...} line and stored under user://wall_perf/ (plus a
## best-effort copy under res://outputs/wall_perf/ on desktop).
##
## Enablement (all optional, zero cost when absent):
##   - env HC_WALL_PERF=1
##   - cmdline user arg --wall-perf-probe
##   - marker file user://wall_perf_probe_enabled.txt (device)
##
## Auto mode watches WorldBackground.zone_name transitions (device matrix:
## enter a map, stabilize, measure, move on). Manual mode (lab) runs one
## window on demand.

const OUTPUT_USER_DIR := "user://wall_perf"
const OUTPUT_LOCAL_DIR := "res://outputs/wall_perf"
const GEOMETRY_SERVICE := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)
const MONITOR_KEYS := {
	"render_objects": Performance.RENDER_TOTAL_OBJECTS_IN_FRAME,
	"draw_calls": Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME,
	"primitives": Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME,
	"object_nodes": Performance.OBJECT_NODE_COUNT,
	"physics_pairs": Performance.PHYSICS_2D_COLLISION_PAIRS,
}

var background: Node = null
var scan_root: Node = null
var auto_mode := false
var stabilization_seconds := 8.0
var window_seconds := 30.0

var _active := false
var _stabilizing := false
var _stabilization_left := 0.0
var _window_left := 0.0
var _window_label := ""
var _window_zone := ""
var _frame_deltas := PackedFloat64Array()
var _monitor_accum := {}
var _poll_accum := 0.0
var _last_zone := ""
var _summary_signal_emitted := false
var _skip_first_frame := false

signal window_finished(summary: Dictionary)


static func enabled_by_environment() -> bool:
	if OS.get_environment("HC_WALL_PERF") == "1":
		return true
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--wall-perf-probe":
			return true
	return FileAccess.file_exists("user://wall_perf_probe_enabled.txt")


func configure(
	probe_background: Node,
	probe_scan_root: Node,
	probe_auto_mode: bool
) -> void:
	background = probe_background
	scan_root = probe_scan_root
	auto_mode = probe_auto_mode


func start_window(label: String, seconds: float) -> void:
	_window_label = label
	_window_zone = str(background.get("zone_name")) if background else ""
	_begin_measurement(seconds)


func _ready() -> void:
	if background == null and auto_mode:
		queue_free()
		return
	set_process(auto_mode or false)


func _process(delta: float) -> void:
	if auto_mode and not _active and not _stabilizing:
		_poll_accum += delta
		if _poll_accum >= 1.0:
			_poll_accum = 0.0
			_watch_zone_transitions()
		return
	if _stabilizing:
		_stabilization_left -= delta
		if _stabilization_left <= 0.0:
			_stabilizing = false
			_begin_measurement(window_seconds)
		return
	if not _active:
		return
	# The window-start synchronous tree scan inflates exactly one frame
	# delta; drop it so percentile stats measure steady state only.
	if _skip_first_frame:
		_skip_first_frame = false
		return
	_frame_deltas.append(delta)
	_sample_monitors()
	_window_left -= delta
	if _window_left <= 0.0:
		_finish_window()


func _watch_zone_transitions() -> void:
	if background == null or not is_instance_valid(background):
		return
	var zone := str(background.get("zone_name"))
	if zone.is_empty():
		return
	if _last_zone == "":
		_last_zone = zone
		return
	if zone != _last_zone:
		_last_zone = zone
		_stabilizing = true
		_stabilization_left = stabilization_seconds
		_window_label = zone
		print(
			"WALL_PERF_STABILIZE label=%s seconds=%s" % [
				zone, str(stabilization_seconds),
			]
		)


func _begin_measurement(seconds: float) -> void:
	_active = true
	_window_left = seconds
	_frame_deltas = PackedFloat64Array()
	_monitor_accum = {}
	_skip_first_frame = true
	_summary_signal_emitted = false
	set_process(true)
	var counts := _collect_counts()
	print(
		"WALL_PERF_WINDOW_START label=%s seconds=%s logical=%d wrappers=%d" % [
			_window_label, str(seconds), counts["logical_total"],
			counts["wrapper_count"],
		]
	)


func _sample_monitors() -> void:
	for key: String in MONITOR_KEYS:
		var value := float(Performance.get_monitor(MONITOR_KEYS[key]))
		var bucket: Dictionary = _monitor_accum.get(
			key, {"sum": 0.0, "count": 0, "max": 0.0}
		)
		bucket["sum"] = float(bucket["sum"]) + value
		bucket["count"] = int(bucket["count"]) + 1
		bucket["max"] = maxf(float(bucket["max"]), value)
		_monitor_accum[key] = bucket


func _finish_window() -> void:
	_active = false
	var summary := _collect_counts()
	summary["label"] = _window_label
	summary["zone"] = _window_zone
	summary["window_seconds"] = snappedf(
		_window_label_length(), 0.001
	)
	for key: String in _monitor_accum:
		var bucket: Dictionary = _monitor_accum[key]
		summary[key] = {
			"avg": snappedf(
				float(bucket["sum"]) / maxf(float(bucket["count"]), 1.0),
				0.01
			),
			"max": float(bucket["max"]),
		}
	var frame_stats := _frame_percentiles()
	summary["frame_ms"] = frame_stats
	summary["video_adapter"] = RenderingServer.get_video_adapter_name()
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		summary["camera_world_position"] = [
			snappedf(camera.get_global_position().x, 0.5),
			snappedf(camera.get_global_position().y, 0.5),
		]
	if scan_root != null and scan_root.get("player") != null:
		var player: Node2D = scan_root.get("player")
		summary["player_world_position"] = [
			snappedf(player.get_global_position().x, 0.5),
			snappedf(player.get_global_position().y, 0.5),
		]
	var json := JSON.stringify(summary)
	_write_outputs(json)
	print("WALL_PERF_SUMMARY %s" % json)
	if not _summary_signal_emitted:
		_summary_signal_emitted = true
		window_finished.emit(summary)


func _window_label_length() -> float:
	# Window length actually measured; derived from the sampled frames.
	var measured := 0.0
	for delta: float in _frame_deltas:
		measured += delta
	return measured


func _frame_percentiles() -> Dictionary:
	if _frame_deltas.is_empty():
		return {"avg": 0.0, "p50": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
	var sorted := _frame_deltas.duplicate()
	sorted.sort()
	var total := 0.0
	for delta: float in sorted:
		total += delta
	var percentile := func(p: float) -> float:
		var index := int(clampf(p, 0.0, 1.0) * float(sorted.size() - 1))
		return snappedf(sorted[index] * 1000.0, 0.01)
	return {
		"avg": snappedf(total / float(sorted.size()) * 1000.0, 0.01),
		"p50": percentile.call(0.50),
		"p95": percentile.call(0.95),
		"p99": percentile.call(0.99),
		"max": snappedf(sorted[sorted.size() - 1] * 1000.0, 0.01),
		"samples": sorted.size(),
	}


func _collect_counts() -> Dictionary:
	var counts := {
		"logical_total": 0,
		"logical_y_sort": 0,
		"logical_static": 0,
		"wrapper_count": 0,
		"wrapper_dynamic_children": 0,
		"bridge_overlay_count": 0,
		"static_sprite_count": 0,
		"static_wall_shadow_count": 0,
		"static_other_count": 0,
		"visible_wrappers": 0,
		"visible_dynamic_children": 0,
		"visible_bridge_overlay_count": 0,
		"visible_wall_base_count": 0,
		"visible_wall_front_count": 0,
		"visible_wall_shadow_count": 0,
		"visible_static_other_count": 0,
		"static_chunk_count": 0,
		"visible_static_chunk_count": 0,
		"visible_wall_composite_count": 0,
	}
	# Texture diversity of visible items; the renderer can only batch items
	# that share a texture, so unique counts bound the best-case batching.
	counts["visible_unique_texture_ids"] = {}
	counts["visible_unique_wall_texture_ids"] = {}
	if background == null or not is_instance_valid(background):
		return counts
	var commands: Array = background.get("_editor_runtime_bridge_commands")
	if commands != null:
		counts["logical_total"] = commands.size()
		for command: Dictionary in commands:
			if str(command.get("render_domain", "")) == (
				GEOMETRY_SERVICE.RENDER_DOMAIN_ACTOR_Y_SORT
			):
				counts["logical_y_sort"] += 1
			else:
				counts["logical_static"] += 1
	var root := scan_root if scan_root != null else get_parent()
	var viewport_rect := get_viewport().get_visible_rect()
	_scan_tree(root, viewport_rect, counts, false)
	counts["visible_unique_texture_count"] = (
		counts["visible_unique_texture_ids"].size()
	)
	counts["visible_unique_wall_texture_count"] = (
		counts["visible_unique_wall_texture_ids"].size()
	)
	counts.erase("visible_unique_texture_ids")
	counts.erase("visible_unique_wall_texture_ids")
	return counts


func _scan_tree(
	node: Node,
	viewport_rect: Rect2,
	counts: Dictionary,
	inside_wrapper: bool
) -> void:
	for child: Node in node.get_children():
		if child.has_meta("editor_runtime_actor_occluder"):
			counts["wrapper_count"] += 1
			var overlay_count := 0
			var dynamic_children := 0
			var any_visible := false
			for sprite: Node in child.get_children():
				if sprite.has_meta("static_authored_wall_bridge"):
					overlay_count += 1
					if sprite is CanvasItem and _item_visible(
						sprite, viewport_rect
					):
						any_visible = true
						counts["visible_bridge_overlay_count"] += 1
						_track_texture(sprite, counts, false)
				else:
					# Pure dynamic children: base/front only, no bridge.
					dynamic_children += 1
					if sprite.get_meta("editor_runtime_wall_composite", false):
						if sprite is CanvasItem and _item_visible(
							sprite, viewport_rect
						):
							any_visible = true
							counts["visible_wall_composite_count"] += 1
							_track_texture(sprite, counts, true)
					elif sprite is CanvasItem and _item_visible(
						sprite, viewport_rect
					):
						any_visible = true
						var pass_index := int(
							sprite.get_meta("editor_runtime_image_pass", -1)
						)
						if pass_index == 1:
							counts["visible_wall_base_count"] += 1
						elif pass_index == 2:
							counts["visible_wall_front_count"] += 1
						_track_texture(sprite, counts, true)
			counts["bridge_overlay_count"] += overlay_count
			counts["wrapper_dynamic_children"] += dynamic_children
			if any_visible:
				counts["visible_wrappers"] += 1
				counts["visible_dynamic_children"] += dynamic_children
			_scan_tree(child, viewport_rect, counts, true)
		elif not inside_wrapper and child.has_meta("wall_static_chunk"):
			counts["static_chunk_count"] += 1
			if child is CanvasItem and _item_visible(child, viewport_rect):
				counts["visible_static_chunk_count"] += 1
				_track_texture(child, counts, false)
			_scan_tree(child, viewport_rect, counts, false)
		elif not inside_wrapper and child.has_meta("editor_runtime_instance"):
			counts["static_sprite_count"] += 1
			var is_wall_shadow: bool = (
				child.get_meta("editor_runtime_wall_asset", false)
				and int(child.get_meta("editor_runtime_image_pass", -1)) == 0
			)
			if is_wall_shadow:
				counts["static_wall_shadow_count"] += 1
			else:
				counts["static_other_count"] += 1
			if child is CanvasItem and _item_visible(child, viewport_rect):
				if is_wall_shadow:
					counts["visible_wall_shadow_count"] += 1
				else:
					counts["visible_static_other_count"] += 1
				_track_texture(child, counts, is_wall_shadow)
			_scan_tree(child, viewport_rect, counts, false)
		else:
			_scan_tree(child, viewport_rect, counts, inside_wrapper)


func _track_texture(item: Node, counts: Dictionary, wall: bool) -> void:
	if item is Sprite2D and (item as Sprite2D).texture != null:
		var id: int = (item as Sprite2D).texture.get_instance_id()
		counts["visible_unique_texture_ids"][id] = true
		if wall:
			counts["visible_unique_wall_texture_ids"][id] = true


func _item_visible(item: CanvasItem, viewport_rect: Rect2) -> bool:
	if not item.is_visible_in_tree():
		return false
	var canvas_transform := item.get_global_transform_with_canvas()
	if item is Sprite2D:
		var rect: Rect2 = canvas_transform * (item as Sprite2D).get_rect()
		return rect.intersects(viewport_rect)
	if item.has_meta("physical_draw_bounds"):
		# Collapsed segment canvas: bounds recorded by the physical planner.
		var bounds: Rect2 = item.get_meta("physical_draw_bounds")
		var rect: Rect2 = canvas_transform * bounds
		return rect.intersects(viewport_rect)
	return true


func _write_outputs(json: String) -> void:
	var stamp := str(Time.get_unix_time_from_system()).replace(".", "_")
	var safe_label := _window_label.replace("/", "_").replace(" ", "_")
	var file_name := "wallperf_%s_%s.json" % [safe_label, stamp]
	DirAccess.make_dir_recursive_absolute(OUTPUT_USER_DIR)
	var user_file := FileAccess.open(
		"%s/%s" % [OUTPUT_USER_DIR, file_name], FileAccess.WRITE
	)
	if user_file != null:
		user_file.store_string(json + "\n")
		user_file.close()
	var local_dir := ProjectSettings.globalize_path(OUTPUT_LOCAL_DIR)
	if DirAccess.dir_exists_absolute(local_dir.get_base_dir()) or (
		DirAccess.make_dir_recursive_absolute(local_dir) == OK
	):
		var local_file := FileAccess.open(
			"%s/%s" % [OUTPUT_LOCAL_DIR, file_name], FileAccess.WRITE
		)
		if local_file != null:
			local_file.store_string(json + "\n")
			local_file.close()
