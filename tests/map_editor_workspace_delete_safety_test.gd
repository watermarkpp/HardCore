extends Node

const SaveService := preload(
	"res://scripts/map_editor/map_editor_save_service.gd"
)
const CatalogService := preload(
	"res://scripts/map_editor/map_design_catalog_service.gd"
)
const PathSafety := preload(
	"res://scripts/map_editor/map_editor_path_safety.gd"
)

const TEST_ROOT := "user://b01_map_workspace_delete_safety/"
const TEST_CATALOG := "user://b01_map_workspace_delete_safety_catalog.json"
const SENTINEL := "do-not-delete"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	SaveService.test_workspace_root_override = TEST_ROOT
	CatalogService.test_blank_template_path_override = TEST_CATALOG
	CatalogService.test_force_blank_template_write_failure = false
	_remove_tree(TEST_ROOT)
	_remove_file(TEST_CATALOG)
	DirAccess.make_dir_recursive_absolute(_absolute(TEST_ROOT))

	_test_identity_components_and_scope()
	_test_prefix_neighbor_isolated()
	_test_document_identity_and_path_binding()
	_test_formal_and_frozen_protection()
	_test_registry_fail_closed()
	_test_catalog_identity_binding()
	_test_formal_template_is_unchanged()
	_test_workspace_failure_keeps_catalog()
	_test_catalog_failure_restores_workspace()
	_test_blank_template_without_workspace()
	_test_failed_operation_keeps_target()
	_test_link_probe_when_supported()
	_test_legal_move_and_recovery()

	SaveService.test_workspace_root_override = ""
	SaveService.test_formal_identity_path_override = ""
	SaveService.test_runtime_release_registry_path_override = ""
	CatalogService.test_blank_template_path_override = ""
	CatalogService.test_force_blank_template_write_failure = false
	_remove_tree(TEST_ROOT)
	_remove_file(TEST_CATALOG)
	print("MAP_EDITOR_WORKSPACE_DELETE_SAFETY_PASS")
	get_tree().quit(0)


func _test_identity_components_and_scope() -> void:
	_make_map("valid_component")
	for map_id: String in ["", ".", "..", "nested/name", "nested\\name", "prefix/../x"]:
		var planned := SaveService.plan_workspace_map_deletion(map_id)
		assert(not bool(planned.get("ok", false)), "invalid map id accepted: %s" % map_id)
		var errors: Array = planned.get("errors", [])
		assert(not errors.is_empty())
	assert(
		SaveService.plan_workspace_map_deletion(".").get("errors", [""])[0]
		== "map_id_invalid_component"
	)
	var root := _absolute(TEST_ROOT)
	assert(
		PathSafety.strict_child_path(root, root).get("error", "")
		== "target_is_workspace_root"
	)
	assert(bool(PathSafety.strict_child_path(root, root.path_join("direct_child")).get("ok", false)))
	assert(
		PathSafety.strict_child_path(root, root.path_join("nested/child")).get("error", "")
		== "target_not_single_child"
	)
	assert(
		PathSafety.strict_child_path(root, root.path_join("../escape")).get("error", "")
		== "path_escape_attempt"
	)
	assert(
		PathSafety.strict_child_path(root, root + "_neighbor/direct").get("error", "")
		== "path_escape_attempt"
	)
	assert(DirAccess.dir_exists_absolute(_absolute(TEST_ROOT.path_join("valid_component"))))
	_remove_tree(TEST_ROOT.path_join("valid_component"))


func _test_prefix_neighbor_isolated() -> void:
	_make_map("prefix")
	_make_map("prefix_neighbor")
	var result := SaveService.delete_workspace_map("prefix")
	assert(bool(result.get("ok", false)), str(result))
	assert(not DirAccess.dir_exists_absolute(_absolute(TEST_ROOT.path_join("prefix"))))
	assert(
		DirAccess.dir_exists_absolute(_absolute(TEST_ROOT.path_join("prefix_neighbor"))),
		"prefix deletion must not touch a prefix neighbor"
	)
	assert(DirAccess.dir_exists_absolute(_absolute(str(result.get("recovery_path", "")))))
	_remove_tree(TEST_ROOT.path_join("prefix_neighbor"))
	_remove_tree(str(result.get("recovery_path", "")))
	_remove_empty_recovery_root()


