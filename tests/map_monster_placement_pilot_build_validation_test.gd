extends Node

const BuildService := preload("res://scripts/map_editor/map_editor_build_runtime_service.gd")
const EXPECTED_ORDINARY_IDS := [112, 126, 128, 129, 132, 138, 148, 150, 153, 156]
const EXPECTED_BOSS_IDS := [135, 141, 152, 155, 158]


func _ready() -> void:
	var source_path := OS.get_environment("HARDCORE_MAP_MONSTER_PILOT_CANDIDATE")
	var expected_map_id := OS.get_environment("HARDCORE_MAP_MONSTER_PILOT_MAP_ID")
	assert(not source_path.is_empty(), "pilot candidate path environment is required")
	assert(not expected_map_id.is_empty(), "pilot map id environment is required")
	var document := _read_json(source_path)
	assert(not document.is_empty(), "pilot candidate must load: %s" % source_path)
	assert(str(document.get("map_id", "")) == expected_map_id)
	var candidate := BuildService.build_formal_candidate(document)
	assert(bool(candidate.get("ok", false)), str(candidate.get("errors", [])))
	var runtime: Dictionary = candidate.get("runtime", {})
	var semantics: Dictionary = runtime.get("semantics", {})
	var ordinary: Array = semantics.get("monster_spawn", [])
	var bosses: Array = semantics.get("boss_spawn", [])
	assert(ordinary.size() == 10, "pilot ordinary spawn count must remain 10")
	assert(bosses.size() == 5, "pilot boss/elite spawn count must remain 5")
	_assert_spawn_identity(ordinary, "monster_spawn")
	_assert_spawn_identity(bosses, "boss_spawn")
	assert(_sorted_monster_ids(ordinary) == EXPECTED_ORDINARY_IDS)
	assert(_sorted_monster_ids(bosses) == EXPECTED_BOSS_IDS)
	assert(not str(candidate.get("build_sha256", "")).is_empty())
	print(
		"MAP_MONSTER_PLACEMENT_PILOT_BUILD_VALIDATION_PASS map=%s ordinary=%d boss=%d"
		% [expected_map_id, ordinary.size(), bosses.size()]
	)
	get_tree().quit(0)


func _assert_spawn_identity(entries: Array, expected_kind: String) -> void:
	var semantic_ids := {}
	var group_ids := {}
	for raw_entry: Variant in entries:
		assert(raw_entry is Dictionary)
		var entry: Dictionary = raw_entry
		assert(int(entry.get("monster_id", -1)) > 0)
		assert(str(entry.get("kind", "")) == expected_kind)
		var semantic_id := str(entry.get("semantic_id", "")).strip_edges()
		var group_id := str(entry.get("spawn_group_id", "")).strip_edges()
		assert(not semantic_id.is_empty())
		assert(not group_id.is_empty())
		assert(not semantic_ids.has(semantic_id), "duplicate semantic_id: %s" % semantic_id)
		assert(not group_ids.has(group_id), "duplicate spawn_group_id: %s" % group_id)
		semantic_ids[semantic_id] = true
		group_ids[group_id] = true


func _sorted_monster_ids(entries: Array) -> Array:
	var ids: Array = []
	for entry: Dictionary in entries:
		ids.append(int(entry.get("monster_id", -1)))
	ids.sort()
	return ids


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
