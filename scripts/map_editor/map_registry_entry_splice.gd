extends RefCounted
## Single-map registry splice. Does not access the filesystem.
## Every byte outside the replaced/inserted map object is retained.

static func replace_entry(
	old_text: String,
	expected: Dictionary,
	map_key: String,
	runtime_map_id: int,
	encoded_target: String
) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(old_text) != OK or not parser.data is Dictionary:
		return _failure("old_registry_invalid")
	var root: Dictionary = parser.data
	if not root.get("maps") is Array or not expected.get("maps") is Array:
		return _failure("maps_array_invalid")
	var expected_target: Dictionary = {}
	var expected_matches := 0
	for value: Variant in expected.maps:
		if not value is Dictionary:
			return _failure("map_entry_invalid")
		if str(value.get("map_key", "")) == map_key and _id_equal(value.get("runtime_map_id"), runtime_map_id):
			expected_target = value
			expected_matches += 1
	if expected_matches != 1:
		return _failure("expected_target_not_unique")
	var target_parser := JSON.new()
	if target_parser.parse(encoded_target) != OK or not _equivalent(target_parser.data, expected_target):
		return _failure("encoded_target_mismatch")
	var members := _object_members(old_text, _skip_space(old_text, 0))
	if not bool(members.get("valid", false)):
		return members
	var spans: Dictionary = members.spans
	if not spans.has("maps"):
		return _failure("maps_missing")
	var maps_span: Vector2i = spans.maps
	var cursor := _skip_space(old_text, maps_span.x + 1)
	var target_start := -1
	var target_end := -1
	var entry_count := 0
	while cursor < maps_span.y and old_text[cursor] != "]":
		var end := _value_end(old_text, cursor)
		if end < 0:
			return _failure("map_entry_span_invalid")
		var entry_members := _object_members(old_text, cursor)
		if not bool(entry_members.get("valid", false)):
			return entry_members
		var entry: Variant = JSON.parse_string(old_text.substr(cursor, end - cursor))
		if not entry is Dictionary:
			return _failure("map_entry_not_object")
		var matches_key := str(entry.get("map_key", "")) == map_key
		var matches_id := _id_equal(entry.get("runtime_map_id"), runtime_map_id)
		if matches_key or matches_id:
			if not matches_key or not matches_id or target_start >= 0:
				return _failure("identity_collision_or_duplicate")
			target_start = cursor
			target_end = end
		entry_count += 1
		cursor = _skip_space(old_text, end)
		if cursor < old_text.length() and old_text[cursor] == ",":
			cursor = _skip_space(old_text, cursor + 1)
	var candidate := ""
	if target_start >= 0:
		candidate = old_text.substr(0, target_start) + encoded_target.strip_edges() + old_text.substr(target_end)
	else:
		if cursor >= old_text.length() or old_text[cursor] != "]":
			return _failure("maps_close_missing")
		candidate = old_text.substr(0, cursor) + ("," if entry_count > 0 else "") + encoded_target.strip_edges() + old_text.substr(cursor)
	var candidate_parser := JSON.new()
	if candidate_parser.parse(candidate) != OK or not _equivalent(candidate_parser.data, expected):
		return _failure("candidate_differs_from_expected_registry")
	return {"valid": true, "text": candidate, "reason": ""}


static func _id_equal(value: Variant, expected: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == float(expected)


static func _equivalent(left: Variant, right: Variant) -> bool:
	if (left is int or left is float) and (right is int or right is float):
		return is_finite(float(left)) and is_finite(float(right)) and float(left) == float(right)
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _equivalent(left[key], right[key]):
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index in range(left.size()):
			if not _equivalent(left[index], right[index]):
				return false
		return true
	return typeof(left) == typeof(right) and left == right


static func _skip_space(text: String, start: int) -> int:
	var cursor := start
	while cursor < text.length() and text[cursor] in [" ", "\t", "\r", "\n"]:
		cursor += 1
	return cursor


static func _string_end(text: String, start: int) -> int:
	if start >= text.length() or text[start] != '"':
		return -1
	var cursor := start + 1
	while cursor < text.length():
		if text[cursor] == "\\":
			cursor += 2
		elif text[cursor] == '"':
			return cursor + 1
		else:
			cursor += 1
	return -1


static func _value_end(text: String, start: int) -> int:
	if start >= text.length():
		return -1
	if text[start] == '"':
		return _string_end(text, start)
	var cursor := start
	if text[start] in ["{", "["]:
		var depth := 0
		while cursor < text.length():
			if text[cursor] == '"':
				cursor = _string_end(text, cursor)
				if cursor < 0:
					return -1
				continue
			if text[cursor] in ["{", "["]:
				depth += 1
			elif text[cursor] in ["}", "]"]:
				depth -= 1
				if depth == 0:
					return cursor + 1
			cursor += 1
		return -1
	while cursor < text.length() and text[cursor] not in [",", "}", "]", " ", "\t", "\r", "\n"]:
		cursor += 1
	return cursor if cursor > start else -1


static func _object_members(text: String, start: int) -> Dictionary:
	if start >= text.length() or text[start] != "{":
		return _failure("object_expected")
	var cursor := _skip_space(text, start + 1)
	var spans: Dictionary = {}
	while cursor < text.length() and text[cursor] != "}":
		var key_end := _string_end(text, cursor)
		if key_end < 0:
			return _failure("key_span_invalid")
		var key: Variant = JSON.parse_string(text.substr(cursor, key_end - cursor))
		if not key is String or spans.has(key):
			return _failure("duplicate_or_invalid_key")
		cursor = _skip_space(text, key_end)
		if cursor >= text.length() or text[cursor] != ":":
			return _failure("colon_missing")
		var value_start := _skip_space(text, cursor + 1)
		var end := _value_end(text, value_start)
		if end < 0:
			return _failure("value_span_invalid")
		spans[key] = Vector2i(value_start, end)
		cursor = _skip_space(text, end)
		if cursor < text.length() and text[cursor] == ",":
			cursor = _skip_space(text, cursor + 1)
	if cursor >= text.length() or text[cursor] != "}":
		return _failure("object_close_missing")
	return {"valid": true, "spans": spans, "reason": ""}


static func _failure(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason, "text": ""}
