extends RefCounted

## Strict actual native mathematical boundary; no GD/native-missing fallback.
const Codec := preload("res://scripts/gameplay/world/world_environment_transport_codec.gd")

static func copy_and_seal(value: Variant) -> Dictionary:
	if not ClassDB.class_exists("HardCoreContentValueGraph"):
		return {"ok": false, "errors": ["native_math_value_graph_missing"]}
	var encoded: Dictionary = Codec.encode(value)
	if not encoded.ok:
		return encoded
	var native: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph") as RefCounted
	if native == null or not native.has_method("capture"):
		return {"ok": false, "errors": ["native_math_value_graph_invalid"]}
	var captured: Dictionary = native.call("capture", encoded.wire, true, false)
	if not bool(captured.get("success", false)):
		return {"ok": false, "errors": captured.get("errors", [])}
	return Codec.decode(captured.value)
