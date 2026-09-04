extends Node

const TARGET_EDITOR := "res://map_editor_workspace/world_bich_province/world_bich_province.editor.json"
const TARGET_RUNTIME := "res://assets/data/runtime/map_editor/world_bich_province.runtime.json"
const TARGET_MAP := "world_bich_province"
const SpawnIdentity := preload(
	"res://scripts/map_editor/map_editor_spawn_identity_service.gd"
)
const BuildService := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)
const JsonCodec := preload("res://scripts/map_editor/map_editor_json_codec.gd")
const FORMAL_RUNTIME_TARGETS := {
	"world_bich_province": Vector2i(82, 0),
	"world_cangyue_island": Vector2i(37, 0),
	"world_wooma_forest": Vector2i(50, 4),
	"bich_orc_tomb_f1": Vector2i(40, 0),
}


func _ready() -> void:
	_test_target_editor_contract()
	_test_target_runtime_contract()
	_test_repaired_formal_runtime_contracts()
	_test_workspace_identity_audit()
	_test_new_and_copied_spawn_identities()
	_test_missing_and_duplicate_fail_closed()
	print(
		"WORLD_BICH_SPAWN_IDENTITY_CONTRACT_PASS "
		+ "workspace_maps=132 formal_runtime_maps=4 "
		+ "target_monster_spawn=82 target_boss_spawn=0 "
		+ "new_and_copy=unique save_build_publish=fail_closed"
	)
	get_tree().quit(0)


func _test_target_editor_contract() -> void:
	var document := _read_json(TARGET_EDITOR)
	assert(str(document.get("map_id", "")) == TARGET_MAP)
	var monsters: Array = document.get("layers", {}).get("monster_spawn", [])
	var bosses: Array = document.get("layers", {}).get("boss_spawn", [])
	assert(monsters.size() == 82, "target ordinary count changed")
	assert(bosses.size() == 0, "target boss count changed")
	var errors := SpawnIdentity.validate_document(document, true)
	assert(errors.is_empty(), "target editor identity invalid: %s" % str(errors))
	for index in monsters.size():
		var entry: Dictionary = monsters[index]
		var expected_semantic := SpawnIdentity.semantic_id_for(
			TARGET_MAP, "monster_spawn", index + 1
		)
		var expected_group := "%s%s" % [
			SpawnIdentity.FORMAL_GROUP_PREFIX,
			expected_semantic.trim_prefix(SpawnIdentity.FORMAL_SEMANTIC_PREFIX),
		]
		assert(str(entry.get("semantic_id", "")) == expected_semantic)
		assert(str(entry.get("spawn_group_id", "")) == expected_group)
	assert(
		str(monsters[0].get("semantic_id", ""))
			== "mse.placement.v1.world_bich_province.monster_spawn.000001"
	)
	assert(
		str(monsters[39].get("spawn_group_id", ""))
			== "mse.group.v1.world_bich_province.monster_spawn.000040"
	)
	assert(
		str(monsters[40].get("semantic_id", ""))
			== "mse.placement.v1.world_bich_province.monster_spawn.000041"
	)
	assert(
		str(monsters[81].get("spawn_group_id", ""))
			== "mse.group.v1.world_bich_province.monster_spawn.000082"
	)


func _test_target_runtime_contract() -> void:
	var runtime := _read_json(TARGET_RUNTIME)
	var errors := SpawnIdentity.validate_runtime(runtime, true)
	assert(errors.is_empty(), "target runtime identity invalid: %s" % str(errors))
	var semantics: Dictionary = runtime.get("semantics", {})
	assert((semantics.get("monster_spawn", []) as Array).size() == 82)
	assert((semantics.get("boss_spawn", []) as Array).size() == 0)


