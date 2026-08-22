class_name MonsterGroundAlignmentDraft
extends RefCounted

const CONTRACT_ID := "local.visual_acceptance_lab.monster_ground_alignment_draft.v1"
const ANIMATION_CATALOG_PATH := (
	"res://assets/data/runtime/monster_animation_catalog.json"
)
const FORMAL_CONTACT_PATH := (
	"res://assets/data/runtime/monster_ground_contacts.json"
)
const FORMAL_CALIBRATION_PATH := (
	"res://assets/data/runtime/monster_ground_contact_calibrations.json"
)
const MANUAL_ALIGNMENT_DATA_PATH := (
	"res://assets/data/runtime/monster_ground_alignment_manual_v1.json"
)
const DRAFT_ROOT := (
	"res://outputs/visual_acceptance/monster_ground_alignment_drafts"
)


static func catalog_rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in _load_json(
		ANIMATION_CATALOG_PATH
	).get("monsters", []):
		if value is Dictionary:
			result.append(value.duplicate(true))
	return result


static func formal_entry(monster_id: int) -> Dictionary:
	# The validator needs one read-only view of all three formal authorities:
	# contact geometry is the base, calibration is the reviewed runtime
	# projection, and the manual contract contributes the saved pose/offset.
	# Keep the contact entry as the base so preserved airborne monsters remain
	# visible even though they intentionally have no manual draft.
	var result := contact_entry(monster_id)
	result.merge(calibration_entry(monster_id), true)
	result.merge(manual_entry(monster_id), true)
	return result


static func contact_entry(monster_id: int) -> Dictionary:
	return _entry_from_contract(FORMAL_CONTACT_PATH, monster_id)


static func calibration_entry(monster_id: int) -> Dictionary:
	return _entry_from_contract(FORMAL_CALIBRATION_PATH, monster_id)


static func manual_entry(monster_id: int) -> Dictionary:
	return _entry_from_contract(MANUAL_ALIGNMENT_DATA_PATH, monster_id)


static func draft_path(monster_id: int, root_override := "") -> String:
	var root := DRAFT_ROOT if root_override.is_empty() else root_override
	return root.path_join("monster_%d.json" % monster_id)


static func load_draft(monster_id: int, root_override := "") -> Dictionary:
	var parsed := _load_json(draft_path(monster_id, root_override))
	if (
		str(parsed.get("contractId", "")) != CONTRACT_ID
		or int(parsed.get("monsterId", -1)) != monster_id
	):
		parsed = {}
	# An explicit root is used by the single-target draft test and by callers
	# that intentionally inspect a local draft sandbox. The project root is
	# stricter: only a draft whose immutable source hash and formal evidence
	# still match the imported manual contract may override the formal replay.
	if not parsed.is_empty() and (
		(not root_override.is_empty())
		or draft_is_formal(monster_id, parsed, root_override)
	):
		return parsed
	if root_override.is_empty():
		return _draft_from_manual_entry(monster_id)
	return {}


static func draft_is_formal(
	monster_id: int,
	draft: Dictionary,
	root_override := "",
) -> bool:
	if (
		str(draft.get("contractId", "")) != CONTRACT_ID
		or int(draft.get("monsterId", -1)) != monster_id
	):
		return false
	var manual := manual_entry(monster_id)
	var expected_hash := str(manual.get("sourceDraftSha256", ""))
	if expected_hash.is_empty():
		return false
	var path := draft_path(monster_id, root_override)
	if not (
		FileAccess.file_exists(path)
		and FileAccess.get_sha256(path) == expected_hash
	):
		return false
	return _source_evidence_matches(draft, manual)


static func _draft_from_manual_entry(monster_id: int) -> Dictionary:
	var manual := manual_entry(monster_id)
	if (
		manual.is_empty()
		or str(manual.get("contractId", "")) != CONTRACT_ID
	):
		return {}
	var selection: Variant = manual.get("selection", {})
	if not selection is Dictionary:
		selection = {}
	var source_evidence: Variant = manual.get("sourceEvidence", {})
	if not source_evidence is Dictionary:
		source_evidence = {}
	var formal_snapshot: Variant = manual.get("formalSnapshot", {})
	if not formal_snapshot is Dictionary:
		formal_snapshot = {}
	var visual_root := _array_copy(manual.get("visualRootOffset", []))
	var visual_foot := _array_copy(manual.get("visualFootOffset", []))
	var final_foot := _array_copy(manual.get("finalVisualFootPoint", []))
	var physics := _array_copy(manual.get("physicsFootprintRadii", []))
	return {
		"contractId": CONTRACT_ID,
		"savedAt": str(manual.get("savedAt", "")),
		"scope": "single_formal_monster_visual",
		"monsterId": monster_id,
		"monsterName": str(manual.get("monsterName", "")),
		"selection": selection.duplicate(true),
		"runtimeVisualOrigin": _array_copy(
			manual.get("runtimeVisualOrigin", [])
		),
		"visualOffset": visual_root,
		"pickedVisualFootOffset": visual_foot,
		"finalVisualFootPoint": final_foot,
		"canonicalCenters": {
			"actorGroundOrigin": [0.0, 0.0],
			"physicsFootprint": [0.0, 0.0],
			"mapDiamond": [0.0, 0.0],
		},
		"physicsFootprintRadii": physics,
		"recommendedRuntime": {
			"visualRootOffset": visual_root.duplicate(),
			"visualFootOffset": visual_foot.duplicate(),
			"ringCenterOffset": _array_copy(
				manual.get("ringCenterOffset", visual_foot)
			),
		},
		"formalSnapshot": formal_snapshot.duplicate(true),
		"sourceEvidence": source_evidence.duplicate(true),
		"formalRuntimeWritten": false,
		"replaySource": "formal_manual_alignment_v1",
	}


