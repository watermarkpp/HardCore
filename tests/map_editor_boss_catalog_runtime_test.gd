extends Node

const Catalog := preload("res://scripts/map_editor/map_editor_content_catalog_service.gd")
const RuntimeBridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const BuildService := preload("res://scripts/map_editor/map_editor_build_runtime_service.gd")
const Fixtures := preload("res://tests/helpers/map_runtime_transaction_test_fixtures.gd")
const SpawnMigration := preload("res://tools/map_editor/migrate_map_spawn_identity.gd")


func _ready() -> void:
	_test_spawn_identity_parser()
	# The map editor consumes one ID-keyed canonical catalog. Rebuilding all
	# three directories must parse that source once and never reopen legacy
	# monster/boss/service tables.
	Catalog.reset_source_parse_counts()
	var monsters: Array[Dictionary] = Catalog.entries("monster_spawn")
	var bosses: Array[Dictionary] = Catalog.entries("boss_spawn")
	var special: Array[Dictionary] = Catalog.entries("special_monster")
	var counts := Catalog.source_parse_counts()
	assert(int(counts.get("res://assets/data/runtime/canonical_monster_catalog.json", 0)) == 1)
	assert(counts.size() == 1, "map catalog parsed legacy sources: %s" % counts)

	# User-authoritative canonical classifications: Woma soldier/fighter/warrior
	# are ordinary, Woma guardian is elite, and Woma Taurus is the Boss.
	_assert_entry(monsters, "monster.64", true)
	_assert_entry(monsters, "monster.66", true)
	_assert_entry(monsters, "monster.68", true)
	_assert_entry(monsters, "monster.73", false)
	_assert_entry(monsters, "monster.76", false)
	_assert_entry(bosses, "boss.73", true)
	_assert_entry(bosses, "boss.76", true)
	_assert_entry(bosses, "boss.64", false)
	_assert_entry(bosses, "boss.66", false)
	_assert_entry(bosses, "boss.68", false)

	var soldier := Catalog.find("monster_spawn", "monster.64")
	assert(str(soldier.get("classification", "")) == "ordinary")
	assert(str(soldier.get("placement_kind", "")) == "monster_spawn")
	assert(bool(soldier.get("authoring_allowed", false)))
	assert(bool(soldier.get("runtime_ready", false)))
	assert(int(soldier.get("default_respawn_seconds", 0)) == 60)
	assert(bool(soldier.get("appearance_verified", false)))

	var warrior := Catalog.find("monster_spawn", "monster.68")
	assert(str(warrior.get("classification", "")) == "ordinary")
	assert(int(warrior.get("hp", 0)) == 285)
	assert(int(warrior.get("attack_min", 0)) == 16 and int(warrior.get("attack_max", 0)) == 28)
	assert(int(warrior.get("experience", 0)) == 310)
	assert(bool(warrior.get("authoring_allowed", false)))
	assert(bool(warrior.get("runtime_ready", false)))
	assert(str(warrior.get("source_status", "")) == "formal")

	var guardian := Catalog.find("boss_spawn", "boss.73")
	assert(str(guardian.get("classification", "")) == "elite")
	assert(str(guardian.get("placement_kind", "")) == "boss_spawn")
	assert(int(guardian.get("default_respawn_seconds", 0)) == 900)
	assert(bool(guardian.get("authoring_allowed", false)))
	assert(bool(guardian.get("runtime_ready", false)))

	var taurus := Catalog.find("boss_spawn", "boss.76")
	assert(str(taurus.get("classification", "")) == "boss")
	assert(str(taurus.get("placement_kind", "")) == "boss_spawn")
	assert(int(taurus.get("default_respawn_seconds", 0)) == 1800)
	assert(int(taurus.get("drop_entry_count", 0)) == 33)
	assert(bool(taurus.get("authoring_allowed", false)))
	assert(bool(taurus.get("runtime_ready", false)))
	var has_horn := false
	for drop: Dictionary in taurus.get("drop_entries", []):
		if str(drop.get("raw_text", "")).contains("沃玛号角"):
			has_horn = true
			break
	assert(has_horn, "canonical Woma Taurus drop rows lost 沃玛号角")

	# Every final active identity remains authorable. Runtime readiness is a
	# separate publish-time gate and these three active variants are ready.
	_assert_entry(special, "boss.39", true)
	_assert_entry(special, "monster.77", true)
	_assert_entry(special, "monster.78", true)
	var unknown_hall := Catalog.find("special_monster", "monster.77")
	assert(str(unknown_hall.get("classification", "")) == "special")
	assert(bool(unknown_hall.get("authoring_allowed", false)))
	assert(bool(unknown_hall.get("runtime_ready", false)))
	var no_drop_variant := Catalog.find("special_monster", "monster.78")
	assert(str(no_drop_variant.get("classification", "")) == "version_difference")
	assert(int(no_drop_variant.get("drop_entry_count", -1)) == 0)
	assert(bool(no_drop_variant.get("authoring_allowed", false)))
	assert(bool(no_drop_variant.get("runtime_ready", false)))
	var unresolved_boss := Catalog.find("boss_spawn", "boss.239")
	assert(not unresolved_boss.is_empty())
	assert(bool(unresolved_boss.get("authoring_allowed", false)))
	assert(bool(unresolved_boss.get("runtime_ready", false)))
	var blocked_boss := Catalog.find("boss_spawn", "boss.33")
	assert(bool(blocked_boss.get("authoring_allowed", false)))
	assert(not bool(blocked_boss.get("runtime_ready", true)))

	# The production runtime bridge still receives the exact stable ID and
	# preserves count/max_alive/radius/respawn/spawn-group semantics.
	var runtime := {"design": {"design_size": [50, 50]}}
	var saved_boss := {
		"monster_id": 76,
		"display_name": "saved exact", "tile": [20, 21],
		"count": 1, "max_alive": 1, "radius_gu": 0.0,
		"respawn_seconds": 1800, "semantic_id": "boss_spawn_test",
	}
	var converted: Dictionary = RuntimeBridge._combat_spawn(runtime, saved_boss, "boss_spawn")
	assert(int(converted.get("monster_id", -1)) == 76)
	assert(float(converted.get("respawn_seconds", 0.0)) == 1800.0)
	assert(str(converted.get("spawn_group", {}).get("semantic_id", "")) == "boss_spawn_test")

	# Exercise the real editor controls and the read-only canonical detail panel.
	var editor := MapEditorApp.new()
	editor.load_default_workspace_on_ready = false
	add_child(editor)
	editor.current_document = MapEditorTypes.new_map(
		"boss_catalog_runtime", 990159, "Boss Catalog Runtime", Vector2i(50, 50)
	)
	editor.preview.set_document(editor.current_document)
	await get_tree().process_frame
	assert(editor.semantic_detail_label != null)
	assert(editor.semantic_detail_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT)
	var boss_index := _option_index(editor.semantic_kind_option, "boss_spawn")
	assert(boss_index >= 0)
	editor.semantic_kind_option.select(boss_index)
	editor._on_semantic_kind_selected(boss_index, false)
	_select_catalog_content(editor, "boss.76")
	assert(int(editor.semantic_respawn.value) == 1800)
	assert(editor.semantic_detail_label.text.contains("沃玛号角"))
	_select_catalog_content(editor, "boss.33")
	assert(editor.semantic_detail_label.text.contains("运行时待闭环"))

	# End-to-end editor contract: select canonical ordinary/elite/Boss entries,
	# place an active special variant, save, reload, build and publish in a
	# user:// scratch registry. Stable monster_id values must survive every
	# boundary; no tracked formal release artifact is touched by this test.
	var ordinary_kind := _option_index(editor.semantic_kind_option, "monster_spawn")
	editor.semantic_kind_option.select(ordinary_kind)
	editor._on_semantic_kind_selected(ordinary_kind, false)
	_select_catalog_content(editor, "monster.64")
	editor._on_semantic_tile_clicked(Vector2i(4, 4))
	var boss_kind := _option_index(editor.semantic_kind_option, "boss_spawn")
	editor.semantic_kind_option.select(boss_kind)
	editor._on_semantic_kind_selected(boss_kind, false)
	_select_catalog_content(editor, "boss.73")
	editor._on_semantic_tile_clicked(Vector2i(8, 8))
	_select_catalog_content(editor, "boss.76")
	editor._on_semantic_tile_clicked(Vector2i(12, 12))
	var special_kind := _option_index(editor.semantic_kind_option, "special_monster")
	editor.semantic_kind_option.select(special_kind)
	editor._on_semantic_kind_selected(special_kind, false)
	_select_catalog_content(editor, "monster.77")
	var before_special := (editor.current_document.layers.monster_spawn as Array).size()
	editor._on_semantic_tile_clicked(Vector2i(16, 16))
	assert((editor.current_document.layers.monster_spawn as Array).size() == before_special + 1)

	var scratch_path := "user://mse_catalog_chain/boss_catalog_runtime.editor.json"
	editor.current_document_path = scratch_path
	var saved := editor._save_current_document()
	assert(bool(saved.get("ok", false)), str(saved))
	_assert_json_integer_monster_ids(scratch_path, [64, 73, 76, 77])
	assert(editor._open_document_path(scratch_path), str(editor.status_label.text))
	_assert_saved_monster_ids(editor.current_document.layers.monster_spawn, [64, 77])
	_assert_saved_monster_ids(editor.current_document.layers.boss_spawn, [73, 76])

	BuildService.test_formal_runtime_root_override = "user://mse_catalog_chain/formal/"
	var registry_path := "user://mse_catalog_chain/release_registry.json"
	Fixtures.write_registry(registry_path, [])
	RuntimeBridge.test_override_release_registry_path(registry_path)
	editor._on_build_candidate_pressed()
	assert(not editor._last_build_candidate.is_empty())
	var candidate: Dictionary = editor._last_build_candidate
	var published := BuildService.publish_runtime_release(
		str(candidate.get("candidate_path", "")),
		int(editor.current_document.get("runtime_map_id", -1)),
		candidate.get("document_binding", {}),
		registry_path,
		str(editor.current_document.get("map_id", ""))
	)
	assert(bool(published.get("success", false)), str(published))
	assert(bool(published.get("formal_playable", false)))
	var published_runtime: Dictionary = RuntimeBridge.load_map(int(editor.current_document.get("runtime_map_id", -1)))
	var published_semantics: Dictionary = published_runtime.get("semantics", {})
	_assert_runtime_layer_ids(published_semantics.get("monster_spawn", []), [64, 77])
	_assert_runtime_layer_ids(published_semantics.get("boss_spawn", []), [73, 76])
	Fixtures.reset_seams()
	editor.queue_free()
	print("MAP_EDITOR_BOSS_CATALOG_RUNTIME_PASS ordinary=%d boss=%d special=%d canonical=1" % [monsters.size(), bosses.size(), special.size()])
	get_tree().quit()