func _test_document_identity_and_path_binding() -> void:
	_make_map("identity_target", {"map_id": "other_map"})
	var wrong_identity := SaveService.plan_workspace_map_deletion("identity_target")
	_assert_error(wrong_identity, "document_map_id_mismatch")
	assert(DirAccess.dir_exists_absolute(_absolute(TEST_ROOT.path_join("identity_target"))))
	_remove_tree(TEST_ROOT.path_join("identity_target"))

	_make_map("path_target")
	var path := TEST_ROOT.path_join("path_target/path_target.editor.json")
	var wrong_path := SaveService.plan_workspace_map_deletion(
		"path_target",
		TEST_ROOT.path_join("other/path_target.editor.json")
	)
	_assert_error(wrong_path, "document_path_mismatch")
	var wrong_expected := SaveService.plan_workspace_map_deletion(
		"path_target",
		path,
		{"map_id": "other_map", "path": path}
	)
	_assert_error(wrong_expected, "expected_document_identity_mismatch")
	assert(DirAccess.dir_exists_absolute(_absolute(TEST_ROOT.path_join("path_target"))))
	_remove_tree(TEST_ROOT.path_join("path_target"))


func _test_formal_and_frozen_protection() -> void:
	_make_map("world_bich_province")
	var formal := SaveService.plan_workspace_map_deletion("world_bich_province")
	_assert_error(formal, "formal_map_protected")
	assert(DirAccess.dir_exists_absolute(_absolute(TEST_ROOT.path_join("world_bich_province"))))
	_remove_tree(TEST_ROOT.path_join("world_bich_province"))

	_make_map("frozen_fixture", {"frozen": true})
	var frozen := SaveService.plan_workspace_map_deletion("frozen_fixture")
	_assert_error(frozen, "frozen_or_approved_map_protected")
	assert(DirAccess.dir_exists_absolute(_absolute(TEST_ROOT.path_join("frozen_fixture"))))
	_remove_tree(TEST_ROOT.path_join("frozen_fixture"))


func _test_registry_fail_closed() -> void:
	SaveService.test_formal_identity_path_override = TEST_ROOT.path_join("missing_identity.json")
	var missing := SaveService.validate_map_deletion_guard("registry_probe")
	_assert_error(missing, "formal_identity_registry_unavailable")
	_write_text(TEST_ROOT.path_join("invalid_identity.json"), "{}")
	SaveService.test_formal_identity_path_override = TEST_ROOT.path_join("invalid_identity.json")
	var invalid := SaveService.validate_map_deletion_guard("registry_probe")
	_assert_error(invalid, "formal_identity_registry_invalid")
	SaveService.test_formal_identity_path_override = ""
	_remove_file(TEST_ROOT.path_join("invalid_identity.json"))
	SaveService.test_runtime_release_registry_path_override = TEST_ROOT.path_join("missing_release_registry.json")
	var missing_release := SaveService.validate_map_deletion_guard("registry_probe")
	_assert_error(missing_release, "runtime_release_registry_unavailable")
	SaveService.test_runtime_release_registry_path_override = ""


func _test_formal_template_is_unchanged() -> void:
	_write_catalog([
		{"template_id": "formal_template", "map_id": "world_bich_province", "display_name": "formal"},
	])
	var before := _read_text(TEST_CATALOG)
	var result := SaveService.delete_map_authoring_transaction(
		"world_bich_province",
		"formal_template"
	)
	_assert_error(result, "formal_map_protected")
	assert(_read_text(TEST_CATALOG) == before, "formal guard must precede catalog mutation")


func _test_catalog_identity_binding() -> void:
	_write_catalog([
		{"template_id": "template_a", "map_id": "map_a", "display_name": "a"},
		{"template_id": "template_b", "map_id": "map_b", "display_name": "b"},
	])
	var before := _read_text(TEST_CATALOG)
	var mismatch := CatalogService.plan_blank_template_deletion("template_a", "map_b")
	_assert_error(mismatch, "template_identity_mismatch")
	assert(_read_text(TEST_CATALOG) == before)


func _test_workspace_failure_keeps_catalog() -> void:
	var map_id := "workspace_failure"
	_write_catalog([
		{"template_id": "workspace_failure_template", "map_id": map_id, "display_name": "failure"},
	])
	var fixture := _make_map(map_id)
	_remove_file(str(fixture.get("document_path", "")))
	var before := _read_text(TEST_CATALOG)
	var result := SaveService.delete_map_authoring_transaction(
		map_id,
		"workspace_failure_template"
	)
	_assert_error(result, "document_not_found")
	assert(_read_text(TEST_CATALOG) == before, "workspace planning failure must not edit catalog")
	assert(DirAccess.dir_exists_absolute(_absolute(TEST_ROOT.path_join(map_id))))
	_remove_tree(TEST_ROOT.path_join(map_id))


