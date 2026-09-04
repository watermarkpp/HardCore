class_name MapEditorSpawnIdentityService
extends RefCounted

## Stable identity authority for map-editor ordinary and Boss placements.
##
## A spawn identity is derived from the formal map key, placement kind and a
## six-digit serial.  The serial is allocated from the existing identity set,
## never from the current array index.  Runtime slot consumption intentionally
## remains outside this service; the current GameRoot compatibility fallback
## is therefore not changed by adding these authoring identities.

const SPAWN_KINDS: Array[String] = ["monster_spawn", "boss_spawn"]
const FORMAL_SEMANTIC_PREFIX := "mse.placement.v1."
const FORMAL_GROUP_PREFIX := "mse.group.v1."
const FORMAL_CONTRACT_ID := "mse.spawn.identity.v1"

## Existing legacy maps are allowed to retain their historical semantic
## strings while they are migrated independently.  These are the maps whose
## current authoring identity defects are repaired by the focused migration;
## their formal semantic/group pair is therefore strict at save/build/publish.
const STRICT_FORMAL_MAPS := {
	"world_bich_province": true,
	"world_cangyue_island": true,
	"world_wooma_forest": true,
	"bich_orc_tomb_f1": true,
	"sandbox_64": true,
}


static func requires_formal_semantic_ids(value: Variant) -> bool:
	var map_id := ""
	if value is Dictionary:
		map_id = str((value as Dictionary).get("map_id", ""))
	else:
		map_id = str(value)
	return bool(STRICT_FORMAL_MAPS.get(map_id, false))


static func semantic_id_for(map_id: String, kind: String, serial: int) -> String:
	return "%s%s.%s.%06d" % [
		FORMAL_SEMANTIC_PREFIX,
		map_id,
		kind,
		serial,
	]


static func group_id_for_semantic(semantic_id: String) -> String:
	var parsed := _parse_formal_id(semantic_id, FORMAL_SEMANTIC_PREFIX)
	if parsed.is_empty():
		return ""
	return "%s%s.%s.%06d" % [
		FORMAL_GROUP_PREFIX,
		str(parsed.get("map_id", "")),
		str(parsed.get("kind", "")),
		int(parsed.get("serial", 0)),
	]


static func next_semantic_id(document: Dictionary, kind: String) -> String:
	var map_id := str(document.get("map_id", "")).strip_edges()
	var used_semantic := {}
	var used_group := {}
	var maximum := 0
	var layers: Dictionary = document.get("layers", {})
	var entries: Array = layers.get(kind, [])
	for raw_entry: Variant in entries:
		if not raw_entry is Dictionary:
			continue
		var semantic_id := str((raw_entry as Dictionary).get("semantic_id", ""))
		if not semantic_id.is_empty():
			used_semantic[semantic_id] = true
		var formal := _parse_formal_id(semantic_id, FORMAL_SEMANTIC_PREFIX)
		if (
			not formal.is_empty()
			and str(formal.get("map_id", "")) == map_id
			and str(formal.get("kind", "")) == kind
		):
			maximum = maxi(maximum, int(formal.get("serial", 0)))
			continue
		# Read the historical simple prefix only to avoid reusing its serial.
		# New records always receive the formal identity above.
		var legacy_prefix := kind + "_"
		if semantic_id.begins_with(legacy_prefix):
			var legacy_serial := semantic_id.trim_prefix(legacy_prefix)
			if _is_decimal(legacy_serial):
				maximum = maxi(maximum, legacy_serial.to_int())
		var group_id := str((raw_entry as Dictionary).get("spawn_group_id", ""))
		if not group_id.is_empty():
			used_group[group_id] = true
		var formal_group := _parse_formal_id(group_id, FORMAL_GROUP_PREFIX)
		if (
			not formal_group.is_empty()
			and str(formal_group.get("map_id", "")) == map_id
			and str(formal_group.get("kind", "")) == kind
		):
			maximum = maxi(maximum, int(formal_group.get("serial", 0)))
	var serial := maxi(1, maximum + 1)
	while (
		used_semantic.has(semantic_id_for(map_id, kind, serial))
		or used_group.has(group_id_for_semantic(semantic_id_for(map_id, kind, serial)))
	):
		serial += 1
	return semantic_id_for(map_id, kind, serial)


static func assign_new_identity(document: Dictionary, entry: Dictionary) -> Dictionary:
	var kind := str(entry.get("kind", ""))
	if kind not in SPAWN_KINDS:
		return {"ok": false, "errors": ["invalid_spawn_identity_kind"]}
	var semantic_id := next_semantic_id(document, kind)
	var group_id := group_id_for_semantic(semantic_id)
	if group_id.is_empty():
		return {"ok": false, "errors": ["spawn_identity_generation_failed"]}
	entry["semantic_id"] = semantic_id
	entry["spawn_group_id"] = group_id
	return {
		"ok": true,
		"semantic_id": semantic_id,
		"spawn_group_id": group_id,
	}