func _assert_entry(entries: Array[Dictionary], content_id: String, expected: bool) -> void:
	var present := false
	for entry: Dictionary in entries:
		if str(entry.get("content_id", "")) == content_id:
			present = true
			break
	assert(present == expected, "%s presence=%s expected=%s" % [content_id, present, expected])


func _option_index(option: OptionButton, metadata_value: String) -> int:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == metadata_value:
			return index
	return -1


func _select_catalog_content(editor: MapEditorApp, content_id: String) -> void:
	for index in editor.semantic_content_option.item_count:
		var entry: Variant = editor.semantic_content_option.get_item_metadata(index)
		if entry is Dictionary and str(entry.get("content_id", "")) == content_id:
			editor.semantic_content_option.select(index)
			editor._on_semantic_content_selected(index)
			return
	assert(false, "catalog content missing: %s" % content_id)


func _assert_saved_monster_ids(entries: Array, expected_ids: Array[int]) -> void:
	var actual: Array[int] = []
	for entry: Dictionary in entries:
		assert(entry.has("monster_id"), "saved semantic entry lost monster_id: %s" % entry)
		assert(not entry.get("monster_id") is String, "saved monster_id must remain numeric: %s" % entry)
		assert(int(entry.get("monster_id", -1)) > 0, "saved monster_id must be positive: %s" % entry)
		assert(not entry.has("boss_id"), "saved semantic entry must not carry boss_id: %s" % entry)
		assert(not entry.has("content_id"), "catalog content_id is UI-only and must not be persisted: %s" % entry)
		assert(not entry.has("is_boss"), "is_boss is canonical-derived and must not be persisted: %s" % entry)
		actual.append(int(entry.get("monster_id", -1)))
	for expected: int in expected_ids:
		assert(expected in actual, "saved semantic monster_id missing: %d from %s" % [expected, actual])


