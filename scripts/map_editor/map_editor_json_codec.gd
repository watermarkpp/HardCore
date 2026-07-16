class_name MapEditorJsonCodec
extends RefCounted


static func encode(document: Dictionary) -> String:
	return JSON.stringify(_canonicalize(document), "  ", true, true) + "\n"


static func decode(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


static func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		for key: Variant in keys:
			result[key] = _canonicalize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_canonicalize(item))
		return result
	return value
