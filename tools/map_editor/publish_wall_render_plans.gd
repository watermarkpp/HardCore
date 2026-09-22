extends SceneTree
## CLI entry for the same derived-wall publisher used by the map editor.
const Publisher := preload("res://scripts/map_editor/map_editor_wall_render_publish_service.gd")
const DEFAULT_MAPS := "mengzhong_dark_area,chiyue_valley"

func _init() -> void:
	var maps := DEFAULT_MAPS.split(",", false)
	if OS.get_environment("WALL_RENDER_MAPS") != "":
		maps = OS.get_environment("WALL_RENDER_MAPS").split(",", false)
	var publisher := Publisher.new()
	var failures: PackedStringArray = []
	var report_rows: Array = []
	for map_key: String in maps:
		var row := publisher.publish_map(map_key.strip_edges())
		if row.has("error"):
			failures.append("%s: %s" % [map_key, str(row["error"])])
			continue
		report_rows.append(row)
	var report := {
		"contract_id": "hardcore.wall_render_memory_report.v1",
		"rows": report_rows,
	}
	var report_path := "res://outputs/wall_perf/wall_render_memory_report.json"
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://outputs/wall_perf")
	)
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.close()
	print("PUBREPORT_TABLE")
	print("map | atlas_pages | atlas_pixels | atlas_rgba8_mib | static_chunks_before | static_chunks_after | chunk_rgba8_mib_after_trim | png_disk_mib | legacy_commands")
	for row: Dictionary in report_rows:
		print("%s | %d | %d | %.2f | %d | %d | %.2f | %.2f | %d" % [
			row["map"], row["atlas_pages"], row["atlas_pixels"],
			row["atlas_rgba8_mib"], row["chunk_pixels_before_trim"],
			row["chunk_pixels_after_trim"], row["chunk_rgba8_mib_after_trim"],
			row["png_disk_mib"], row["legacy_commands"],
		])
	if failures.is_empty():
		print("PUBRESULT PASS")
		quit(0)
	else:
		for failure: String in failures:
			print("PUBFAIL ", failure)
		print("PUBRESULT FAIL")
		quit(1)
