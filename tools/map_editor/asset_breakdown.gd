extends SceneTree

## Per-asset draw-command breakdown for two maps that share a copy lineage.

const RUNTIMES := [
	"res://assets/data/runtime/map_editor/bich_mine_f1.runtime.json",
	"res://assets/data/runtime/map_editor/mengzhong_death_valley_dungeon.runtime.json",
]


func _init() -> void:
	for path: String in RUNTIMES:
		_breakdown(path)
	print("ASSET_BREAKDOWN_DONE")
	quit(0)


func _breakdown(path: String) -> void:
	var runtime: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(path)
	)
	var map_key := str(runtime.get("map_id", path.get_file()))
	var commands := MapEditorRuntimeVisualGeometryService.sorted_draw_commands(
		runtime.get("instances", [])
	)
	var per_asset := {}
	for command: Dictionary in commands:
		var asset_id := str(command.get("instance", {}).get("asset_id", "?"))
		if not per_asset.has(asset_id):
			per_asset[asset_id] = {"instances": {}, "commands": 0}
		per_asset[asset_id]["commands"] = int(per_asset[asset_id]["commands"]) + 1
		per_asset[asset_id]["instances"][str(command.get(
			"instance", {}
		).get("instance_id", ""))] = true
	var rows: Array[Dictionary] = []
	var total := 0
	for asset_id: String in per_asset:
		var record: Dictionary = per_asset[asset_id]
		var instance_count := (record["instances"] as Dictionary).size()
		rows.append({
			"asset": asset_id,
			"instances": instance_count,
			"commands": int(record["commands"]),
			"commands_per_instance": snappedf(
				float(record["commands"]) / float(maxi(1, instance_count)),
				0.1
			),
		})
		total += int(record["commands"])
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["commands"]) > int(b["commands"])
	)
	print("ASSET_BREAKDOWN map=%s total_commands=%d distinct_assets=%d" % [
		map_key, total, rows.size(),
	])
	for row: Dictionary in rows.slice(0, 8):
		print("ASSET_BREAKDOWN map=%s asset=%s instances=%d commands=%d per_instance=%s" % [
			map_key, str(row["asset"]), int(row["instances"]),
			int(row["commands"]), str(row["commands_per_instance"]),
		])
