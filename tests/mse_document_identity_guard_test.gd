extends Node

## Regression guard for the map-system normalization work:
## 1. Formal documents whose embedded runtime_map_id drifted from the formal
##    identity registry (chiyue_choice_land and the two chiyue valley secret
##    passages used to carry legacy ids 990280/990330) must pass
##    MapEditorSaveService.validate_document_runtime_identity().
## 2. Legacy-id documents (for example the five legacy docs sharing runtime id
##    990100) and drifted formal documents must be rejected by the guard.
## 3. The publish button must refuse documents that fail the identity guard.
## 4. The map-template dropdown merges the two entry kinds for the same saved
##    document into ONE row without losing any reachable document: every
##    document reachable from the unmerged enumeration must still be reachable
##    exactly once after the merge.
## 5. Saving advances the authoring revision, and the runtime state label flags
##    unpublished documents and documents whose published artifact lags behind.
## 6. New-map creation allocates a collision-free formal runtime id inside the
##    canonical range, birth-registers the identity row, and the birth-registered
##    document passes the publish gate. Registry writes in this test go to
##    user:// copies via the service test overrides.
## 7. The create-map dialog suggests the map id from the selected map type:
##    every catalog type owns a non-generic prefix, switching the type
##    regenerates an untouched suggestion, and a manually edited id survives.
## 8. The formal document portal graph stays intact: every non-arrival
##    map_exit endpoint carries a complete linkage (target map key, target
##    portal, target runtime id matching the identity registry), its landing
##    tile equals the target portal's current tile, bidirectional endpoints
##    point back at each other, and one_way endpoints land on arrival_only
##    anchors. This locks the class of silent portal-linkage wipe that used to
##    pass in the editor and break transitions in the packaged game.
## The test is strictly read-only except for one synthetic document saved into
## the runner's isolated user:// tree; no workspace document and no production
## registry is written.


func _ready() -> void:
	_assert_formal_docs_aligned()
	_assert_guard_rejections()
	_assert_template_dropdown_merged()
	_assert_publish_gate()
	_assert_revision_and_staleness()
	_assert_new_map_identity_allocation()
	_assert_map_type_id_suggestion()
	_assert_all_formal_maps_reachable()
	_assert_doc_portal_network()
	print("MSE_DOCUMENT_IDENTITY_GUARD_PASS")
	get_tree().quit(0)


func _assert_formal_docs_aligned() -> void:
	var expected_ids := {
		"chiyue_choice_land": 916003,
		"chiyue_valley_secret_passage_a": 916004,
		"chiyue_valley_secret_passage_b": 916005,
	}
	for map_id: String in expected_ids:
		var editor_path := "res://map_editor_workspace/%s/%s.editor.json" % [map_id, map_id]
		var loaded := MapEditorLoadService.load_document(editor_path, false)
		assert(bool(loaded.get("ok", false)), "%s failed to load: %s" % [map_id, str(loaded.get("errors", []))])
		var document: Dictionary = loaded.document
		var check := MapEditorSaveService.validate_document_runtime_identity(document)
		assert(
			bool(check.get("ok", false)),
			"%s identity check failed: %s" % [map_id, str(check)]
		)
		assert(
			int(check.get("registered_runtime_map_id", -1)) == int(expected_ids[map_id]),
			"%s registered id mismatch: %s" % [map_id, str(check)]
		)


