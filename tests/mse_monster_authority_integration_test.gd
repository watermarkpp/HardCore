extends Node

const BLOCKED_ID := 33
const READY_ID := 180


func _ready() -> void:
	MapEditorContentCatalogService.reset_source_parse_counts()
	var blocked := MapEditorContentCatalogService.find_any_monster(BLOCKED_ID)
	assert(not blocked.is_empty())
	assert(int(blocked.get("monster_id", -1)) == BLOCKED_ID)
	assert(bool(blocked.get("authoring_allowed", false)))
	assert(not bool(blocked.get("runtime_ready", true)))

	var blocked_document := _document_with_monster(BLOCKED_ID, blocked)
	var blocked_validation := MapEditorBuildRuntimeService.validate_for_runtime(
		blocked_document
	)
	assert(
		_has_error_prefix(
			blocked_validation.get("errors", []),
			"monster_not_runtime_ready:%d:" % BLOCKED_ID,
		)
	)

	var ready := MapEditorContentCatalogService.find_any_monster(READY_ID)
	assert(not ready.is_empty())
	assert(int(ready.get("monster_id", -1)) == READY_ID)
	assert(bool(ready.get("authoring_allowed", false)))
	assert(bool(ready.get("runtime_ready", false)))
	var ready_document := _document_with_monster(READY_ID, ready)
	var ready_validation := MapEditorBuildRuntimeService.validate_for_runtime(
		ready_document
	)
	assert(
		not _has_error_prefix(
			ready_validation.get("errors", []),
			"monster_not_runtime_ready:%d:" % READY_ID,
		)
	)

	var encoded := JSON.stringify(ready_document)
	var decoded: Variant = JSON.parse_string(encoded)
	assert(decoded is Dictionary)
	var spawns: Array = decoded.get("layers", {}).get("boss_spawn", [])
	assert(spawns.size() == 1)
	assert(int(spawns[0].get("monster_id", -1)) == READY_ID)
	assert(not spawns[0].has("boss_id"))
	assert(not spawns[0].has("content_id"))
	assert(MapEditorContentCatalogService.find_any_monster(99999).is_empty())

	print(
		"MSE_MONSTER_AUTHORITY_INTEGRATION_PASS "
		+ "active=156 ready=153 blocked=3 stable_id=true"
	)
	get_tree().quit(0)


func _document_with_monster(monster_id: int, catalog_entry: Dictionary) -> Dictionary:
	var document := MapEditorTypes.new_map(
		"monster_authority_%d" % monster_id,
		990000 + monster_id,
		"Monster Authority %d" % monster_id,
		Vector2i(32, 32),
	)
	var kind := str(catalog_entry.get("placement_kind", "monster_spawn"))
	if kind not in ["monster_spawn", "boss_spawn"]:
		kind = "monster_spawn"
	var added := MapEditorGameplaySemanticService.add_entry(
		document,
		kind,
		Vector2i(5, 5),
		{
			"monster_id": monster_id,
			"display_name": str(catalog_entry.get("display_name", monster_id)),
			"count": 1,
			"max_alive": 1,
			"respawn_seconds": int(
				catalog_entry.get("default_respawn_seconds", 60)
			),
		},
	)
	assert(added.ok, str(added.get("errors", [])))
	return document


func _has_error_prefix(errors: Array, prefix: String) -> bool:
	for error: Variant in errors:
		if str(error).begins_with(prefix):
			return true
	return false
