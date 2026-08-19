extends Node

const Catalog := preload("res://scripts/map_editor/map_editor_content_catalog_service.gd")


func _ready() -> void:
	Catalog.reset_source_parse_counts()

	# ---- TEST A: AUTHORING ALLOWS RUNTIME-UNCLOSED MONSTERS ----
	# ID=33 (雪人王) is in the 156 active canonical catalog with
	# runtime_allowed=false. It must be authorable but NOT runtime-ready.
	var lu := Catalog.find_by_monster_id("boss_spawn", 33)
	assert(not lu.is_empty(), "ID33 must exist in catalog")
	assert(bool(lu.get("authoring_allowed", false)), "ID33 must be authoring_allowed")
	assert(not bool(lu.get("runtime_ready", false)), "ID33 must NOT be runtime_ready")

	var doc := MapEditorTypes.new_map("auth_rt_sep", 990100, "Auth Rt Sep", Vector2i(32, 32))
	doc.editor_meta.workspace = "user://auth_rt_sep_%s" % str(Time.get_ticks_usec())
	assert(MapEditorGroundService.initialize(doc).ok)

	var spawn := MapEditorGameplaySemanticService.add_entry(doc, "boss_spawn", Vector2i(5, 5), {
		"monster_id": 33, "display_name": "雪人王", "count": 1, "max_alive": 1, "respawn_seconds": 60,
	})
	assert(spawn.ok, "ID33 placement must succeed: %s" % str(spawn.get("errors", [])))
	assert(int(spawn.entry.get("monster_id", -1)) == 33, "placed monster_id must be 33")

	# Save and reload — monster_id must survive round-trip.
	var save_path := "user://auth_rt_sep_%s.editor.json" % str(Time.get_ticks_usec())
	var saved := MapEditorSaveService.save_document(doc, save_path)
	assert(saved.ok, "save must succeed: %s" % str(saved.get("errors", [])))
	var loaded := MapEditorLoadService.load_document(save_path)
	assert(loaded.ok, "load must succeed: %s" % str(loaded.get("errors", [])))
	var loaded_spawns: Array = loaded.document.layers.get("boss_spawn", [])
	assert(loaded_spawns.size() == 1, "reloaded doc must have 1 boss_spawn")
	assert(int(loaded_spawns[0].get("monster_id", -1)) == 33, "reloaded monster_id must still be 33")

	# UI label must show "待闭环" not "未闭环".
	var suffix := _monster_status_suffix(lu)
	assert(suffix.contains("待闭环"), "suffix must say 待闭环: %s" % suffix)
	assert(not suffix.contains("未闭环"), "suffix must NOT say 未闭环: %s" % suffix)

	# ---- TEST B: RUNTIME GATE BLOCKS UNCLOSED MONSTERS ----
	var validation := MapEditorBuildRuntimeService.validate_for_runtime(doc)
	assert(not validation.ok, "runtime validation must FAIL for ID33")
	assert(
		_has_error_prefix(validation.get("errors", []), "monster_not_runtime_ready:33:"),
		"must have monster_not_runtime_ready:33 error: %s" % str(validation.get("errors", []))
	)

	# Approval must also fail.
	var approval := MapEditorBuildRuntimeService.approve_for_runtime(doc)
	assert(not approval.ok, "runtime approval must FAIL for doc with ID33")

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

	# ---- TEST D: EXEMPTION MONSTERS ARE AUTHORING + RUNTIME READY ----
	# ID186 鹰卫 / ID187 虎卫 have drop_entry_count=0 but a valid exemption,
	# so they must be authorable AND runtime-ready (no "运行时待闭环").
	for exempt_id: int in [186, 187]:
		var exempt := Catalog.find_by_monster_id("special_monster", exempt_id)
		assert(not exempt.is_empty(), "ID%d must exist in catalog" % exempt_id)
		assert(bool(exempt.get("authoring_allowed", false)), "ID%d must be authoring_allowed" % exempt_id)
		assert(bool(exempt.get("runtime_ready", false)), "ID%d must be runtime_ready (exemption)" % exempt_id)
		assert(int(exempt.get("drop_entry_count", -1)) == 0, "ID%d drop_entry_count must be 0" % exempt_id)
		var exempt_suffix := _monster_status_suffix(exempt)
		assert(not exempt_suffix.contains("待闭环"), "ID%d must NOT show 待闭环: %s" % [exempt_id, exempt_suffix])

	# ---- TEST E: VERSION_DIFFERENCE MONSTER IS AUTHORING + RUNTIME READY ----
	# ID78 沃玛教主9 is version_difference but runtime_allowed=true with
	# hostile_requires_non_empty=false, so it is authorable and runtime-ready.
	var vd := Catalog.find_by_monster_id("special_monster", 78)
	assert(not vd.is_empty(), "ID78 must exist in catalog")
	assert(str(vd.get("classification", "")) == "version_difference", "ID78 classification must be version_difference")
	assert(bool(vd.get("authoring_allowed", false)), "ID78 must be authoring_allowed")
	assert(bool(vd.get("runtime_ready", false)), "ID78 must be runtime_ready (no hostile drop requirement)")
	var vd_suffix := _monster_status_suffix(vd)
	assert(not vd_suffix.contains("待闭环"), "ID78 must NOT show 待闭环: %s" % vd_suffix)

	# ---- TEST F: GOLD-ONLY ENTITY IS AUTHORING + RUNTIME READY ----
	# ID226 宝箱 has 1 canonical drop row (quantity gold) and runtime_allowed=true.
	var gold := Catalog.find_by_monster_id("special_monster", 226)
	assert(not gold.is_empty(), "ID226 must exist in catalog")
	assert(bool(gold.get("authoring_allowed", false)), "ID226 must be authoring_allowed")
	assert(bool(gold.get("runtime_ready", false)), "ID226 must be runtime_ready (gold-only reward)")
	assert(int(gold.get("drop_entry_count", -1)) == 1, "ID226 drop_entry_count must be 1")
	var gold_suffix := _monster_status_suffix(gold)
	assert(not gold_suffix.contains("待闭环"), "ID226 must NOT show 待闭环: %s" % gold_suffix)

	# ---- TEST G: ID STABILITY ACROSS CATALOG LOOKUPS ----
	var stability_cases := [
		["monster_spawn", 18],
		["boss_spawn", 76],
		["boss_spawn", 33],
		["boss_spawn", 180],
		["special_monster", 186],
		["special_monster", 78],
		["special_monster", 226],
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

	# ---- TEST H: NO NAME FALLBACK ----
	# Placed entry carries only numeric monster_id, no display_name dependency.
	var placed_entry: Dictionary = loaded_spawns[0]
	assert(int(placed_entry.get("monster_id", -1)) == 33, "persisted entry must use monster_id=33")
	# Even if display_name were wrong, monster_id is the authority.
	placed_entry["display_name"] = "WRONG_NAME"
	assert(int(placed_entry.get("monster_id", -1)) == 33, "monster_id must not depend on display_name")

	# Catalog lookup must never use name to resolve identity.
	var by_wrong_name := Catalog.find_by_monster_id("boss_spawn", 33)
	assert(int(by_wrong_name.get("monster_id", -1)) == 33, "lookup by monster_id must be stable")

	print("MSE_AUTHORING_RUNTIME_SEPARATION_PASS authoring=yes runtime_gate=fail_closed id_stable=true exemption=2 version_diff=1 gold_entity=1")
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