func _assert_guard_rejections() -> void:
	var unknown := MapEditorSaveService.validate_document_runtime_identity(
		{"map_id": "no_such_map_anywhere", "runtime_map_id": 990100}
	)
	assert(not bool(unknown.get("ok", true)), "unknown map_id must be rejected")
	assert(
		str(unknown.get("reason", "")) == "document_map_id_not_in_formal_identity_registry",
		"unknown map_id rejection reason mismatch: %s" % str(unknown)
	)
	var drifted := MapEditorSaveService.validate_document_runtime_identity(
		{"map_id": "mengzhong_zuma_pavilion", "runtime_map_id": 990100}
	)
	assert(not bool(drifted.get("ok", true)), "drifted formal doc must be rejected")
	assert(
		str(drifted.get("reason", "")) == "document_runtime_map_id_mismatch",
		"drifted rejection reason mismatch: %s" % str(drifted)
	)
	assert(
		int(drifted.get("registered_runtime_map_id", -1)) == 913105,
		"drifted rejection must report the registered id: %s" % str(drifted)
	)
	var legacy := MapEditorSaveService.validate_document_runtime_identity(
		{"map_id": "zumage_1", "runtime_map_id": 990100}
	)
	assert(not bool(legacy.get("ok", true)), "legacy-id document must be rejected")
	assert(
		str(legacy.get("reason", "")) == "formal_identity_row_missing_runtime_map_id",
		"legacy rejection reason mismatch: %s" % str(legacy)
	)


func _template_canonical_target(meta: Variant) -> String:
	if meta is Dictionary:
		return MapEditorSaveService.canonical_workspace_path(
			str((meta as Dictionary).get("path", ""))
		)
	var template := MapDesignCatalogService.find_blank_template(str(meta))
	return MapEditorSaveService.canonical_workspace_path(
		MapEditorSaveService.default_path(str(template.get("map_id", "")))
	)


func _assert_template_dropdown_merged() -> void:
	var editor := MapEditorApp.new()
	editor.load_default_workspace_on_ready = false
	editor.persist_last_document_path = false
	add_child(editor)
	## Reference enumeration: every row the list WOULD show without merging.
	var unmerged_targets := {}
	for template: Dictionary in MapDesignCatalogService.blank_templates():
		unmerged_targets[MapEditorSaveService.canonical_workspace_path(
			MapEditorSaveService.default_path(str(template.get("map_id", "")))
		)] = true
	for workspace_map: Dictionary in MapEditorSaveService.list_workspace_maps():
		unmerged_targets[MapEditorSaveService.canonical_workspace_path(
			str(workspace_map.get("path", ""))
		)] = true
	editor._refresh_map_template_options()
	## No two rows may resolve to the same saved document, and every document
	## reachable before the merge must still be reachable after it.
	var merged_targets := {}
	var duplicate_targets := 0
	for index in editor.map_template_option.item_count:
		var target := _template_canonical_target(
			editor.map_template_option.get_item_metadata(index)
		)
		if merged_targets.has(target):
			duplicate_targets += 1
		merged_targets[target] = true
	assert(
		duplicate_targets == 0,
		"dropdown rows resolving to duplicate documents: %d" % duplicate_targets
	)
	for target: String in unmerged_targets:
		assert(
			merged_targets.has(target),
			"merge lost a reachable document: %s" % target
		)
	## Spot check: 黑暗地带 must appear exactly once and open the formal doc.
	var dark_rows := 0
	for index in editor.map_template_option.item_count:
		if editor.map_template_option.get_item_text(index).begins_with("黑暗地带 ·"):
			dark_rows += 1
			var meta: Variant = editor.map_template_option.get_item_metadata(index)
			assert(
				meta is Dictionary and str(meta.get("map_id", "")) == "mengzhong_dark_area",
				"merged 黑暗地带 row must open mengzhong_dark_area"
			)
	assert(dark_rows == 1, "黑暗地带 must appear exactly once, got %d" % dark_rows)
	editor.queue_free()


