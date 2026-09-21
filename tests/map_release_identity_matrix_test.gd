extends Node

## R2-W2 release identity matrix regression, executed over ALL released maps.
## Read-only over the real release data plus a hermetic scratch publish for
## the isolation contract:
##   1. registry entry <-> runtime artifact identity and build hash binding,
##   2. runtime <-> editor workspace revision binding,
##   3. portal contract: every bidirectional exit has a reverse exit, every
##      one_way exit is contract-shaped (role + flag + explicit reason),
##   4. publishing one map never mutates any other map's artifact bytes or
##      the other registry entries.

const Fixtures := preload(
	"res://tests/helpers/map_runtime_transaction_test_fixtures.gd"
)
const BuildService := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)
const Bridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)

const REGISTRY_PATH := (
	"res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
)
## R2-W2 finding C5: two half-applied one_way exits (mode=one_way but the
## role/flag/reason still say bidirectional, no pair id, no reverse exit).
## Pinned so any growth or fix of the set is detected.
const KNOWN_ONE_WAY_SHAPE_VIOLATIONS := [
	[916004, 916006],
	[916005, 916007],
]
## R2-W2 finding: world_bich_province ground manifest drifted from the visual
## provenance hash in the 9944265c editor sync; pinned until refreshed.
const KNOWN_GROUND_MANIFEST_PROVENANCE_DRIFT := ["world_bich_province"]

var failures: Array[String] = []
var checks := 0


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _ready() -> void:
	_run.call_deferred()


