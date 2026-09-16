extends Node

## Regression guard for the map-system normalization work:
## 1. Formal documents whose embedded runtime_map_id drifted from the formal
##    identity registry (chiyue_choice_land and the two chiyue valley secret
##    passages used to carry legacy ids 990280/990330) must pass
##    MapEditorSaveService.validate_document_runtime_identity().
## 2. Legacy-id documents (for example the five legacy docs sharing runtime id
##    990100) and drifted formal documents must be rejected by the guard.
## 3. The map-template dropdown must not offer superseded legacy templates and
##    must not contain duplicate display names.
## 4. The publish button must refuse documents that fail the identity guard.
## The test is strictly read-only: no document is saved and no registry is
## written.


func _ready() -> void:
	_assert_formal_docs_aligned()
	_assert_guard_rejections()
	_assert_template_dropdown_deduplicated()
	_assert_publish_gate()
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


func _assert_template_dropdown_deduplicated() -> void:
	var editor := MapEditorApp.new()
	editor.load_default_workspace_on_ready = false
	editor.persist_last_document_path = false
	add_child(editor)
	editor._refresh_map_template_options()
	var superseded: Dictionary = MapEditorSaveService._superseded_legacy_map_ids()
	var template_ids: Array[String] = []
	var display_names := {}
	var duplicate_names := 0
	for index in editor.map_template_option.item_count:
		var meta: Variant = editor.map_template_option.get_item_metadata(index)
		var text := editor.map_template_option.get_item_text(index)
		if meta is Dictionary:
			var display_name := str((meta as Dictionary).get("display_name", ""))
			if display_names.has(display_name):
				duplicate_names += 1
			display_names[display_name] = true
		else:
			template_ids.append(str(meta))
	assert(
		duplicate_names == 0,
		"dropdown still has %d duplicate display names" % duplicate_names
	)
	var catalog_templates: Array = MapDesignCatalogService.blank_templates()
	var catalog_by_id := {}
	for template: Dictionary in catalog_templates:
		catalog_by_id[str(template.get("template_id", ""))] = template
	var expected_template_count := 0
	for template: Dictionary in catalog_templates:
		if not superseded.has(str(template.get("map_id", ""))):
			expected_template_count += 1
	assert(
		template_ids.size() == expected_template_count,
		"template item count %d != expected %d" % [template_ids.size(), expected_template_count]
	)
	for template_id: String in template_ids:
		var template: Dictionary = catalog_by_id.get(template_id, {})
		assert(
			not superseded.has(str(template.get("map_id", ""))),
			"superseded legacy template still offered: %s" % template_id
		)
	assert(not template_ids.has("blank.hadd_2"), "blank.hadd_2 must be suppressed")
	assert(
		not template_ids.has("blank.wooma_temple_1"),
		"blank.wooma_temple_1 must be suppressed"
	)
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