func _assert_revision_and_staleness() -> void:
	var editor := MapEditorApp.new()
	editor.load_default_workspace_on_ready = false
	editor.persist_last_document_path = false
	add_child(editor)
	## Saving a synthetic hermetic document must advance its revision.
	var document := MapEditorTypes.new_map(
		"mse_revision_probe", 919999, "修订探针", Vector2i(8, 8)
	)
	var revision_before := int(document.editor_meta.revision)
	editor.current_document = document
	editor.current_document_path = "user://mse_revision_probe/mse_revision_probe.editor.json"
	editor.current_document["editor_meta"]["workspace"] = "user://mse_revision_probe"
	var saved := editor._save_current_document()
	assert(
		bool(saved.get("ok", false)),
		"probe save failed: %s" % str(saved.get("errors", []))
	)
	assert(
		int(editor.current_document.editor_meta.revision) == revision_before + 1,
		"save must advance the authoring revision"
	)
	## An unregistered map must show the unpublished hint.
	editor._update_runtime_state_label()
	assert(
		str(editor.runtime_state_label.text).contains("尚未发布"),
		"unregistered map must show the unpublished hint: %s" % str(
			editor.runtime_state_label.text
		)
	)
	## A document revision ahead of the artifact must show the stale hint.
	editor.current_document = {
		"map_id": "mengzhong_zuma_pavilion",
		"editor_meta": {"revision": 9999},
	}
	editor._update_runtime_state_label()
	assert(
		str(editor.runtime_state_label.text).contains("落后"),
		"drifted revision must show the stale hint: %s" % str(
			editor.runtime_state_label.text
		)
	)
	## An aligned revision with a document file not newer than the artifact
	## must show the fresh hint.
	var artifact: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/data/runtime/map_editor/mengzhong_zuma_pavilion.runtime.json"
	))
	var artifact_revision := int(artifact.get("source", {}).get("revision", 0))
	editor.current_document = {
		"map_id": "mengzhong_zuma_pavilion",
		"editor_meta": {"revision": artifact_revision},
	}
	editor.current_document_path = (
		"res://assets/data/runtime/map_editor/mengzhong_zuma_pavilion.runtime.json"
	)
	editor._update_runtime_state_label()
	assert(
		str(editor.runtime_state_label.text).contains("一致"),
		"aligned document must show the fresh hint: %s" % str(
			editor.runtime_state_label.text
		)
	)
	editor.queue_free()


