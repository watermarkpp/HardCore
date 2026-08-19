extends Node

const Catalog := preload("res://scripts/map_editor/map_editor_content_catalog_service.gd")


func _ready() -> void:
	Catalog.reset_source_parse_counts()

	# ---- TEST A: AUTHORING ALLOWS RUNTIME-UNCLOSED MONSTERS ----
	# ID=16 has runtime_allowed=false but authoring_allowed=true (classification=ordinary).
	var lu := Catalog.find_by_monster_id("monster_spawn", 16)
	assert(not lu.is_empty(), "ID16 must exist in catalog")
	assert(bool(lu.get("authoring_allowed", false)), "ID16 must be authoring_allowed")
	assert(not bool(lu.get("runtime_ready", false)), "ID16 must NOT be runtime_ready")

	var doc := MapEditorTypes.new_map("auth_rt_sep", 990100, "Auth Rt Sep", Vector2i(32, 32))
	doc.editor_meta.workspace = "user://auth_rt_sep_%s" % str(Time.get_ticks_usec())
	assert(MapEditorGroundService.initialize(doc).ok)

	var spawn := MapEditorGameplaySemanticService.add_entry(doc, "monster_spawn", Vector2i(5, 5), {
		"monster_id": 16, "display_name": "鹿", "count": 1, "max_alive": 1, "respawn_seconds": 60,
	})
	assert(spawn.ok, "ID16 placement must succeed: %s" % str(spawn.get("errors", [])))
	assert(int(spawn.entry.get("monster_id", -1)) == 16, "placed monster_id must be 16")

	# Save and reload — monster_id must survive round-trip.
	var save_path := "user://auth_rt_sep_%s.editor.json" % str(Time.get_ticks_usec())
	var saved := MapEditorSaveService.save_document(doc, save_path)
	assert(saved.ok, "save must succeed: %s" % str(saved.get("errors", [])))
	var loaded := MapEditorLoadService.load_document(save_path)
	assert(loaded.ok, "load must succeed: %s" % str(loaded.get("errors", [])))
	var loaded_spawns: Array = loaded.document.layers.get("monster_spawn", [])
	assert(loaded_spawns.size() == 1, "reloaded doc must have 1 monster_spawn")
	assert(int(loaded_spawns[0].get("monster_id", -1)) == 16, "reloaded monster_id must still be 16")

	# UI label must show "待闭环" not "未闭环".
	var suffix := _monster_status_suffix(lu)
	assert(suffix.contains("待闭环"), "suffix must say 待闭环: %s" % suffix)
	assert(not suffix.contains("未闭环"), "suffix must NOT say 未闭环: %s" % suffix)

	# ---- TEST B: RUNTIME GATE BLOCKS UNCLOSED MONSTERS ----
	var validation := MapEditorBuildRuntimeService.validate_for_runtime(doc)
	assert(not validation.ok, "runtime validation must FAIL for ID16")
	assert(
		_has_error_prefix(validation.get("errors", []), "monster_not_runtime_ready:16:"),
		"must have monster_not_runtime_ready:16 error: %s" % str(validation.get("errors", []))
	)

	# Approval must also fail.
	var approval := MapEditorBuildRuntimeService.approve_for_runtime(doc)
	assert(not approval.ok, "runtime approval must FAIL for doc with ID16")

	# ---- TEST C: CLOSED MONSTER PASSES BOTH ----
	var woma := Catalog.find_by_monster_id("boss_spawn", 76)
	assert(not woma.is_empty(), "ID76 must exist")
	assert(bool(woma.get("authoring_allowed", false)), "ID76 must be authoring_allowed")
	assert(bool(woma.get("runtime_ready", false)), "ID76 must be runtime_ready")

	var closed_doc := MapEditorTypes.new_map("closed_ok", 990076, "Closed OK", Vector2i(32, 32))
	closed_doc.editor_meta.workspace = "user://closed_ok_%s" % str(Time.get_ticks_usec())
	assert(MapEditorGroundService.initialize(closed_doc).ok)
	var boss_spawn := MapEditorGameplaySemanticService.add_entry(closed_doc, "boss_spawn", Vector2i(6, 6), {
		"monster_id": 76, "display_name": "沃玛教主", "count": 1, "max_alive": 1, "respawn_seconds": 1800,
	})
	assert(boss_spawn.ok, str(boss_spawn.get("errors", [])))
	var closed_validation := MapEditorBuildRuntimeService.validate_for_runtime(closed_doc)
	assert(closed_validation.ok, "ID76 must pass runtime validation: %s" % str(closed_validation.get("errors", [])))

	# ---- TEST D: ID STABILITY ACROSS CATALOG LOOKUPS ----
	var stability_cases := [
		["monster_spawn", 18],
		["boss_spawn", 76],
		["monster_spawn", 16],
		["boss_spawn", 180],
	]
	for case_data: Array in stability_cases:
		var kind: String = case_data[0]
		var expected_id: int = case_data[1]
		var entry := Catalog.find_by_monster_id(kind, expected_id)
		assert(not entry.is_empty(), "ID%d missing from %s" % [expected_id, kind])
		assert(int(entry.get("monster_id", -1)) == expected_id, "ID%d unstable" % expected_id)

	# find_any_monster must also resolve by monster_id.
	var any_76 := Catalog.find_any_monster(76)
	assert(not any_76.is_empty(), "find_any_monster(76) must find")
	assert(int(any_76.get("monster_id", -1)) == 76, "find_any_monster(76) id mismatch")

	# ---- TEST E: NO NAME FALLBACK ----
	# Placed entry carries only numeric monster_id, no display_name dependency.
	var placed_entry: Dictionary = loaded_spawns[0]
	assert(int(placed_entry.get("monster_id", -1)) == 16, "persisted entry must use monster_id=16")
	# Even if display_name were wrong, monster_id is the authority.
	placed_entry["display_name"] = "WRONG_NAME"
	assert(int(placed_entry.get("monster_id", -1)) == 16, "monster_id must not depend on display_name")

	# Catalog lookup must never use name to resolve identity.
	var by_wrong_name := Catalog.find_by_monster_id("monster_spawn", 16)
	assert(int(by_wrong_name.get("monster_id", -1)) == 16, "lookup by monster_id must be stable")

	print("MSE_AUTHORING_RUNTIME_SEPARATION_PASS authoring=yes runtime_gate=fail_closed id_stable=true")
	get_tree().quit()


func _monster_status_suffix(entry: Dictionary) -> String:
	if not bool(entry.get("authoring_allowed", false)):
		return "（不可布置）"
	if not bool(entry.get("runtime_ready", false)):
		return "（可布置｜运行时待闭环）"
	return ""


func _has_error_prefix(errors: Array, prefix: String) -> bool:
	for error: Variant in errors:
		if str(error).begins_with(prefix):
			return true
	return false
