extends RefCounted

## WALL-P1R rollout classification authority (R4-0).
## Single source: release registry -> runtime design -> sorted_draw_commands
## -> compile_plan -> atlas_command_indices. A: atlas_commands > 0,
## B: atlas_commands == 0, C: any design/compile blocker. No outputs/ or
## hand-maintained list dependencies; every tool (census, store GC, R4/R6
## gates) rebuilds classification through this helper in-process.

const BRIDGE := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)
const GEOMETRY_SERVICE := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)
const COMPILER := preload(
	"res://scripts/map_editor/map_editor_wall_render_compiler.gd"
)


static func _image_size(path: String) -> Vector2i:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null:
		return Vector2i.ZERO
	return Vector2i(image.get_width(), image.get_height())


## Returns {rows: Array[Dictionary], a_keys: PackedStringArray}. Each row:
## {map_id, map_key, class, error?, atlas_commands?}. Hard-asserts the
## rollout contract 67/60/7/0 and returns "" via error on any drift.
static func classify() -> Dictionary:
	var rows: Array = []
	var a_keys := PackedStringArray()
	var map_ids := BRIDGE.released_map_ids()
	map_ids.sort()
	for map_id: int in map_ids:
		var runtime_path := str(BRIDGE.runtime_path(map_id))
		if runtime_path.is_empty() or not BRIDGE.has_runtime_map(map_id):
			rows.append({"map_id": map_id, "class": "C", "error": "no runtime path"})
			continue
		var map_key := runtime_path.get_file().replace(".runtime.json", "")
		var raw: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(runtime_path)
		)
		if raw is not Dictionary:
			rows.append({"map_id": map_id, "map_key": map_key, "class": "C", "error": "runtime json unparsable"})
			continue
		var design_container: Dictionary = raw.get("design", {})
		var design_raw: Array = design_container.get("design_size", [])
		if design_raw.size() != 2 or int(design_raw[0]) <= 0 or int(design_raw[1]) <= 0:
			rows.append({"map_id": map_id, "map_key": map_key, "class": "C", "error": "design_size missing/malformed"})
			continue
		var design_size := Vector2i(int(design_raw[0]), int(design_raw[1]))
		var commands: Array = GEOMETRY_SERVICE.sorted_draw_commands(
			raw.get("instances", [])
		)
		var plan: Dictionary = COMPILER.compile_plan(
			commands, design_size, _image_size
		)
		if bool(plan.get("contract_violation", false)) or plan.has("error"):
			rows.append({
				"map_id": map_id, "map_key": map_key, "class": "C",
				"error": str(plan.get("error", "compiler contract violation")),
			})
			continue
		var atlas_commands: int = plan.get("atlas_command_indices", []).size()
		if atlas_commands == 0:
			rows.append({"map_id": map_id, "map_key": map_key, "class": "B"})
			continue
		a_keys.append(map_key)
		rows.append({
			"map_id": map_id, "map_key": map_key, "class": "A",
			"atlas_commands": atlas_commands,
		})
	var counts := {"A": 0, "B": 0, "C": 0}
	for row: Dictionary in rows:
		counts[str(row["class"])] = int(counts[str(row["class"])]) + 1
	var error := ""
	if (
		map_ids.size() != 67 or counts["A"] != 60 or counts["B"] != 7
		or counts["C"] != 0
	):
		error = "classification drift: released=%d A=%d B=%d C=%d" % [
			map_ids.size(), counts["A"], counts["B"], counts["C"],
		]
	return {"rows": rows, "a_keys": a_keys, "counts": counts, "error": error}
