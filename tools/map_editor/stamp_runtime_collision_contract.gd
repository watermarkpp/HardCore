extends SceneTree

const RUNTIME_DIRECTORY := "res://assets/data/runtime/map_editor"
const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)
const JsonCodec := preload(
	"res://scripts/map_editor/map_editor_json_codec.gd"
)


func _init() -> void:
	var stamped := 0
	for file_name: String in DirAccess.get_files_at(RUNTIME_DIRECTORY):
		if not file_name.ends_with(".runtime.json"):
			continue
		if file_name == "bich_v15_sample.runtime.json":
			continue
		var path := RUNTIME_DIRECTORY.path_join(file_name)
		var file := FileAccess.open(path, FileAccess.READ)
		assert(file != null, path)
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		assert(parsed is Dictionary, path)
		var runtime: Dictionary = parsed
		var collision: Dictionary = runtime.get("collision", {})
		collision["coordinate_contract_id"] = (
			CollisionGeometry.CONTRACT_ID
		)
		collision["physics_source_id"] = (
			CollisionGeometry.PHYSICS_SOURCE_ID
		)
		runtime["collision"] = collision
		runtime["build_sha256"] = ""
		runtime["build_sha256"] = _sha256(
			JsonCodec.encode(runtime)
		)
		file = FileAccess.open(path, FileAccess.WRITE)
		assert(file != null, path)
		file.store_string(JsonCodec.encode(runtime))
		file.close()
		stamped += 1
	print("STAMP_RUNTIME_COLLISION_CONTRACT_PASS maps=%d" % stamped)
	quit(0)


func _sha256(text: String) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(text.to_utf8_buffer())
	return hashing.finish().hex_encode()