func _test_repaired_formal_runtime_contracts() -> void:
	for map_key: String in FORMAL_RUNTIME_TARGETS:
		var runtime_path := (
			"res://assets/data/runtime/map_editor/%s.runtime.json" % map_key
		)
		var runtime := _read_json(runtime_path)
		var errors := SpawnIdentity.validate_runtime(runtime, true)
		assert(errors.is_empty(), "%s runtime identity invalid: %s" % [map_key, str(errors)])
		var semantics: Dictionary = runtime.get("semantics", {})
		var expected: Vector2i = FORMAL_RUNTIME_TARGETS[map_key]
		assert((semantics.get("monster_spawn", []) as Array).size() == expected.x)
		assert((semantics.get("boss_spawn", []) as Array).size() == expected.y)


func _test_workspace_identity_audit() -> void:
	var root := DirAccess.open("res://map_editor_workspace")
	assert(root != null, "map editor workspace missing")
	var audited := 0
	for directory: String in root.get_directories():
		var map_path := "res://map_editor_workspace/%s/%s.editor.json" % [directory, directory]
		if not FileAccess.file_exists(map_path):
			continue
		var document := _read_json(map_path)
		audited += 1
		var map_key := str(document.get("map_id", ""))
		assert(map_key == directory, "workspace map identity mismatch: %s" % map_path)
		var errors := SpawnIdentity.validate_document(
			document,
			SpawnIdentity.requires_formal_semantic_ids(document)
		)
		assert(errors.is_empty(), "%s spawn identity invalid: %s" % [map_key, str(errors)])
	assert(audited == 132, "workspace map count changed: %d" % audited)


func _test_new_and_copied_spawn_identities() -> void:
	var document := MapEditorTypes.new_map(
		"identity_generation_test", 990881, "Identity Generation", Vector2i(32, 32)
	)
	var ordinary := MapEditorGameplaySemanticService.add_entry(
		document,
		"monster_spawn",
		Vector2i(4, 4),
		{"monster_id": 18, "count": 1, "max_alive": 1, "respawn_seconds": 60}
	)
	assert(bool(ordinary.get("ok", false)), str(ordinary.get("errors", [])))
	assert(
		str(ordinary.entry.get("semantic_id", ""))
			== "mse.placement.v1.identity_generation_test.monster_spawn.000001"
	)
	assert(
		str(ordinary.entry.get("spawn_group_id", ""))
			== "mse.group.v1.identity_generation_test.monster_spawn.000001"
	)
	var copied := MapEditorGameplaySemanticService.duplicate_entry_snapshot(
		document, ordinary.entry, Vector2i(8, 9)
	)
	assert(bool(copied.get("ok", false)), str(copied.get("errors", [])))
	assert(
		str(copied.entry.get("semantic_id", ""))
			== "mse.placement.v1.identity_generation_test.monster_spawn.000002"
	)
	assert(
		str(copied.entry.get("spawn_group_id", ""))
			== "mse.group.v1.identity_generation_test.monster_spawn.000002"
	)
	assert(
		str(copied.entry.get("spawn_group_id", ""))
			!= str(ordinary.entry.get("spawn_group_id", ""))
	)
	var boss := MapEditorGameplaySemanticService.add_entry(
		document,
		"boss_spawn",
		Vector2i(12, 12),
		{"monster_id": 76, "count": 1, "max_alive": 1, "respawn_seconds": 1800}
	)
	assert(bool(boss.get("ok", false)), str(boss.get("errors", [])))
	assert(str(boss.entry.get("semantic_id", "")).contains("boss_spawn.000001"))
	assert(str(boss.entry.get("spawn_group_id", "")).contains("boss_spawn.000001"))
	var copied_boss := MapEditorGameplaySemanticService.duplicate_entry_snapshot(
		document, boss.entry, Vector2i(14, 14)
	)
	assert(bool(copied_boss.get("ok", false)), str(copied_boss.get("errors", [])))
	assert(str(copied_boss.entry.get("semantic_id", "")).ends_with("boss_spawn.000002"))
	assert(str(copied_boss.entry.get("spawn_group_id", "")).ends_with("boss_spawn.000002"))
	assert(
		str(copied_boss.entry.get("spawn_group_id", ""))
			!= str(boss.entry.get("spawn_group_id", ""))
	)

	# Reordering the existing rows must not change the next serial.
	var reordered := document.duplicate(true)
	var reordered_rows: Array = reordered.layers.monster_spawn.duplicate(true)
	reordered_rows.reverse()
	reordered.layers.monster_spawn = reordered_rows
	var after_reorder := MapEditorGameplaySemanticService.add_entry(
		reordered,
		"monster_spawn",
		Vector2i(16, 16),
		{"monster_id": 18, "count": 1, "max_alive": 1, "respawn_seconds": 60}
	)
	assert(bool(after_reorder.get("ok", false)), str(after_reorder.get("errors", [])))
	assert(str(after_reorder.entry.get("semantic_id", "")).ends_with("monster_spawn.000003"))
	assert(SpawnIdentity.validate_document(document).is_empty())


