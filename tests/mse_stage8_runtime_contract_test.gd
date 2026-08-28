extends Node


func _ready() -> void:
	var document := MapEditorTypes.new_map("stage8_runtime", 990008, "Stage 8", Vector2i(32, 32))
	assert(MapEditorGroundService.initialize(document).ok)
	assert(MapEditorGameplaySemanticService.add_entry(document, "npc", Vector2i(2, 2), {"content_id": "npc.bich_guard", "npc_id": "npc.bich_guard"}).ok)
	assert(MapEditorGameplaySemanticService.add_entry(document, "door", Vector2i(3, 3), {"target_map_id": "bich_province", "target_tile": [7, 7]}).ok)
	# Keep this stage focused on runtime checksum/collision export.  The
	# palisade asset is intentionally non-placeable in the current catalog;
	# paint the equivalent authored collision directly instead of depending on
	# an unrelated asset-calibration state.
	var painted_collision_tile := Vector2i(8, 8)
	assert(MapEditorCollisionService.paint_collision_cell(document, painted_collision_tile).ok)
	assert(MapEditorCollisionService.paint_collision_cell(document, Vector2i(1, 1)).ok)
	assert(MapEditorCollisionService.erase_collision_cell(document, Vector2i(1, 1)).ok)
	assert(MapEditorBuildRuntimeService.approve_for_runtime(document).ok)
	var path := "user://stage8_runtime.runtime.json"
	assert(MapEditorBuildRuntimeService.build(document, path).ok)
	var loaded := MapEditorRuntimeMapService.load_runtime(path)
	assert(loaded.ok, str(loaded.get("errors", [])))
	assert(MapEditorRuntimeMapService.is_blocked(loaded.runtime, painted_collision_tile))
	assert(not MapEditorRuntimeMapService.is_blocked(loaded.runtime, Vector2i(0, 0)))
	assert(not MapEditorRuntimeMapService.is_blocked(loaded.runtime, Vector2i(1, 1)))
	assert(loaded.runtime.collision.erased_cells.size() == 1)
	assert(MapEditorRuntimeMapService.entries_at(loaded.runtime, Vector2i(2, 2), "npc").size() == 1)
	assert(MapEditorRuntimeMapService.entries_at(loaded.runtime, Vector2i(3, 3), "door")[0].target_map_id == "bich_province")
	_test_fast_checksum_matches_canonical(loaded.runtime, path)
	_test_formal_world_bich_raw_checksum()
	var tampered: Dictionary = (loaded.runtime as Dictionary).duplicate(true)
	tampered.collision.blocked_tiles.append("1,1")
	assert("runtime_checksum_invalid" in MapEditorRuntimeMapService.validate_runtime(tampered))
	print("MSE_STAGE8_RUNTIME_CONTRACT_PASS")
	get_tree().quit()


