extends Node

const BuildService := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)
const JsonCodec := preload(
	"res://scripts/map_editor/map_editor_json_codec.gd"
)

const LEGACY_MAP_ID := "gmhl_purgatory_corridor"
const FORMAL_MAP_ID := "fengmo_purgatory_corridor"
const FORMAL_RUNTIME_MAP_ID := 914007


func _ready() -> void:
	var source_path := OS.get_environment(
		"HARDCORE_MAP_MONSTER_PILOT_CANDIDATE"
	)
	assert(not source_path.is_empty(), "pilot candidate path environment is required")
	var source_bytes := _read_text(source_path)
	var document := _read_json(source_path)
	assert(not document.is_empty(), "pilot candidate must load: %s" % source_path)
	assert(str(document.get("map_id", "")) == LEGACY_MAP_ID)
	assert(int(document.get("schema_version", -1)) == 4)
	var document_before := JsonCodec.encode(document)
	var candidate := BuildService.build_formal_candidate(document)
	assert(bool(candidate.get("ok", false)), str(candidate.get("errors", [])))
	assert(str(candidate.get("map_key", "")) == FORMAL_MAP_ID)
	assert(int(candidate.runtime.source.runtime_map_id) == FORMAL_RUNTIME_MAP_ID)
	assert(int(candidate.runtime.source.editor_schema_version) == 5)
	assert(bool(candidate.get("formal_authority_composed", false)))
	var semantics: Dictionary = candidate.runtime.semantics
	var ordinary: Array = semantics.get("monster_spawn", [])
	var bosses: Array = semantics.get("boss_spawn", [])
	assert(ordinary.size() == 9)
	assert(bosses.size() == 2)
	_assert_spawn_identity(ordinary, "monster_spawn")
	_assert_spawn_identity(bosses, "boss_spawn")
	assert(BuildService.candidate_matches_document(candidate, document))
	assert(JsonCodec.encode(document) == document_before)
	assert(_read_text(source_path) == source_bytes)
	assert(
		str(candidate.candidate_path).begins_with(
			"res://outputs/map_runtime_candidates/"
		)
	)
	assert(not str(candidate.candidate_path).begins_with(BuildService.RUNTIME_ROOT))
	print(
		"MAP_MONSTER_PLACEMENT_FORMAL_PILOT_BUILD_PASS "
		+ "map=%s runtime=%d ordinary=%d boss=%d hash=%s"
		% [
			FORMAL_MAP_ID,
			FORMAL_RUNTIME_MAP_ID,
			ordinary.size(),
			bosses.size(),
			candidate.build_sha256,
		]
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
		assert(not semantic_ids.has(semantic_id))
		assert(not group_ids.has(group_id))
		semantic_ids[semantic_id] = true
		group_ids[group_id] = true


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read_text(path))
	return parsed if parsed is Dictionary else {}