func _test_catalog_failure_restores_workspace() -> void:
	var map_id := "rollback_map"
	_write_catalog([
		{"template_id": "rollback_template", "map_id": map_id, "display_name": "rollback"},
	])
	_make_map(map_id)
	var sentinel_path := TEST_ROOT.path_join(map_id + "/sentinel.txt")
	_write_text(sentinel_path, SENTINEL)
	var document_path := TEST_ROOT.path_join(map_id + "/" + map_id + ".editor.json")
	var before := _read_text(TEST_CATALOG)
	CatalogService.test_force_blank_template_write_failure = true
	var result := SaveService.delete_map_authoring_transaction(
		map_id,
		"rollback_template",
		document_path,
		{"map_id": map_id, "path": document_path}
	)
	CatalogService.test_force_blank_template_write_failure = false
	assert(not bool(result.get("ok", false)), str(result))
	var errors: Array = result.get("errors", [])
	assert(errors.has("template_commit_failed"), str(result))
	assert(errors.has("forced_write_failure"), str(result))
	assert(bool(result.get("catalog_restored", false)), str(result))
	assert(bool(result.get("workspace_restored", false)), str(result))
	assert(bool(result.get("transaction_rolled_back", false)), str(result))
	assert(_read_text(TEST_CATALOG) == before, "failed catalog commit must preserve catalog")
	assert(DirAccess.dir_exists_absolute(_absolute(TEST_ROOT.path_join(map_id))))
	assert(_read_text(sentinel_path) == SENTINEL)
	_remove_tree(TEST_ROOT.path_join(map_id))
	_remove_empty_recovery_root()


func _test_blank_template_without_workspace() -> void:
	var map_id := "blank_only_map"
	_write_catalog([
		{"template_id": "blank_only_template", "map_id": map_id, "display_name": "blank"},
	])
	var result := SaveService.delete_map_authoring_transaction(
		map_id,
		"blank_only_template"
	)
	assert(bool(result.get("ok", false)), str(result))
	assert(bool(result.get("template_deleted", false)), str(result))
	assert(not bool(result.get("workspace_deleted", false)), str(result))
	assert(CatalogService.find_blank_template("blank_only_template").is_empty())


func _test_failed_operation_keeps_target() -> void:
	_make_map("blocked_move")
	var sentinel_path := TEST_ROOT.path_join("blocked_move/sentinel.txt")
	_write_text(sentinel_path, SENTINEL)
	var recovery_file := _absolute(TEST_ROOT.path_join(".recycle_bin"))
	_write_text(recovery_file, "recovery-slot-is-not-a-directory")
	var result := SaveService.delete_workspace_map("blocked_move")
	assert(not bool(result.get("ok", false)), str(result))
	var errors: Array = result.get("errors", [])
	assert(not errors.is_empty())
	assert(str(errors[0]).begins_with("recovery_root_create_failed:"))
	assert(DirAccess.dir_exists_absolute(_absolute(TEST_ROOT.path_join("blocked_move"))))
	assert(FileAccess.get_file_as_string(sentinel_path) == SENTINEL)
	DirAccess.remove_absolute(recovery_file)
	_remove_tree(TEST_ROOT.path_join("blocked_move"))


func _test_link_probe_when_supported() -> void:
	_make_map("link_fixture")
	var outside := TEST_ROOT.path_join("outside_target")
	_write_text(outside.path_join("outside.txt"), SENTINEL)
	var link_path := TEST_ROOT.path_join("link_fixture/linked_dir")
	var link_parent := DirAccess.open(_absolute(TEST_ROOT.path_join("link_fixture")))
	assert(link_parent != null)
	var link_error := link_parent.create_link(_absolute(outside), _absolute(link_path))
	if link_error != OK:
		print("B01_LINK_TEST=SKIPPED error=%d" % link_error)
	else:
		var result := SaveService.delete_workspace_map("link_fixture")
		_assert_error(result, "linked_entry_rejected:linked_dir")
		assert(DirAccess.dir_exists_absolute(_absolute(TEST_ROOT.path_join("link_fixture"))))
		assert(FileAccess.get_file_as_string(outside.path_join("outside.txt")) == SENTINEL)
		DirAccess.remove_absolute(_absolute(link_path))
	_remove_tree(TEST_ROOT.path_join("link_fixture"))
	_remove_tree(outside)