func _assert_new_map_identity_allocation() -> void:
	DirAccess.make_dir_recursive_absolute("user://identity_alloc_test")
	var identity_override := "user://identity_alloc_test/map_identity_registry.json"
	var release_override := "user://identity_alloc_test/map_runtime_release_registry.json"
	for pair: Array in [
		["res://assets/data/map_design/map_identity_registry.json", identity_override],
		["res://assets/data/runtime/map_editor/map_runtime_release_registry.json", release_override],
	]:
		var target := FileAccess.open(str(pair[1]), FileAccess.WRITE)
		assert(target != null, "identity alloc test copy failed: %s" % str(pair[1]))
		target.store_string(FileAccess.get_file_as_string(str(pair[0])))
		target.flush()
		target.close()
	var previous_identity_override := MapEditorSaveService.test_formal_identity_path_override
	var previous_release_override := MapEditorSaveService.test_runtime_release_registry_path_override
	MapEditorSaveService.test_formal_identity_path_override = identity_override
	MapEditorSaveService.test_runtime_release_registry_path_override = release_override
	var allocation := MapEditorSaveService.allocate_next_runtime_map_id()
	var check_ok := MapEditorSaveService.validate_new_map_identity("custom_probe_map")
	var check_legacy := MapEditorSaveService.validate_new_map_identity("hadd_2")
	var check_formal := MapEditorSaveService.validate_new_map_identity("world_bich_province")
	var check_pattern := MapEditorSaveService.validate_new_map_identity("bad id!")
	var allocated_id := int(allocation.get("runtime_map_id", 0))
	var registration := MapEditorSaveService.register_formal_map_identity(
		"custom_probe_map", allocated_id, "探针地图"
	)
	var probe_document := MapEditorTypes.new_custom_map(
		"custom_probe_map", allocated_id, "探针地图", "quest_room", Vector2i(1, 1)
	)
	var gate := MapEditorSaveService.validate_document_runtime_identity(probe_document)
	var duplicate_map := MapEditorSaveService.register_formal_map_identity(
		"custom_probe_map", allocated_id + 1, "探针地图"
	)
	var duplicate_runtime := MapEditorSaveService.register_formal_map_identity(
		"custom_probe_map_b", allocated_id, "探针地图二"
	)
	var legacy_runtime := MapEditorSaveService.register_formal_map_identity(
		"custom_probe_map_c", 990100, "探针地图三"
	)
	var reallocation := MapEditorSaveService.allocate_next_runtime_map_id()
	MapEditorSaveService.test_formal_identity_path_override = previous_identity_override
	MapEditorSaveService.test_runtime_release_registry_path_override = previous_release_override
	## Assertions run after the overrides are restored so a failing assert can
	## never leave the seams redirected for later sections.
	assert(bool(allocation.get("ok", false)), "allocation failed: %s" % str(allocation))
	assert(
		allocated_id >= MapEditorSaveService.FORMAL_RUNTIME_ID_MIN
		and allocated_id <= MapEditorSaveService.FORMAL_RUNTIME_ID_MAX,
		"allocated id outside canonical range: %d" % allocated_id
	)
	assert(bool(check_ok.get("ok", false)), "fresh id must validate: %s" % str(check_ok))
	assert(
		str(check_legacy.get("errors", [])).contains("map_id_already_formal_or_legacy"),
		"legacy id must be rejected: %s" % str(check_legacy)
	)
	assert(
		str(check_formal.get("errors", [])).contains("map_id_already_formal_or_legacy"),
		"formal id must be rejected: %s" % str(check_formal)
	)
	assert(
		str(check_pattern.get("errors", [])).contains("map_id_pattern_invalid"),
		"invalid pattern must be rejected: %s" % str(check_pattern)
	)
	assert(bool(registration.get("ok", false)), "registration failed: %s" % str(registration))
	assert(
		bool(gate.get("ok", false)),
		"birth-registered document must pass the publish gate: %s" % str(gate)
	)
	assert(not bool(duplicate_map.get("ok", false)), "duplicate map_id registration must fail")
	assert(not bool(duplicate_runtime.get("ok", false)), "duplicate runtime id registration must fail")
	assert(not bool(legacy_runtime.get("ok", false)), "legacy runtime id registration must fail")
	assert(
		int(reallocation.get("runtime_map_id", 0)) > allocated_id,
		"allocator must skip the registered id: %s vs %d" % [str(reallocation), allocated_id]
	)
	var updated_registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(identity_override))
	assert(
		int(updated_registry.get("formal_map_count", 0)) == 68,
		"registry row count must advance: %s" % str(updated_registry.get("formal_map_count", 0))
	)


func _assert_map_type_id_suggestion() -> void:
	var editor := MapEditorApp.new()
	editor.load_default_workspace_on_ready = false
	editor.persist_last_document_path = false
	add_child(editor)
	## Every type offered by the template catalog must own a real id prefix:
	## the generic custom_map fallback is reserved for unknown types.
	var type_count := 0
	for entry: Dictionary in MapDesignCatalogService._read_json(
		MapDesignCatalogService.TEMPLATE_PATH
	).get("templates", []):
		var map_type := str(entry.get("id", ""))
		if map_type.is_empty():
			continue
		type_count += 1
		assert(
			editor._map_type_id_prefix(map_type) != "custom_map",
			"map type missing id prefix: %s" % map_type
		)
	assert(type_count >= 14, "catalog types unexpectedly reduced: %d" % type_count)
	## The floor categories the workspace naming convention uses.
	assert(editor._map_type_id_prefix("dungeon_floor") == "dungeon")
	assert(editor._map_type_id_prefix("mine_floor") == "mine")
	assert(editor._map_type_id_prefix("temple_floor") == "temple")
	## Switching the type regenerates an untouched suggestion. The selection is
	## applied first, exactly like the real item_selected flow.
	var dungeon_index := editor._find_type_index("dungeon_floor")
	editor.map_type_option.select(dungeon_index)
	editor._on_create_map_type_changed(dungeon_index)
	var regenerated := editor.map_id_edit.text
	assert(
		regenerated.begins_with("dungeon_"),
		"type change must regenerate the id suggestion: %s" % regenerated
	)
	assert(
		not FileAccess.file_exists(MapEditorSaveService.default_path(regenerated)),
		"suggested id must be free: %s" % regenerated
	)
	## A manually edited id survives further type switches.
	editor.map_id_edit.text = "my_custom_id"
	editor._create_map_id_manually_edited = true
	var mine_index := editor._find_type_index("mine_floor")
	editor.map_type_option.select(mine_index)
	editor._on_create_map_type_changed(mine_index)
	assert(
		editor.map_id_edit.text == "my_custom_id",
		"manually edited id must not be overwritten: %s" % editor.map_id_edit.text
	)
	editor.queue_free()


