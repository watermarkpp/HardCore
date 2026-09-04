extends Node


const REQUIRED_ACTIONS := ["idle", "walk", "attack", "hit", "death"]
const STRATEGIES := ["grounded", "flying", "hover"]


func _ready() -> void:
	var manifest := MonsterVisual._ground_contact_manifest()
	assert(manifest.get("contract", "") == MonsterVisual.GROUND_CONTACT_CONTRACT)
	assert(manifest.get("calibrationContract", "") == "monster.ground_contact.calibration.v5")
	assert(manifest.get("manualAlignmentContract", "") == "monster.ground_alignment.manual.v1")
	var summary: Dictionary = manifest.get("summary", {})
	assert(int(summary.get("monsterCount", 0)) == 214)
	assert(int(summary.get("explicitCalibrationCount", 0)) == 214)
	assert(int(summary.get("userAlignmentCount", 0)) == 212)
	assert(int(summary.get("preservedAirborneCount", 0)) == 2)
	assert(summary.get("requiredActions", []) == REQUIRED_ACTIONS)
	assert(int(summary.get("requiredDirections", 0)) == 8)
	var entries: Dictionary = manifest.get("entriesByMonsterId", {})
	assert(entries.size() == 214)
	var catalog_file := FileAccess.open(
		"res://assets/data/runtime/monster_animation_catalog.json",
		FileAccess.READ,
	)
	var catalog: Variant = JSON.parse_string(catalog_file.get_as_text()) if catalog_file != null else null
	assert(catalog is Dictionary)
	for row: Dictionary in catalog.get("monsters", []):
		var monster_id := str(int(row.monster_id))
		assert(entries.has(monster_id), "monsterId=%s calibration missing" % monster_id)
		var entry: Dictionary = entries[monster_id]
		assert(int(entry.monsterId) == int(row.monster_id))
		assert(str(entry.projectionStrategy) in STRATEGIES)
		assert(entry.visualRootOffset is Array and entry.visualRootOffset.size() == 2)
		assert(entry.visualFootOffset is Array and entry.visualFootOffset.size() == 2)
		assert(entry.ringCenterOffset is Array and entry.ringCenterOffset.size() == 2)
		assert(entry.ringEllipseRadii is Array and entry.ringEllipseRadii.size() == 2)
		assert(float(entry.ringEllipseRadii[0]) >= 8.0)
		assert(float(entry.ringEllipseRadii[1]) >= 3.0)
		assert(
			absf(
				float(entry.ringVerticalSquash)
				- float(entry.ringEllipseRadii[1]) / float(entry.ringEllipseRadii[0])
			) <= 0.0001,
			"monsterId=%s vertical squash disagrees with ellipse" % monster_id,
		)
		assert(entry.stableAcrossActions == REQUIRED_ACTIONS)
		assert(int(entry.stableAcrossDirections) == 8)
		assert(entry.calibrationSource in [
			"user_visual_acceptance_lab_v1",
			"manual_runtime_composite_review_v4",
		])
		var review: Dictionary = entry.get("review", {})
		assert(review.get("status", "") == "approved")
		assert(not str(review.get("archetype", "")).is_empty())
		assert(review.get("poses", []) is Array)
		assert(not review.get("poses", []).is_empty())
		assert(str(review.get("decision", "")).contains("monsterId=%s" % monster_id))
		assert(entry.manualAlignmentEvidence is Dictionary)
		if entry.calibrationSource == "user_visual_acceptance_lab_v1":
			assert(
				entry.manualAlignmentEvidence.contractId
				== "local.visual_acceptance_lab.monster_ground_alignment_draft.v1"
			)
			assert(str(entry.manualAlignmentEvidence.sourceDraftSha256).length() == 64)
		else:
			assert(int(monster_id) in [97, 98])
			assert(entry.projectionStrategy == "flying")
			assert(entry.visualRootOffset == [0.0, 0.0])
		assert(entry.automaticInitial is Dictionary)
	var counts: Dictionary = summary.get("projectionStrategyCounts", {})
	assert(int(counts.get("grounded", 0)) > 0)
	assert(int(counts.get("flying", 0)) > 0)
	assert(int(counts.get("hover", 0)) > 0)
	print("MONSTER_GROUND_CONTACT_CALIBRATION_COVERAGE_PASS: 212 user-aligned per-ID roots/feet plus 2 preserved airborne falcon projections")
	get_tree().quit(0)
