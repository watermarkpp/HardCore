class_name MapEditorUnitLegacyAdapter
extends RefCounted

const CONTRACT_ID := "map.editor.unit_legacy_adapter.v1"
const LEGACY_EDITOR_SCHEMA_VERSION := 4
const EDITOR_SCHEMA_VERSION := 5
const LEGACY_RUNTIME_SCHEMA_VERSION := 1
const RUNTIME_SCHEMA_VERSION := 2
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

const _RADIUS_KINDS := [
	"monster_spawn", "boss_spawn", "safe_area", "light", "region_trigger",
]
const _POLYGON_KINDS := ["safe_area", "light", "region_trigger"]
const _PORTAL_KINDS := ["door", "map_exit"]


static func upgrade_editor_document_v4(document: Dictionary) -> Dictionary:
	var upgraded := document.duplicate(true)
	if int(upgraded.get("schema_version", -1)) != LEGACY_EDITOR_SCHEMA_VERSION:
		return upgraded
	var layers: Dictionary = upgraded.get("layers", {})
	for layer_name: String in layers:
		var entries: Variant = layers.get(layer_name, [])
		if not entries is Array:
			continue
		var adapted_entries: Array = []
		for source_entry: Variant in entries:
			adapted_entries.append(
				_adapt_legacy_semantic_entry(source_entry)
				if source_entry is Dictionary
				else source_entry
			)
		layers[layer_name] = adapted_entries
	upgraded["layers"] = layers
	upgraded["schema_version"] = EDITOR_SCHEMA_VERSION
	var meta: Dictionary = upgraded.get("editor_meta", {})
	meta["source_editor_schema_version"] = LEGACY_EDITOR_SCHEMA_VERSION
	meta["unit_legacy_adapter_id"] = CONTRACT_ID
	upgraded["editor_meta"] = meta
	return upgraded


static func editor_semantic_to_runtime_v2(source_entry: Dictionary) -> Dictionary:
	# Schema 5 authoring already uses formal GU names. This copy is the only
	# editor-to-runtime unit boundary; it never guesses units from screen pixels.
	var entry := source_entry.duplicate(true)
	var kind := str(entry.get("kind", ""))
	if kind in _RADIUS_KINDS and not entry.has("radius_gu"):
		entry["radius_gu"] = 0.0
	if kind in _POLYGON_KINDS and not entry.has("polygon_ground_gu"):
		entry["polygon_ground_gu"] = []
	if kind in _PORTAL_KINDS and not entry.has("return_unlock_distance_gu"):
		entry["return_unlock_distance_gu"] = 0.0
	return entry


static func adapt_runtime_v1_to_v2(raw_runtime: Dictionary) -> Dictionary:
	var runtime := raw_runtime.duplicate(true)
	runtime["source_runtime_schema_version"] = LEGACY_RUNTIME_SCHEMA_VERSION
	runtime["unit_legacy_adapter_id"] = CONTRACT_ID
	runtime["runtime_schema_version"] = RUNTIME_SCHEMA_VERSION
	runtime["unit_contract_id"] = GroundUnitSpaceScript.CONTRACT_ID
	runtime["projection_contract_id"] = GroundUnitSpaceScript.PROJECTION_CONTRACT_ID
	var semantics: Dictionary = runtime.get("semantics", {})
	for layer_name: String in semantics:
		var adapted_entries: Array = []
		for source_entry: Dictionary in semantics.get(layer_name, []):
			adapted_entries.append(_adapt_legacy_semantic_entry(source_entry))
		semantics[layer_name] = adapted_entries
	runtime["semantics"] = semantics
	return runtime


static func validate_runtime_v2_has_no_legacy_unit_fields(
	runtime: Dictionary
) -> Array[String]:
	var errors: Array[String] = []
	for layer_name: String in runtime.get("semantics", {}):
		for entry: Dictionary in runtime.semantics.get(layer_name, []):
			var kind := str(entry.get("kind", ""))
			var semantic_id := str(entry.get("semantic_id", kind))
			if kind in _RADIUS_KINDS and entry.has("radius_tiles"):
				errors.append("runtime_legacy_radius_forbidden:%s" % semantic_id)
			if kind in _POLYGON_KINDS and entry.has("polygon_tiles"):
				errors.append("runtime_legacy_polygon_forbidden:%s" % semantic_id)
			if kind in _PORTAL_KINDS and entry.has(
				"return_unlock_distance_tiles"
			):
				errors.append(
					"runtime_legacy_portal_distance_forbidden:%s" % semantic_id
				)
	return errors


static func _adapt_legacy_semantic_entry(
	source_entry: Dictionary
) -> Dictionary:
	var entry := source_entry.duplicate(true)
	var kind := str(entry.get("kind", ""))
	if kind in _RADIUS_KINDS:
		entry["radius_gu"] = float(entry.get(
			"radius_gu", entry.get("radius_tiles", 0.0)
		))
		entry.erase("radius_tiles")
	if kind in _POLYGON_KINDS:
		entry["polygon_ground_gu"] = entry.get(
			"polygon_ground_gu", entry.get("polygon_tiles", [])
		).duplicate(true)
		entry.erase("polygon_tiles")
	if kind in _PORTAL_KINDS:
		entry["return_unlock_distance_gu"] = float(entry.get(
			"return_unlock_distance_gu",
			entry.get("return_unlock_distance_tiles", 0.0)
		))
		entry.erase("return_unlock_distance_tiles")
	return entry