static func _source_evidence_matches(
	draft: Dictionary,
	manual: Dictionary,
) -> bool:
	var expected: Variant = manual.get("sourceEvidence", {})
	var actual: Variant = draft.get("sourceEvidence", {})
	if not expected is Dictionary or not actual is Dictionary:
		return false
	for key in [
		"animationCatalogPath",
		"formalCalibrationPath",
		"formalContactPath",
	]:
		var path := str(expected.get(key, ""))
		var expected_hash := str(expected.get("%sSha256" % key.trim_suffix("Path"), ""))
		if path.is_empty() or expected_hash.is_empty():
			return false
		if str(actual.get(key, "")) != path:
			return false
		if str(actual.get("%sSha256" % key.trim_suffix("Path"), "")) != expected_hash:
			return false
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != expected_hash:
			return false
	return true


static func _entry_from_contract(path: String, monster_id: int) -> Dictionary:
	var value: Variant = _load_json(path).get(
		"entriesByMonsterId", {}
	).get(str(monster_id), {})
	return value.duplicate(true) if value is Dictionary else {}


static func _array_copy(value: Variant) -> Array:
	return value.duplicate(true) if value is Array else []


static func build_payload(
	monster_id: int,
	selection: Dictionary,
	runtime_visual_origin: Vector2,
	visual_offset: Vector2,
	picked_visual_foot_offset: Vector2,
	physics_footprint_radii: Vector2,
) -> Dictionary:
	var formal := formal_entry(monster_id)
	if formal.is_empty():
		return {}
	var final_visual_foot_point := (
		runtime_visual_origin
		+ visual_offset
		+ picked_visual_foot_offset
	)
	var final_visual_origin := runtime_visual_origin + visual_offset
	return {
		"contractId": CONTRACT_ID,
		"savedAt": Time.get_datetime_string_from_system(),
		"scope": "single_formal_monster_visual",
		"monsterId": monster_id,
		"monsterName": str(formal.get("name", "")),
		"selection": {
			"action": str(selection.get("action", "idle")),
			"direction": int(selection.get("direction", 0)),
			"frame": int(selection.get("frame", 0)),
		},
		"runtimeVisualOrigin": _vector_array(runtime_visual_origin),
		"visualOffset": _vector_array(visual_offset),
		"pickedVisualFootOffset": _vector_array(
			picked_visual_foot_offset
		),
		"finalVisualFootPoint": _vector_array(final_visual_foot_point),
		"canonicalCenters": {
			"actorGroundOrigin": [0.0, 0.0],
			"physicsFootprint": [0.0, 0.0],
			"mapDiamond": [0.0, 0.0],
		},
		"physicsFootprintRadii": _vector_array(
			physics_footprint_radii
		),
		"recommendedRuntime": {
			"visualRootOffset": _vector_array(visual_offset),
			"visualFootOffset": _vector_array(
				picked_visual_foot_offset
			),
			"ringCenterOffset": _vector_array(-final_visual_origin),
		},
		"formalSnapshot": {
			"projectionStrategy": str(
				formal.get("projectionStrategy", "grounded")
			),
			"visualFootOffset": formal.get(
				"visualFootOffset", []
			).duplicate(),
			"ringCenterOffset": formal.get(
				"ringCenterOffset", []
			).duplicate(),
			"ringEllipseRadii": formal.get(
				"ringEllipseRadii", []
			).duplicate(),
		},
		"sourceEvidence": {
			"formalContactPath": FORMAL_CONTACT_PATH,
			"formalContactSha256": FileAccess.get_sha256(
				FORMAL_CONTACT_PATH
			),
			"formalCalibrationPath": FORMAL_CALIBRATION_PATH,
			"formalCalibrationSha256": FileAccess.get_sha256(
				FORMAL_CALIBRATION_PATH
			),
			"animationCatalogPath": ANIMATION_CATALOG_PATH,
			"animationCatalogSha256": FileAccess.get_sha256(
				ANIMATION_CATALOG_PATH
			),
		},
		"formalRuntimeWritten": false,
	}


static func save_draft(
	payload: Dictionary,
	root_override := "",
) -> Dictionary:
	if str(payload.get("contractId", "")) != CONTRACT_ID:
		return {"ok": false, "path": "", "error": "draft contract mismatch"}
	var monster_id := int(payload.get("monsterId", -1))
	if formal_entry(monster_id).is_empty():
		return {"ok": false, "path": "", "error": "unknown monsterId"}
	var path := draft_path(monster_id, root_override)
	var absolute_path := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(
		absolute_path.get_base_dir()
	)
	if directory_error != OK:
		return {
			"ok": false,
			"path": path,
			"error": error_string(directory_error),
		}
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"path": path,
			"error": error_string(FileAccess.get_open_error()),
		}
	file.store_string(JSON.stringify(payload, "\t") + "\n")
	file.close()
	return {"ok": true, "path": path, "error": ""}


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = (
		JSON.parse_string(file.get_as_text()) if file != null else null
	)
	return parsed if parsed is Dictionary else {}


static func _vector_array(value: Vector2) -> Array:
	return [value.x, value.y]