## The real completeness contract behind the user's "67 maps" expectation:
## every formal identity row whose document exists on disk must be reachable
## from the map-template dropdown. The merge no-loss assertions compare
## against the raw enumeration; this check additionally guards against the
## enumeration itself hiding documents (the superseded-legacy filter used to
## suppress formal documents whose legacy id equals their formal id, which
## hid 抉择之地/山谷密道A/山谷密道B).
func _assert_all_formal_maps_reachable() -> void:
	var editor := MapEditorApp.new()
	editor.load_default_workspace_on_ready = false
	editor.persist_last_document_path = false
	add_child(editor)
	editor._refresh_map_template_options()
	var targets := {}
	for index in editor.map_template_option.item_count:
		var meta: Variant = editor.map_template_option.get_item_metadata(index)
		if meta is Dictionary:
			targets[MapEditorSaveService.canonical_workspace_path(
				str(meta.get("path", ""))
			)] = true
		else:
			var template := MapDesignCatalogService.find_blank_template(str(meta))
			targets[MapEditorSaveService.canonical_workspace_path(
				MapEditorSaveService.default_path(str(template.get("map_id", "")))
			)] = true
	var checked := 0
	for row: Dictionary in MapEditorSaveService._formal_identity_rows():
		var formal_map_id := str(row.get("map_id", "")).strip_edges()
		if formal_map_id.is_empty():
			continue
		var document_path := MapEditorSaveService.default_path(formal_map_id)
		if not FileAccess.file_exists(document_path):
			continue
		checked += 1
		assert(
			targets.has(MapEditorSaveService.canonical_workspace_path(document_path)),
			"formal map not reachable in dropdown: %s (%s)" % [
				formal_map_id,
				str(row.get("display_name", "")),
			]
		)
	assert(
		checked >= 67,
		"formal documents on disk unexpectedly reduced: %d" % checked
	)
	## Direct spot check for the reported missing maps.
	var passage_rows := 0
	var choice_rows := 0
	for index in editor.map_template_option.item_count:
		var row_text := editor.map_template_option.get_item_text(index)
		if row_text.begins_with("山谷密道A"):
			passage_rows += 1
		if row_text.begins_with("抉择之地"):
			choice_rows += 1
	assert(passage_rows == 1, "山谷密道A must be listed exactly once, got %d" % passage_rows)
	assert(choice_rows == 1, "抉择之地 must be listed exactly once, got %d" % choice_rows)
	editor.queue_free()


func _assert_publish_gate() -> void:
	var editor := MapEditorApp.new()
	editor.load_default_workspace_on_ready = false
	editor.persist_last_document_path = false
	add_child(editor)
	editor.current_document = {
		"map_id": "mengzhong_zuma_pavilion",
		"runtime_map_id": 990100,
	}
	editor._on_publish_runtime_pressed()
	assert(
		str(editor.status_label.text).begins_with("发布拒绝"),
		"publish gate must refuse a drifted document: %s" % str(editor.status_label.text)
	)
	editor.current_document = {
		"map_id": "mengzhong_zuma_pavilion",
		"runtime_map_id": 913105,
	}
	editor._on_publish_runtime_pressed()
	assert(
		str(editor.status_label.text).begins_with("无有效候选"),
		"aligned document must fall through to the candidate check: %s" % str(
			editor.status_label.text
		)
	)
	editor.queue_free()