func _test_legal_move_and_recovery() -> void:
	var map_id := "legal_single_target"
	_make_map(map_id)
	var nested := TEST_ROOT.path_join(map_id + "/ground/.hidden/sentinel.txt")
	_write_text(nested, SENTINEL)
	var document_path := TEST_ROOT.path_join(map_id + "/" + map_id + ".editor.json")
	var plan := SaveService.plan_workspace_map_deletion(
		map_id,
		document_path,
		{"map_id": map_id, "path": document_path}
	)
	assert(bool(plan.get("ok", false)), str(plan))
	var result := SaveService.delete_workspace_map(
		map_id,
		document_path,
		{"map_id": map_id, "path": document_path}
	)
	assert(bool(result.get("ok", false)), str(result))
	var target := _absolute(TEST_ROOT.path_join(map_id))
	var recovery := _absolute(str(result.get("recovery_path", "")))
	assert(not DirAccess.dir_exists_absolute(target))
	assert(DirAccess.dir_exists_absolute(recovery))
	assert(FileAccess.get_file_as_string(recovery.path_join("ground/.hidden/sentinel.txt")) == SENTINEL)
	assert(int(result.get("deleted_files", 0)) >= 2)
	# Reversible quarantine: put the exact directory back, then prove it is intact.
	assert(DirAccess.rename_absolute(recovery, target) == OK)
	assert(DirAccess.dir_exists_absolute(target))
	assert(FileAccess.get_file_as_string(nested) == SENTINEL)
	_remove_tree(TEST_ROOT.path_join(map_id))
	_remove_empty_recovery_root()


func _make_map(map_id: String, document_overrides: Dictionary = {}) -> Dictionary:
	var map_path := TEST_ROOT.path_join(map_id)
	var document_path := map_path.path_join(map_id + ".editor.json")
	DirAccess.make_dir_recursive_absolute(_absolute(map_path))
	var document := {
		"map_id": map_id,
		"display_name": "B01 isolated fixture",
		"editor_meta": {
			"template_kind": "custom_empty_map",
			"workspace": _absolute(map_path),
		},
	}
	for key: Variant in document_overrides.keys():
		if key == "editor_meta" and document_overrides[key] is Dictionary:
			var meta: Dictionary = document.editor_meta.duplicate()
			meta.merge(document_overrides[key])
			document.editor_meta = meta
		else:
			document[key] = document_overrides[key]
	_write_text(document_path, JSON.stringify(document))
	return {"map_path": map_path, "document_path": document_path}


func _assert_error(result: Dictionary, expected: String) -> void:
	assert(not bool(result.get("ok", false)), str(result))
	var errors: Array = result.get("errors", [])
	assert(not errors.is_empty(), str(result))
	assert(str(errors[0]) == expected, "expected %s, got %s" % [expected, str(errors)])


func _write_text(path: String, contents: String) -> void:
	var absolute := _absolute(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	assert(file != null, "unable to create fixture: %s" % absolute)
	file.store_string(contents)
	file.close()


func _write_catalog(templates: Array) -> void:
	_write_text(TEST_CATALOG, JSON.stringify({"templates": templates}))


func _read_text(path: String) -> String:
	var file := FileAccess.open(_absolute(path), FileAccess.READ)
	assert(file != null, "unable to read fixture: %s" % path)
	var contents := file.get_as_text()
	file.close()
	return contents


func _remove_file(path: String) -> void:
	var absolute := _absolute(path)
	if FileAccess.file_exists(absolute):
		assert(DirAccess.remove_absolute(absolute) == OK)


func _remove_empty_recovery_root() -> void:
	var recovery := _absolute(TEST_ROOT.path_join(".recycle_bin"))
	if DirAccess.dir_exists_absolute(recovery):
		DirAccess.remove_absolute(recovery)


func _absolute(path: String) -> String:
	return PathSafety.absolute_path(path)


func _remove_tree(path: String) -> void:
	var absolute := _absolute(path)
	if absolute.is_empty():
		return
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
		return
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var dir := DirAccess.open(absolute)
	if dir == null:
		return
	dir.include_hidden = true
	dir.include_navigational = false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child := absolute.path_join(entry)
			if dir.is_link(entry) or not dir.current_is_dir():
				DirAccess.remove_absolute(child)
			else:
				_remove_tree(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(absolute)
