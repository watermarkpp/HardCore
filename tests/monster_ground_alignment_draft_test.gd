extends Node

const DraftScript := preload(
	"res://scripts/monster_ground_alignment_draft.gd"
)
const TEST_ROOT := "user://monster_ground_alignment_draft_test"


func _ready() -> void:
	var formal_contact_hash := FileAccess.get_sha256(
		DraftScript.FORMAL_CONTACT_PATH
	)
	var formal_calibration_hash := FileAccess.get_sha256(
		DraftScript.FORMAL_CALIBRATION_PATH
	)
	var animation_catalog_hash := FileAccess.get_sha256(
		DraftScript.ANIMATION_CATALOG_PATH
	)
	var rows := DraftScript.catalog_rows()
	assert(rows.size() == 214)
	assert(int(rows[0].get("monster_id", -1)) == 18)

	var payload := DraftScript.build_payload(
		18,
		{"action": "walk", "direction": 3, "frame": 2},
		Vector2(0.0, 4.0),
		Vector2(2.0, -1.0),
		Vector2(-2.0, -3.0),
		Vector2(16.0, 8.0),
	)
	assert(payload.get("contractId", "") == DraftScript.CONTRACT_ID)
	assert(int(payload.get("monsterId", -1)) == 18)
	assert(payload.get("finalVisualFootPoint", []) == [0.0, 0.0])
	assert(
		payload.get("recommendedRuntime", {}).get(
			"ringCenterOffset", []
		) == [-2.0, -3.0]
	)
	assert(not bool(payload.get("formalRuntimeWritten", true)))

	var sentinel_path := DraftScript.draft_path(19, TEST_ROOT)
	var sentinel_absolute := ProjectSettings.globalize_path(sentinel_path)
	DirAccess.make_dir_recursive_absolute(sentinel_absolute.get_base_dir())
	var sentinel := FileAccess.open(sentinel_absolute, FileAccess.WRITE)
	assert(sentinel != null)
	sentinel.store_string("{\"monsterId\":19,\"sentinel\":true}\n")
	sentinel.close()
	var sentinel_hash := FileAccess.get_sha256(sentinel_path)

	var save_result := DraftScript.save_draft(payload, TEST_ROOT)
	assert(bool(save_result.get("ok", false)))
	assert(
		str(save_result.get("path", ""))
		== DraftScript.draft_path(18, TEST_ROOT)
	)
	var loaded := DraftScript.load_draft(18, TEST_ROOT)
	assert(int(loaded.get("monsterId", -1)) == 18)
	assert(
		FileAccess.get_sha256(sentinel_path) == sentinel_hash,
		"saving monsterId=18 changed monsterId=19",
	)
	assert(
		FileAccess.get_sha256(DraftScript.FORMAL_CONTACT_PATH)
		== formal_contact_hash
	)
	assert(
		FileAccess.get_sha256(DraftScript.FORMAL_CALIBRATION_PATH)
		== formal_calibration_hash
	)
	assert(
		FileAccess.get_sha256(DraftScript.ANIMATION_CATALOG_PATH)
		== animation_catalog_hash
	)

	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(
			DraftScript.draft_path(18, TEST_ROOT)
		)
	)
	DirAccess.remove_absolute(sentinel_absolute)
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(TEST_ROOT)
	)
	print(
		"MONSTER_GROUND_ALIGNMENT_DRAFT_PASS "
		+ "catalog=214 single_target=true formal_readonly=true"
	)
	get_tree().quit(0)
