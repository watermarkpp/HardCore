extends Node


const ANCHOR_PATH := "res://assets/data/runtime/monster_overhead_anchors.json"
const SAMPLE_IDS := [21, 24, 28, 46, 76, 124]


func _ready() -> void:
	var file := FileAccess.open(ANCHOR_PATH, FileAccess.READ)
	assert(file != null, "per-monster overhead anchor data is missing")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "per-monster overhead anchor data is invalid")
	var manifest: Dictionary = parsed
	assert(manifest.get("contract", "") == "monster.overhead_anchor.v4")
	assert(int(manifest.get("summary", {}).get("monsterCount", 0)) == 214)
	assert(int(manifest.get("summary", {}).get("requiredDirections", 0)) == 8)
	assert(manifest.get("summary", {}).get("requiredActions", []) == ["idle", "walk", "attack", "hit", "death"])

	var anchors: Dictionary = manifest.get("anchorsByMonsterId", {})
	assert(anchors.size() == 214)
	var body_tops: Dictionary = {}
	var frame_heights: Dictionary = {}
	for monster_id: int in SAMPLE_IDS:
		var entry: Dictionary = anchors.get(str(monster_id), {})
		assert(not entry.is_empty(), "monsterId=%d has no stable overhead entry" % monster_id)
		var body_top := int(entry.get("stableBodyTop", -1))
		var action_tops: Dictionary = entry.get("actionVisibleTops", {})
		var frame_size: Array = entry.get("frameSize", [])
		assert(body_top > 0 and frame_size.size() == 2)
		assert(body_top == int(action_tops.get("idle", -1)), "monsterId=%d body crown is not the all-direction idle envelope" % monster_id)
		assert(action_tops.keys().size() == 5 and int(entry.get("sampledFrames", 0)) > 0)
		body_tops[body_top] = true
		frame_heights[int(frame_size[1])] = true

	assert(body_tops.size() >= 3, "different monster bodies incorrectly share one universal top")
	assert(frame_heights.size() >= 4, "fixture does not cover enough monster body sizes")
	assert(int(anchors["24"]["stableBodyTop"]) > int(anchors["21"]["stableBodyTop"]), "cat and scarecrow retained a universal body height")
	assert(int(anchors["76"]["stableBodyTop"]) != int(anchors["46"]["stableBodyTop"]), "boss and small monster retained a universal body height")
	print("MONSTER_SPECIES_OVERHEAD_ANCHOR_CONTRACT_PASS monsters=214 sampledSizes=%d sampledBodyTops=%d" % [frame_heights.size(), body_tops.size()])
	get_tree().quit(0)