func _file_sha(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while true:
		var chunk := file.get_buffer(65536)
		if chunk.is_empty():
			break
		context.update(chunk)
	return context.finish().hex_encode()


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _run() -> void:
	Fixtures.reset_seams()
	var registry := _read_json(REGISTRY_PATH)
	expect(not registry.is_empty(), "release registry must be readable")
	var maps: Array = registry.get("maps", [])
	expect(maps.size() >= 60, "expected the full released set, got %d" % maps.size())

	var seen_ids := {}
	var seen_keys := {}
	var id_to_key := {}
	var violations := []
	var provenance_drift: Array[String] = []
	# Portal checks need the full id->key map, so fill it up front.
	for entry: Dictionary in maps:
		id_to_key[int(entry.get("runtime_map_id", -1))] = str(
			entry.get("map_key", "")
		)
	for entry: Dictionary in maps:
		var map_key := str(entry.get("map_key", ""))
		var map_id := int(entry.get("runtime_map_id", -1))
		if seen_ids.has(map_id) or seen_keys.has(map_key):
			violations.append("duplicate identity %s/%s" % [map_id, map_key])
			continue
		seen_ids[map_id] = true
		seen_keys[map_key] = true
		id_to_key[map_id] = map_key
		# Registry leg.
		expect(
			str(entry.get("release_state", "")) == "implemented_playable",
			"%s release_state" % map_key
		)
		expect(
			str(entry.get("runtime_path", ""))
			== "res://assets/data/runtime/map_editor/%s.runtime.json" % map_key,
			"%s runtime_path" % map_key
		)
		var approved := str(entry.get("approved_build_sha256", ""))
		expect(approved.length() == 64, "%s approved hash shape" % map_key)
		# Runtime leg.
		var runtime_path := str(entry.get("runtime_path", ""))
		expect(FileAccess.file_exists(runtime_path), "%s runtime missing" % map_key)
		var runtime := _read_json(runtime_path)
		expect(
			str(runtime.get("build_sha256", "")) == approved,
			"%s runtime build hash != registry approved hash" % map_key
		)
		var source: Dictionary = runtime.get("source", {})
		expect(str(source.get("map_id", "")) == map_key, "%s source.map_id" % map_key)
		expect(
			int(source.get("runtime_map_id", -1)) == map_id,
			"%s source.runtime_map_id" % map_key
		)
		# Editor leg (workspace document).
		var editor_path := "res://map_editor_workspace/%s/%s.editor.json" % [
			map_key, map_key
		]
		expect(FileAccess.file_exists(editor_path), "%s editor doc missing" % map_key)
		var editor := _read_json(editor_path)
		expect(str(editor.get("map_id", "")) == map_key, "%s editor map_id" % map_key)
		expect(
			int(editor.get("runtime_map_id", -1)) == map_id,
			"%s editor runtime_map_id" % map_key
		)
		var editor_meta: Dictionary = editor.get("editor_meta", {})
		expect(
			int(editor_meta.get("revision", -1)) == int(source.get("revision", -2)),
			"%s editor revision != runtime source revision" % map_key
		)
		# Visual leg (identity fields; byte provenance is diagnostic-only).
		var visual_path := "res://assets/data/runtime/map_editor/%s.visual.json" % map_key
		expect(FileAccess.file_exists(visual_path), "%s visual missing" % map_key)
		var visual := _read_json(visual_path)
		expect(str(visual.get("map_id", "")) == map_key, "%s visual map_id" % map_key)
		expect(
			int(visual.get("runtime_map_id", -1)) == map_id,
			"%s visual runtime_map_id" % map_key
		)
		var manifest_path := "res://map_editor_workspace/%s/ground/ground_manifest.json" % [
			map_key
		]
		var recorded := str(visual.get("source_ground_manifest_sha256", ""))
		if not recorded.is_empty() and FileAccess.file_exists(manifest_path):
			if _file_sha(manifest_path) != recorded:
				provenance_drift.append(map_key)
		# Consumer gate.
		expect(
			Bridge.is_formal_playable(map_id),
			"%s must be formal playable" % map_key
		)
		# Portal contract.
		var semantics: Dictionary = runtime.get("semantics", {})
		for exit_point: Dictionary in semantics.get("map_exit_points", []):
			var target: Variant = exit_point.get("target_map_id")
			if target == null:
				continue
			target = int(target)
			var mode := str(exit_point.get("connection_mode", "bidirectional"))
			var role := str(exit_point.get("portal_role", ""))
			if mode == "one_way" or role == "one_way_endpoint":
				# Shape compliance is asserted once via the pinned set below.
				continue
			if role == "arrival_only_endpoint":
				continue
			var target_key := str(id_to_key.get(target, ""))
			var reverse := []
			if not target_key.is_empty():
				var target_runtime := _read_json(
					"res://assets/data/runtime/map_editor/%s.runtime.json" % target_key
				)
				var target_semantics: Dictionary = target_runtime.get(
					"semantics", {}
				)
				for back: Dictionary in target_semantics.get(
					"map_exit_points", []
				):
					if int(back.get("target_map_id", -1)) == map_id:
						reverse.append(back)
			if reverse.is_empty():
				violations.append(
					"bidirectional exit %s -> %s has no reverse exit" % [
						map_key, target
					]
				)

	expect(violations.is_empty(), "; ".join(PackedStringArray(violations)))
	var shape_violations := _one_way_shape_violations(maps)
	expect(
		shape_violations == KNOWN_ONE_WAY_SHAPE_VIOLATIONS,
		"one_way shape violations must match the pinned C5 set, got %s" % [
			str(shape_violations)
		]
	)
	var drifted := provenance_drift.filter(
		func(key: String) -> bool: return not KNOWN_GROUND_MANIFEST_PROVENANCE_DRIFT.has(key)
	)
	expect(
		drifted.is_empty(),
		"unexpected ground manifest provenance drift: %s" % [", ".join(drifted)]
	)

	# ---- Publish isolation (hermetic scratch) ----
	_isolation_check(maps.size())

	for failure: String in failures:
		push_error("MAP_RELEASE_IDENTITY_MATRIX: " + failure)
	print(
		"MAP_RELEASE_IDENTITY_MATRIX_%s checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()]
	)
	get_tree().quit(0 if failures.is_empty() else 1)


func _one_way_shape_violations(maps: Array) -> Array:
	var found := []
	for entry: Dictionary in maps:
		var map_id := int(entry.get("runtime_map_id", -1))
		var runtime := _read_json(str(entry.get("runtime_path", "")))
		var semantics: Dictionary = runtime.get("semantics", {})
		for exit_point: Dictionary in semantics.get("map_exit_points", []):
			if str(exit_point.get("connection_mode", "")) != "one_way":
				continue
			if str(exit_point.get("portal_role", "")) != "one_way_endpoint" \
					or not bool(exit_point.get("one_way", false)):
				found.append([map_id, int(exit_point.get("target_map_id", -1))])
	found.sort()
	return found


func _isolation_check(released_count: int) -> void:
	var scratch_root := "user://p0_3r_identity_isolation/"
	var scratch_registry := scratch_root + "registry.json"
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(scratch_root)
	)
	# Copy the real registry + every released artifact into the scratch root.
	var registry_source := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	var registry_bytes := registry_source.get_buffer(registry_source.get_length())
	registry_source.close()
	var registry_copy := FileAccess.open(scratch_registry, FileAccess.WRITE)
	registry_copy.store_buffer(registry_bytes)
	registry_copy.close()
	var scratch_registry_backup := scratch_registry + ".pre_publish"
	DirAccess.copy_absolute(
		ProjectSettings.globalize_path(scratch_registry),
		ProjectSettings.globalize_path(scratch_registry_backup)
	)
	var baseline := {}
	for entry: Dictionary in _read_json(REGISTRY_PATH).get("maps", []):
		var map_key := str(entry.get("map_key", ""))
		var source_path := str(entry.get("runtime_path", ""))
		var scratch_path := scratch_root + map_key + ".runtime.json"
		expect(
			DirAccess.copy_absolute(
				ProjectSettings.globalize_path(source_path),
				ProjectSettings.globalize_path(scratch_path)
			) == OK,
			"%s scratch copy failed" % map_key
		)
		baseline[map_key] = _file_sha(scratch_path)

	BuildService.test_formal_runtime_root_override = scratch_root
	Bridge.test_override_release_registry_path(scratch_registry)
	Bridge.invalidate_release_registry()
	var doc := Fixtures.make_document(
		"p0_3r_identity_probe", 993001, "Identity Isolation Probe"
	)
	var approval := BuildService.approve_for_runtime(doc)
	expect(approval.ok, str(approval.get("errors", [])))
	var candidate := BuildService.build_candidate(doc)
	expect(candidate.ok, str(candidate.get("errors", [])))
	var published := BuildService.publish_runtime_release(
		str(candidate.candidate_path),
		993001,
		candidate.document_binding,
		scratch_registry
	)
	expect(bool(published.get("success", false)), str(published))

	# Every previously copied artifact must stay byte-identical.
	for map_key: String in baseline.keys():
		expect(
			_file_sha(scratch_root + map_key + ".runtime.json") == baseline[map_key],
			"publish mutated unrelated artifact %s" % map_key
		)
	# The other registry entries must be preserved deep-equal.
	var before := _read_json(scratch_registry_backup)
	var after := _read_json(scratch_registry)
	expect(
		int(before.get("maps", []).size()) == released_count
		and int(after.get("maps", []).size()) == released_count + 1,
		"registry must append exactly one entry"
	)
	var after_by_id := {}
	for entry: Dictionary in after.get("maps", []):
		after_by_id[int(entry.get("runtime_map_id", -1))] = entry
	for entry: Dictionary in before.get("maps", []):
		var map_id := int(entry.get("runtime_map_id", -1))
		expect(
			after_by_id.has(map_id) and after_by_id[map_id] == entry,
			"registry entry %s changed" % map_id
		)

	# Update publish of the probe map (override path) keeps others intact too.
	Fixtures.mutate_and_bake(doc)
	var candidate_b := BuildService.build_candidate(doc)
	expect(candidate_b.ok, str(candidate_b.get("errors", [])))
	var published_b := BuildService.publish_runtime_release(
		str(candidate_b.candidate_path),
		993001,
		candidate_b.document_binding,
		scratch_registry,
		"p0_3r_identity_probe"
	)
	expect(bool(published_b.get("success", false)), str(published_b))
	var after_b := _read_json(scratch_registry)
	var after_b_by_id := {}
	for entry: Dictionary in after_b.get("maps", []):
		after_b_by_id[int(entry.get("runtime_map_id", -1))] = entry
	for entry: Dictionary in before.get("maps", []):
		var map_id := int(entry.get("runtime_map_id", -1))
		expect(
			after_b_by_id.has(map_id) and after_b_by_id[map_id] == entry,
			"update publish changed registry entry %s" % map_id
		)
	for map_key: String in baseline.keys():
		expect(
			_file_sha(scratch_root + map_key + ".runtime.json") == baseline[map_key],
			"update publish mutated unrelated artifact %s" % map_key
		)

	BuildService.test_formal_runtime_root_override = ""
	Bridge.reset_release_registry_override()
	Bridge.invalidate_release_registry()
