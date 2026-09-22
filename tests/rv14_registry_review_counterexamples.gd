extends Node
# Run with the official isolated-userdata test runner only. No real maps.
const Build := preload("res://scripts/map_editor/map_editor_build_runtime_service.gd")
const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
var errors: Array[String] = []
var checked := 0

func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()

func expect(value: bool, message: String) -> void:
	checked += 1
	if not value:
		errors.append(message)

func entry(key: String, mid: int, revision: Variant) -> Dictionary:
	return {"map_key": key, "runtime_map_id": mid,
		"runtime_path": "user://rv14_review/%s.runtime.json" % key,
		"approved_build_sha256": "a".repeat(64),
		"release_state": "implemented_playable", "display_name": key,
		"approval_revision": revision}

func envelope(tag: String, rows: Array) -> Dictionary:
	var registry := {"schema_version": 1,
		"registry_contract_id": "mse.map.runtime.release.v1", "maps": rows}
	return {"tag": tag, "registry": registry,
		"bytes": JSON.stringify(registry).to_utf8_buffer()}

func reject_both_orders(label: String, a: Dictionary, b: Dictionary) -> void:
	expect(Build._select_registry_backup_by_approval_evidence(a, b).is_empty(), label + ": forward")
	expect(Build._select_registry_backup_by_approval_evidence(b, a).is_empty(), label + ": reverse")

func write_bytes(path: String, data: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(data)
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return ok

func read_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes

func _run() -> void:
	var all_maps := envelope("all", [entry("A", 990041, 1), entry("B", 990042, 1)])
	var subset := envelope("subset", [entry("A", 990041, 2)])
	# Both pass the real schema validator: this is not a malformed-JSON case.
	expect(Bridge.validate_release_registry(all_maps.registry).is_empty(), "all maps fixture schema")
	expect(Bridge.validate_release_registry(subset.registry).is_empty(), "subset fixture schema")
	reject_both_orders("missing map must not be silently dropped", all_maps, subset)
	reject_both_orders("disjoint maps", envelope("a", [entry("A", 990041, 1)]), envelope("b", [entry("B", 990042, 2)]))
	var updated := envelope("updated", [entry("A", 990041, 2), entry("B", 990042, 1)])
	expect(Build._select_registry_backup_by_approval_evidence(all_maps, updated).get("tag", "") == "updated", "unchanged sibling allows update")
	expect(Build._select_registry_backup_by_approval_evidence(updated, all_maps).get("tag", "") == "updated", "update symmetric")
	var low := envelope("low", [entry("A", 990041, 1)])
	var high := envelope("high", [entry("A", 990041, 2)])
	expect(Build._select_registry_backup_by_approval_evidence(low, high).get("tag", "") == "high", "single map version ordering retained")
	reject_both_orders("map id changed", low, envelope("other id", [entry("A", 990099, 2)]))
	var moved: Dictionary = high.duplicate(true)
	moved.registry.maps[0].runtime_path = "user://rv14_review/other.runtime.json"
	reject_both_orders("path changed without migration evidence", low, moved)
	var missing: Dictionary = low.duplicate(true)
	missing.registry.maps[0].erase("approval_revision")
	reject_both_orders("missing revision", missing, high)
	for revision: Variant in [-1, 0, 1.25, "9", true, 9007199254740992]:
		reject_both_orders("invalid revision %s" % str(revision), envelope("bad", [entry("A", 990041, revision)]), high)
	var divergent: Dictionary = low.duplicate(true)
	divergent.registry.maps[0].display_name = "different"
	reject_both_orders("equal revision with different payload", low, divergent)
	reject_both_orders("crossed revisions", updated, envelope("crossed", [entry("A", 990041, 1), entry("B", 990042, 2)]))
	var extra_header: Dictionary = high.duplicate(true)
	extra_header.registry["unversioned_metadata"] = "changed"
	reject_both_orders("top-level unversioned conflict", low, extra_header)

	# Real recovery ENTRY: no main file, valid .bak contains A+B, valid
	# .restore_bak contains only A at higher revision. Do not restore either.
	var root := "user://rv14_review_%d/" % Time.get_ticks_usec()
	expect(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root)) == OK, "scratch directory")
	var path := root + "registry.json"
	var a_bytes: PackedByteArray = all_maps.bytes
	var b_bytes: PackedByteArray = subset.bytes
	expect(write_bytes(path + ".bak", a_bytes), "write .bak")
	expect(write_bytes(path + ".restore_bak", b_bytes), "write .restore_bak")
	var recovered := Build._read_registry(path)
	expect(not bool(recovered.get("ok", false)), "entry must refuse unequal map sets")
	expect(str(recovered.get("reason", "")) == "release_registry_backup_conflict", "entry explicit conflict")
	expect(not FileAccess.file_exists(path), "conflict must not create main registry")
	expect(read_bytes(path + ".bak") == a_bytes, ".bak preserved byte-for-byte")
	expect(read_bytes(path + ".restore_bak") == b_bytes, ".restore_bak preserved byte-for-byte")

	# Nonempty expected backup path != first-publish/no-backup cleanup.
	var formal := root + "runtime.json"
	var formal_before := "candidate survives missing rollback source".to_utf8_buffer()
	expect(write_bytes(formal, formal_before), "write rollback fixture")
	var restored := Build._restore_runtime(formal, ProjectSettings.globalize_path(root + "missing.bak"))
	expect(not bool(restored.get("ok", false)), "missing expected backup cannot report recovered")
	expect(read_bytes(formal) == formal_before, "missing expected backup cannot delete formal")
	# Fresh first-publish rollback still removes its new artifact.
	if not FileAccess.file_exists(formal):
		expect(write_bytes(formal, formal_before), "restore first-publish fixture after baseline red")
	var first_publish := Build._restore_runtime(formal, "")
	expect(bool(first_publish.get("ok", false)) and not FileAccess.file_exists(formal), "first publish rollback behavior retained")
	for message: String in errors:
		push_error("RV14_REGISTRY_REVIEW: " + message)
	print("RV14_REGISTRY_REVIEW_%s checks=%d failures=%d" % ["PASS" if errors.is_empty() else "FAIL", checked, errors.size()])
	get_tree().quit(0 if errors.is_empty() else 1)