func _assert_doc_portal_network() -> void:
	var identity_raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/data/map_design/map_identity_registry.json"
	))
	assert(identity_raw is Dictionary, "identity registry must parse")
	var runtime_id_by_key := {}
	for row_v: Variant in (identity_raw as Dictionary).get("maps", []):
		if row_v is Dictionary:
			runtime_id_by_key[str(row_v["map_id"])] = int(row_v["runtime_map_id"])
	var documents := {}
	for key: String in runtime_id_by_key:
		var document_path := "res://map_editor_workspace/%s/%s.editor.json" % [key, key]
		if not FileAccess.file_exists(document_path):
			continue
		var loaded := MapEditorLoadService.load_document(document_path, false)
		assert(
			bool(loaded.get("ok", false)),
			"%s failed to load for portal contract: %s" % [key, str(loaded.get("errors", []))]
		)
		documents[key] = loaded.document
	var index := {}
	for key: String in documents:
		for raw_endpoint: Variant in documents[key].get("layers", {}).get("map_exit_points", []):
			assert(raw_endpoint is Dictionary, "%s has a non-dictionary portal endpoint" % key)
			var endpoint: Dictionary = raw_endpoint
			var endpoint_key := "%s::%s" % [key, str(endpoint.get("semantic_id", ""))]
			assert(
				not str(endpoint.get("semantic_id", "")).is_empty() and not index.has(endpoint_key),
				"portal endpoint id empty or duplicated: %s" % endpoint_key
			)
			index[endpoint_key] = endpoint
	assert(
		index.size() >= 132,
		"formal doc portal endpoint count regressed: %d" % index.size()
	)
	for key: String in documents:
		for raw_endpoint: Variant in documents[key].get("layers", {}).get("map_exit_points", []):
			var endpoint: Dictionary = raw_endpoint
			var self_key := "%s::%s" % [key, str(endpoint.get("semantic_id", ""))]
			var mode := str(endpoint.get("connection_mode", ""))
			if mode == "arrival_only":
				continue
			assert(
				mode == "bidirectional" or mode == "one_way",
				"unclassified doc portal: %s (%s)" % [self_key, mode]
			)
			var target_map := str(endpoint.get("target_map_key", ""))
			var target_portal := str(endpoint.get("target_portal_id", ""))
			var target_id := str(endpoint.get("target_map_id", ""))
			assert(
				not target_map.is_empty() and not target_portal.is_empty() and not target_id.is_empty(),
				"doc portal linkage wiped: %s" % self_key
			)
			assert(
				int(runtime_id_by_key.get(target_map, -1)) == int(float(target_id)),
				"doc portal target runtime id mismatch: %s (%s vs %s)" % [
					self_key, target_id, str(int(runtime_id_by_key.get(target_map, -1)))
				]
			)
			var target_full := "%s::%s" % [target_map, target_portal]
			assert(
				index.has(target_full),
				"doc portal target missing: %s -> %s" % [self_key, target_full]
			)
			var target: Dictionary = index[target_full]
			assert(
				endpoint.get("target_tile", []) == target.get("tile", []),
				"doc portal landing tile mismatch: %s target_tile=%s target tile=%s" % [
					self_key, str(endpoint.get("target_tile", [])), str(target.get("tile", []))
				]
			)
			if mode == "bidirectional":
				assert(
					str(target.get("target_map_key", "")) == key
					and str(target.get("target_portal_id", "")) == str(endpoint.get("semantic_id", "")),
					"doc portal backlink broken: %s" % self_key
				)
			else:
				assert(
					str(target.get("connection_mode", "")) == "arrival_only",
					"one_way doc portal must land on an arrival_only anchor: %s" % self_key
				)