func _assert_json_integer_monster_ids(path: String, expected_ids: Array[int]) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "saved editor document missing: %s" % path)
	var text := file.get_as_text()
	assert(not text.contains('"boss_id"'), "saved editor document contains forbidden boss_id")
	assert(not text.contains('"content_id"'), "saved editor document contains UI-only content_id")
	for expected: int in expected_ids:
		var token := '"monster_id": %d' % expected
		assert(text.contains(token), "saved editor JSON missing integer token: %s" % token)
		assert(not text.contains('"monster_id": %d.' % expected), "saved editor JSON serialized decimal monster_id=%d" % expected)
		assert(not text.contains('"monster_id": "%d"' % expected), "saved editor JSON serialized string monster_id=%d" % expected)


func _assert_runtime_layer_ids(entries: Array, expected_ids: Array[int]) -> void:
	var actual: Array[int] = []
	for entry: Dictionary in entries:
		assert(entry.has("monster_id"), "runtime spawn must carry canonical monster_id: %s" % entry)
		assert(not entry.has("monsterId"), "runtime spawn must not carry legacy monsterId: %s" % entry)
		assert(not entry.has("boss_id"), "runtime spawn must not carry boss_id: %s" % entry)
		assert(not entry.has("content_id"), "runtime spawn must not carry UI content_id: %s" % entry)
		assert(not entry.has("is_boss"), "runtime spawn must derive Boss state canonically: %s" % entry)
		var numeric_id: Variant = entry.get("monster_id")
		assert(not numeric_id is String and not numeric_id is bool, "runtime monster_id must be numeric: %s" % entry)
		assert(float(numeric_id) > 0.0 and float(numeric_id) == floor(float(numeric_id)), "runtime monster_id must be positive integral: %s" % entry)
		actual.append(int(numeric_id))
	for expected: int in expected_ids:
		assert(expected in actual, "published runtime monster ID missing: %d from %s" % [expected, actual])


func _test_spawn_identity_parser() -> void:
	assert(SpawnMigration._parse_identity_value(64) == 64)
	assert(SpawnMigration._parse_identity_value(64.0) == 64)
	assert(SpawnMigration._parse_identity_value("monster.64") == 64)
	assert(SpawnMigration._parse_identity_value("boss.76") == 76)
	for invalid: Variant in [true, false, 64.5, "64", " garbage.64", "garbage.64", "monster.64.1", "monster.64 ", "boss.-1", "monster.0"]:
		assert(SpawnMigration._parse_identity_value(invalid) == -1, "accepted invalid identity: %s" % [invalid])
	var conflict := SpawnMigration._entry_identity({"monster_id": "monster.64", "content_id": "monster.66"})
	assert(not bool(conflict.get("ok", true)))
	assert(str(conflict.get("reason", "")) == "conflicting_identity_fields")
	var same := SpawnMigration._entry_identity({"monster_id": "monster.64", "content_id": "monster.64"})
	assert(bool(same.get("ok", false)))
	assert(int(same.get("monster_id", -1)) == 64)
