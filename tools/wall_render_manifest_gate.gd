extends Node

## WALL-P1R R5-12 cross-check: the static unique-path memory model must
## match the live consumer manifest. For three probe maps (dark, chiyue,
## memory-max), run the real prepare_map_build() on a real
## WorldBackground + fresh coordinator and count resource_manifest
## entries whose owners include wall_render_derived; compare with the
## R5 audit report's unique_derived_resource_count.
## Usage:
##   godot --headless --path . res://tools/wall_render_manifest_gate.tscn

const AUTHORITY := preload("res://tools/wall_rollout_authority.gd")
const WB_SCRIPT := preload("res://scripts/world_background.gd")
const COORD_SCRIPT := preload("res://scripts/world_bootstrap_coordinator.gd")

const PROBE := ["mengzhong_dark_area", "chiyue_valley"]


func _ready() -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://outputs/wall_perf/wall_render_r5_memory_report.json"
	))
	var expected := {}
	var max_key := ""
	var max_px := 0
	for row: Dictionary in report["rows"]:
		if str(row.get("class", "")) != "A":
			continue
		expected[str(row["map_key"])] = int(
			row["unique_derived_resource_count"]
		)
		if int(row["unique_derived_pixels"]) > max_px:
			max_px = int(row["unique_derived_pixels"])
			max_key = str(row["map_key"])
	var id_by_key := {}
	for row: Dictionary in AUTHORITY.classify()["rows"]:
		id_by_key[str(row["map_key"])] = int(row["map_id"])
	var targets: Array = [
		{"key": "mengzhong_dark_area",
			"id": int(id_by_key["mengzhong_dark_area"])},
		{"key": "chiyue_valley",
			"id": int(id_by_key["chiyue_valley"])},
	]
	if max_key != "" and max_key != "mengzhong_dark_area" \
			and max_key != "chiyue_valley":
		targets.append({"key": max_key, "id": int(id_by_key[max_key])})
	var background := WB_SCRIPT.new()
	# Skip the _ready() legacy full rebuild (same protocol as the C9 test):
	# the probe only needs prepare_map_build's manifest side effects.
	background.defer_initial_legacy_build_to_coordinator()
	add_child(background)
	var failures := 0
	for target: Dictionary in targets:
		var map_key: String = target["key"]
		var coord = COORD_SCRIPT.new()
		var map_data: Dictionary = GameData.get_map_by_id(int(target["id"]))
		background.prepare_map_build(int(target["id"]), coord, map_data)
		var counted := 0
		for path: Variant in coord.resource_manifest:
			var entry: Dictionary = coord.resource_manifest[path]
			if (entry.get("owners", []) as Array).has("wall_render_derived"):
				counted += 1
		var want: int = expected.get(map_key, -1)
		var ok := counted == want
		if not ok:
			failures += 1
		print("R5_PROBE %s manifest=%d audit=%d match=%s" % [
			map_key, counted, want, str(ok),
		])
	print("WALL_RENDER_R5_MANIFEST_PROBE_%s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)