func _test_missing_and_duplicate_fail_closed() -> void:
	var document := _read_json(TARGET_EDITOR)
	var missing := document.duplicate(true)
	missing.layers.monster_spawn[0].erase("spawn_group_id")
	var missing_errors := SpawnIdentity.validate_document(missing, true)
	assert(_has_prefix(missing_errors, "spawn_group_id_missing:"))
	var duplicate := document.duplicate(true)
	duplicate.layers.monster_spawn[1].spawn_group_id = duplicate.layers.monster_spawn[0].spawn_group_id
	var duplicate_errors := SpawnIdentity.validate_document(duplicate, true)
	assert(_has_prefix(duplicate_errors, "duplicate_spawn_group_id:"))
	var missing_runtime_validation := BuildService.validate_for_runtime(missing)
	assert(
		_has_prefix(
			missing_runtime_validation.get("errors", []),
			"spawn_group_id_missing:"
		),
		"build validator must reject missing group"
	)
	var duplicate_runtime_validation := BuildService.validate_for_runtime(duplicate)
	assert(
		_has_prefix(
			duplicate_runtime_validation.get("errors", []),
			"duplicate_spawn_group_id:"
		),
		"build validator must reject duplicate group"
	)
	var save_path := "user://world_bich_spawn_identity_fail_closed.editor.json"
	var saved := MapEditorSaveService.save_document(missing, save_path)
	assert(not bool(saved.get("ok", false)), "missing group must block save")
	assert(_has_prefix(saved.get("errors", []), "spawn_group_id_missing:"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var duplicate_save_path := "user://world_bich_spawn_identity_duplicate.editor.json"
	var duplicate_saved := MapEditorSaveService.save_document(duplicate, duplicate_save_path)
	assert(not bool(duplicate_saved.get("ok", false)), "duplicate group must block save")
	assert(_has_prefix(duplicate_saved.get("errors", []), "duplicate_spawn_group_id:"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(duplicate_save_path))

	var invalid_runtime := _read_json(TARGET_RUNTIME)
	var invalid_spawns: Array = invalid_runtime.get("semantics", {}).get("monster_spawn", [])
	invalid_spawns[1]["spawn_group_id"] = invalid_spawns[0].get("spawn_group_id", "")
	invalid_runtime["build_sha256"] = ""
	invalid_runtime["build_sha256"] = BuildService._sha256(JsonCodec.encode(invalid_runtime))
	var invalid_runtime_path := "user://world_bich_spawn_identity_fail_closed.runtime.json"
	var runtime_file := FileAccess.open(invalid_runtime_path, FileAccess.WRITE)
	assert(runtime_file != null, "invalid runtime fixture open failed")
	runtime_file.store_string(JsonCodec.encode(invalid_runtime))
	runtime_file.close()
	var published := BuildService.publish_runtime_release(
		invalid_runtime_path,
		910001,
		{},
		"res://assets/data/runtime/map_editor/map_runtime_release_registry.json",
		TARGET_MAP
	)
	assert(
		str(published.get("reason", "")) == "runtime_spawn_identity_invalid",
		"publisher must reject duplicate group: %s" % str(published)
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(invalid_runtime_path))


func _has_prefix(values: Variant, prefix: String) -> bool:
	if not values is Array:
		return false
	for value: Variant in values:
		if str(value).begins_with(prefix):
			return true
	return false


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "missing JSON: %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	assert(parsed is Dictionary, "invalid JSON object: %s" % path)
	return parsed
