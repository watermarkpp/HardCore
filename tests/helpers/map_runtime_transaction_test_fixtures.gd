class_name MapRuntimeTransactionFixtures
extends RefCounted

const BuildService := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)
const Bridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)
const JsonCodec := preload(
	"res://scripts/map_editor/map_editor_json_codec.gd"
)


static func reset_seams() -> void:
	Bridge.reset_release_registry_override()
	BuildService.test_formal_runtime_root_override = ""
	BuildService.test_fail_runtime_promote = false
	BuildService.test_fail_registry_commit = false
	BuildService.test_fail_post_publish_verify = false


static func make_document(
	map_key: String,
	runtime_map_id: int,
	display_name: String
) -> Dictionary:
	var document := MapEditorTypes.new_map(
		map_key, runtime_map_id, display_name, Vector2i(32, 32)
	)
	document.editor_meta.workspace = (
		"user://p0_3r_%s_%d" % [map_key, Time.get_ticks_usec()]
	)
	var ground := MapEditorGroundService.initialize(document)
	assert(ground.ok, str(ground.get("errors", [])))
	var npc := MapEditorGameplaySemanticService.add_entry(
		document, "npc", Vector2i(3, 3),
		{"content_id": "npc.bich_guard", "npc_id": "npc.bich_guard"}
	)
	var door := MapEditorGameplaySemanticService.add_entry(
		document, "door", Vector2i(4, 4),
		{"target_map_id": "bich_province", "target_tile": [8, 8]}
	)
	var entrance := MapEditorGameplaySemanticService.add_entry(
		document, "map_entrance", Vector2i(5, 5), {"display_name": "测试入口"}
	)
	var map_exit := MapEditorGameplaySemanticService.add_entry(
		document, "map_exit", Vector2i(6, 5),
		{
			"target_map_id": "bich_province",
			"target_entrance_id": str(entrance.entry.semantic_id),
		}
	)
	var respawn := MapEditorGameplaySemanticService.add_entry(
		document, "respawn_point", Vector2i(7, 7),
		{"display_name": "出生复活点"}
	)
	var safe := MapEditorGameplaySemanticService.add_entry(
		document, "safe_area", Vector2i(7, 7), {
			"shape": "polygon",
			"polygon_ground_gu": [[5, 5], [9, 5], [9, 9], [5, 9]],
			"radius_gu": 0.0,
		}
	)
	assert(
		npc.ok and door.ok and entrance.ok and map_exit.ok
		and respawn.ok and safe.ok,
		"semantic setup failed: %s"
		% str({
			"npc": npc,
			"door": door,
			"entrance": entrance,
			"exit": map_exit,
			"respawn": respawn,
			"safe": safe,
		})
	)
	return document


static func mutate_and_bake(document: Dictionary) -> void:
	var paint := MapEditorGroundService.record_tile_paint(
		document, Vector2i(2, 2), "ground.dark_grass.001"
	)
	assert(paint.ok, str(paint.get("errors", [])))
	var bake := MapEditorChunkBakeService.bake_dirty_chunks(document)
	assert(bake.ok, str(bake.get("errors", [])))


static func write_registry(path: String, maps: Array) -> void:
	write_json(path, {
		"schema_version": 1,
		"registry_contract_id": "mse.map.runtime.release.v1",
		"maps": maps,
	})


static func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "cannot write %s" % path)
	file.store_string(JsonCodec.encode(value))
	file.close()


static func read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "cannot read %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


static func file_sha256(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "cannot read %s" % path)
	var text := file.get_as_text()
	file.close()
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(text.to_utf8_buffer())
	return hashing.finish().hex_encode()


static func make_entry(
	map_id: int,
	map_key: String,
	approved: String,
	runtime_path: String,
	revision: int,
	state := "implemented_playable"
) -> Dictionary:
	return {
		"runtime_map_id": map_id,
		"map_key": map_key,
		"display_name": map_key,
		"runtime_path": runtime_path,
		"release_state": state,
		"approved_build_sha256": approved,
		"approval_source": "test_fixture",
		"approval_revision": revision,
	}