func _test_fast_checksum_matches_canonical(runtime: Dictionary, path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "stage8 runtime must be readable for raw checksum coverage")
	var raw_text := file.get_as_text()
	file.close()

	MapEditorRuntimeMapService.reset_validation_diagnostics()
	var fast_started_us := Time.get_ticks_usec()
	var fast_errors := MapEditorRuntimeMapService.validate_runtime(runtime, raw_text)
	var fast_elapsed_us := Time.get_ticks_usec() - fast_started_us
	var fast_diagnostics := MapEditorRuntimeMapService.validation_diagnostics()
	assert(fast_errors.is_empty(), "canonical raw checksum path must accept valid runtime")
	assert(
		int(fast_diagnostics.get("runtime_checksum_fast_path_count", 0)) == 1
		and int(fast_diagnostics.get("runtime_checksum_deep_encode_count", 0)) == 0,
		"canonical raw validation must avoid deep duplicate+encode: %s" % fast_diagnostics
	)

	# The same parsed object must produce the same result through the historical
	# canonical path, proving the raw shortcut is an optimization rather than a
	# second checksum definition.
	var canonical_errors := MapEditorRuntimeMapService.validate_runtime(runtime)
	var canonical_diagnostics := MapEditorRuntimeMapService.validation_diagnostics()
	assert(canonical_errors == fast_errors, "raw and canonical validation results diverged")
	assert(
		int(canonical_diagnostics.get("runtime_checksum_deep_encode_count", 0)) == 1,
		"canonical comparison must exercise the retained fallback"
	)

	# A safe-looking raw envelope with changed content and a stale claim must
	# fail closed after the raw digest mismatch and canonical fallback.
	var tampered_raw := raw_text.replace(
		"\"runtime_map_id\": 990008",
		"\"runtime_map_id\": 990009",
	)
	if tampered_raw == raw_text:
		tampered_raw = raw_text.replace(
			"\"runtime_map_id\": 990008.0",
			"\"runtime_map_id\": 990009.0",
		)
	assert(tampered_raw != raw_text, "tamper fixture must change runtime content")
	var tampered_parsed: Variant = JSON.parse_string(tampered_raw)
	assert(tampered_parsed is Dictionary, "tamper fixture must remain valid JSON")
	var tampered_errors := MapEditorRuntimeMapService.validate_runtime(
		tampered_parsed,
		tampered_raw,
	)
	assert(
		"runtime_checksum_invalid" in tampered_errors,
		"raw content tampering must be rejected"
	)

	# Formatting that is not provably codec-canonical must use the old semantic
	# check; the valid parsed object remains accepted and no raw hash is trusted.
	var noncanonical_raw := raw_text.replace(
		"{\n  \"build_sha256\"",
		"{ \"build_sha256\"",
	)
	assert(noncanonical_raw != raw_text, "noncanonical fixture must change envelope")
	var fallback_errors := MapEditorRuntimeMapService.validate_runtime(
		runtime,
		noncanonical_raw,
	)
	var fallback_diagnostics := MapEditorRuntimeMapService.validation_diagnostics()
	assert(fallback_errors.is_empty(), "canonical fallback must preserve valid runtime acceptance")
	assert(
		int(fallback_diagnostics.get("runtime_checksum_canonical_fallback_count", 0)) >= 2,
		"unsafe raw and tampered raw must use canonical fallback: %s" % fallback_diagnostics
	)
	print(
		"MSE_STAGE8_CHECKSUM_FAST_PASS fast_us=%d diagnostics=%s"
		% [fast_elapsed_us, fallback_diagnostics]
	)


func _test_formal_world_bich_raw_checksum() -> void:
	const formal_path := "res://assets/data/runtime/map_editor/world_bich_province.runtime.json"
	var file := FileAccess.open(formal_path, FileAccess.READ)
	assert(file != null, "formal world_bich runtime must be readable")
	var raw_text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw_text)
	assert(parsed is Dictionary, "formal world_bich runtime must parse")
	var runtime: Dictionary = parsed
	var prefix := "{\n  \"build_sha256\": \""
	assert(raw_text.begins_with(prefix), "formal world_bich runtime must be codec-canonical")
	var hash_start := prefix.length()
	var claimed_hash := raw_text.substr(hash_start, 64)
	var without_claimed_hash := raw_text.substr(0, hash_start) + raw_text.substr(hash_start + 64)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(without_claimed_hash.to_utf8_buffer())
	var computed_hash := hashing.finish().hex_encode()
	assert(
		computed_hash == claimed_hash,
		"world_bich raw checksum must exactly match its claimed build_sha256",
	)

	MapEditorRuntimeMapService.reset_validation_diagnostics()
	var started_us := Time.get_ticks_usec()
	var loaded := MapEditorRuntimeMapService.load_runtime(formal_path)
	var elapsed_us := Time.get_ticks_usec() - started_us
	var diagnostics := MapEditorRuntimeMapService.validation_diagnostics()
	assert(
		loaded.ok,
		"formal world_bich runtime must pass raw validation: %s"
		% str(loaded.get("errors", [])),
	)
	assert(
		int(diagnostics.get("runtime_checksum_fast_path_count", 0)) == 1
		and int(diagnostics.get("runtime_checksum_deep_encode_count", 0)) == 0,
		"formal world_bich first load must avoid deep checksum encode: %s" % diagnostics,
	)
	print(
		"WORLD_BICH_CHECKSUM_FAST_PASS bytes=%d elapsed_us=%d claimed=%s diagnostics=%s"
		% [raw_text.to_utf8_buffer().size(), elapsed_us, claimed_hash, diagnostics]
	)
