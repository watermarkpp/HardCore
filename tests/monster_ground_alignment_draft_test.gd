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
	var manual_alignment_hash := FileAccess.get_sha256(
		DraftScript.MANUAL_ALIGNMENT_DATA_PATH
	)
	var rows := DraftScript.catalog_rows()
	assert(DraftScript.animation_catalog_authority_valid())
	assert(rows.size() == 214)
	assert(int(rows[0].get("monster_id", -1)) == 18)
	var red_moon_index := -1
	for row_index in rows.size():
		if int(rows[row_index].get("monster_id", -1)) == 180:
			red_moon_index = row_index
			break
	assert(red_moon_index >= 0)
	var formal_replay_count := 0
	for row: Dictionary in rows:
		var replay := DraftScript.load_draft(
			int(row.get("monster_id", -1))
		)
		if not replay.is_empty():
			formal_replay_count += 1
	assert(formal_replay_count == 212)
	assert(DraftScript.load_draft(97).is_empty())
	assert(DraftScript.load_draft(98).is_empty())
	var red_moon_replay := DraftScript.load_draft(180)
	assert(str(red_moon_replay.get("monsterName", "")) == "赤月恶魔")
	assert(red_moon_replay.get("selection", {}).get("action", "") == "hit")
	assert(int(red_moon_replay.get("selection", {}).get("direction", -1)) == 0)
	assert(int(red_moon_replay.get("selection", {}).get("frame", -1)) == 1)
	assert(red_moon_replay.get("runtimeVisualOrigin", []) == [0.0, 6.0])
	assert(red_moon_replay.get("visualOffset", []) == [-31.5, -4.0])
	assert(red_moon_replay.get("pickedVisualFootOffset", []) == [31.5, -2.0])
	assert(red_moon_replay.get("finalVisualFootPoint", []) == [0.0, 0.0])
	var red_moon_formal := DraftScript.formal_entry(180)
	assert(
		red_moon_formal.get("projectionStrategy", "") == "grounded"
	)
	assert(red_moon_formal.get("visualRootOffset", []) == [-31.5, -4.0])
	assert(red_moon_formal.get("visualFootOffset", []) == [31.5, -2.0])
	assert(red_moon_formal.get("ringCenterOffset", []) == [31.5, -2.0])

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
	assert(
		FileAccess.get_sha256(DraftScript.MANUAL_ALIGNMENT_DATA_PATH)
		== manual_alignment_hash
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
		+ "catalog=214 replay=212 red_moon=180 "
		+ "single_target=true formal_readonly=true"
	)
	get_tree().quit(0)