static func validate_document(
	document: Dictionary,
	require_formal_semantics := false
) -> Array[String]:
	var errors: Array[String] = []
	var map_id := str(document.get("map_id", "")).strip_edges()
	var strict := bool(require_formal_semantics)
	var seen_semantic := {}
	var seen_group := {}
	var layers: Dictionary = document.get("layers", {})
	for kind: String in SPAWN_KINDS:
		var raw_entries: Variant = layers.get(kind, [])
		if not raw_entries is Array:
			errors.append("spawn_layer_invalid:%s" % kind)
			continue
		for index in (raw_entries as Array).size():
			var raw_entry: Variant = (raw_entries as Array)[index]
			if not raw_entry is Dictionary:
				errors.append("spawn_entry_invalid:%s:%d" % [kind, index])
				continue
			var entry: Dictionary = raw_entry
			var semantic_id := str(entry.get("semantic_id", "")).strip_edges()
			if semantic_id.is_empty():
				errors.append("spawn_semantic_id_missing:%s:%d" % [kind, index])
			elif seen_semantic.has(semantic_id):
				errors.append("duplicate_spawn_semantic_id:%s" % semantic_id)
			else:
				seen_semantic[semantic_id] = true

			var group_id := str(entry.get("spawn_group_id", "")).strip_edges()
			if group_id.is_empty():
				errors.append("spawn_group_id_missing:%s:%d" % [kind, index])
			elif seen_group.has(group_id):
				errors.append("duplicate_spawn_group_id:%s" % group_id)
			else:
				seen_group[group_id] = true

			var parsed := _parse_formal_id(semantic_id, FORMAL_SEMANTIC_PREFIX)
			if parsed.is_empty():
				if strict:
					errors.append("spawn_semantic_id_not_formal:%s" % semantic_id)
				continue
			if str(parsed.get("map_id", "")) != map_id:
				errors.append("spawn_semantic_map_mismatch:%s" % semantic_id)
			if str(parsed.get("kind", "")) != kind:
				errors.append("spawn_semantic_kind_mismatch:%s" % semantic_id)
			var expected_group := group_id_for_semantic(semantic_id)
			if group_id != expected_group:
				errors.append("spawn_group_id_mismatch:%s" % semantic_id)
	return errors


static func validate_runtime(
	runtime: Dictionary,
	require_formal_semantics := false
) -> Array[String]:
	var source: Dictionary = runtime.get("source", {})
	var semantics: Dictionary = runtime.get("semantics", {})
	return validate_document(
		{"map_id": str(source.get("map_id", "")), "layers": semantics},
		require_formal_semantics
	)


static func repair_spawn_group_ids(document: Dictionary) -> int:
	## Repair only groups that can be deterministically derived from a formal
	## semantic ID.  Malformed semantic IDs remain visible to the strict gate.
	var repaired := 0
	var seen := {}
	var layers: Dictionary = document.get("layers", {})
	for kind: String in SPAWN_KINDS:
		var entries: Array = layers.get(kind, [])
		for index in entries.size():
			var entry: Dictionary = entries[index]
			var expected := group_id_for_semantic(str(entry.get("semantic_id", "")))
			if expected.is_empty():
				continue
			if str(entry.get("spawn_group_id", "")) != expected or seen.has(expected):
				entry["spawn_group_id"] = expected
				repaired += 1
			seen[expected] = true
		layers[kind] = entries
	return repaired


static func _parse_formal_id(value: String, prefix: String) -> Dictionary:
	if not value.begins_with(prefix):
		return {}
	var parts := value.split(".")
	if parts.size() != 6:
		return {}
	if parts[0] != "mse" or parts[1] != ("placement" if prefix == FORMAL_SEMANTIC_PREFIX else "group") or parts[2] != "v1":
		return {}
	if parts[3].is_empty() or parts[4] not in SPAWN_KINDS or not _is_six_digit_decimal(parts[5]):
		return {}
	var serial := parts[5].to_int()
	if serial <= 0:
		return {}
	return {"map_id": parts[3], "kind": parts[4], "serial": serial}


static func _is_six_digit_decimal(value: String) -> bool:
	if value.length() != 6:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if code < 48 or code > 57:
			return false
	return true


static func _is_decimal(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if code < 48 or code > 57:
			return false
	return true
