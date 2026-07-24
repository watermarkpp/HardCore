extends Node

const CATALOG_PATH := "res://outputs/resource_catalog/complete_client_frame_catalog/manifest.json"
const HELMET_SOURCE_PATH := "res://assets/art/characters/warrior/wear/helmet/black_iron_helmet.source.json"


func _ready() -> void:
	var catalog := _read_json(CATALOG_PATH)
	assert(int(catalog.get("libraryCount", 0)) == 122, "complete client library count changed")
	assert(int(catalog.get("indexedFramesScanned", 0)) == 962251, "complete client frame scan is incomplete")
	assert(int(catalog.get("validFrames", 0)) == 962250, "complete client valid frame count changed")
	assert(int(catalog.get("decodedHeadCandidates", 0)) == 332460, "head candidate scan is incomplete")
	assert(str(catalog.get("database", "")).ends_with("frame_catalog.sqlite"), "frame catalog SQLite path is missing")

	var helmet := _read_json(HELMET_SOURCE_PATH)
	assert(int(helmet.get("schemaVersion", 0)) == 16, "black iron helmet provenance schema must be v16")
	assert(str(helmet.get("classification", "")).begins_with("project-generated"), "generated helmet must remain separated from original client resources")
	assert(int(helmet.get("referenceIconImage", -1)) == 344, "black iron helmet identity must remain StateItem #344")
	assert(bool(helmet.get("generation", {}).get("aiGenerated", false)), "direct approved-design pixels must be recorded")
	assert(bool(helmet.get("generation", {}).get("aiConceptUsed", false)), "approved meteoric concept must be recorded")
	assert((helmet.get("generation", {}).get("aiPixelsLimitedTo", []) as Array) == ["idle", "walk", "attack", "cast", "hit"], "approved-design pixels must be limited to standing/action atlases")
	var pixel_generator := str(helmet.get("generation", {}).get("runtimePixelGenerator", ""))
	assert(pixel_generator.contains("Direct approved-design crops"), "standing/action helmet must use the approved design directly")
	assert(pixel_generator.contains("Godot 4.7"), "death helmet must use the Godot orthographic renderer")
	assert(not bool(helmet.get("generation", {}).get("oldDerivedStateItemWorldPixelsUsed", true)), "runtime atlas must not mix old StateItem-derived world pixels")
	var direction_references: Dictionary = helmet.get("approvedDirectionReferences", {})
	assert(str(direction_references.get("approvedConcept", "")).ends_with("black_iron_helmet_approved_meteoric_narrow_jaw_20260717.png"), "approved narrow-jaw meteoric concept is missing from provenance")
	assert((direction_references.get("sourceSlotDirectionOrder", []) as Array) == ["N", "E", "W", "SW", "S", "SE", "NW", "NE"], "approved source-slot facing classification changed")
	var source_slots: Array = direction_references.get("canonicalRowSourceSlots", [])
	var expected_source_slots := [0, 7, 1, 5, 4, 3, 2, 6]
	assert(source_slots.size() == expected_source_slots.size(), "approved source-slot mapping length changed")
	for direction_index in range(expected_source_slots.size()):
		assert(int(source_slots[direction_index]) == expected_source_slots[direction_index], "approved source slot is not mapped to canonical game row %d" % direction_index)
	assert(str(direction_references.get("godotRenderer", "")).ends_with("render_black_iron_helmet_3d.gd"), "Godot helmet renderer is missing from provenance")
	assert(is_equal_approx(float(helmet.get("generation", {}).get("runtimeEnvelopeScale", 0.0)), 1.0), "black iron helmet must use the client median size without arbitrary scale")
	assert(is_equal_approx(float(helmet.get("generation", {}).get("visualMassTargetMultiplier", 0.0)), 1.15), "black iron helmet visual mass must be calibrated to 1.15x the client median")
	assert(int(helmet.get("clientHelmetParameterBaseline", {}).get("poseAnchorRecords", 0)) == 232, "Helmet.wil same-cell anchor table must cover all 232 frames")
	assert(int(helmet.get("clientHelmetParameterBaseline", {}).get("outlierFilteredPoseRecords", 0)) > 0, "non-head Helmet.wil pose clusters must be filtered")
	assert(int(helmet.get("deathPoseBaseline", {}).get("records", 0)) == 32, "death helmet mapping must cover 8 directions x 4 frames")
	assert(int(helmet.get("completeClientCoverage", {}).get("indexedFrames", 0)) == 962251, "helmet provenance must bind the complete client scan")
	for action_name in ["idle", "walk", "attack", "cast", "hit", "death"]:
		var action: Dictionary = helmet.get("actions", {}).get(action_name, {})
		assert(int(action.get("directions", 0)) == 8, "%s helmet must contain eight directions" % action_name)
		assert((action.get("directionSignatures", []) as Array).size() == 8, "%s direction signatures are missing" % action_name)
	assert(ArtSpec.PLAYER_HEALTH_BAR_OFFSET == Vector2(-8.0, -95.0), "player health bar offset changed")
	print("COMPLETE_CLIENT_RESOURCE_CATALOG_PASS")
	get_tree().quit(0)


func _read_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "file is missing: %s" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary, "invalid JSON: %s" % path)
	return parsed
