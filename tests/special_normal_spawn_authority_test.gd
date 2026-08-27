extends Node

const Catalog := preload("res://scripts/map_editor/map_editor_content_catalog_service.gd")
const RuntimeBridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const RespawnPolicy := preload("res://scripts/monster_respawn_policy.gd")

const EXPECTED := {
	39: ["STRONG_COMMON", 1.5],
	57: ["MINOR_BOSS", 6.0],
	74: ["ELITE", 3.0],
	77: ["MAJOR_BOSS", 12.0],
	90: ["MINOR_BOSS", 6.0],
	121: ["MINOR_BOSS", 6.0],
	137: ["ELITE", 3.0],
	142: ["MINOR_BOSS", 6.0],
}


func _ready() -> void:
	Catalog.reset_source_parse_counts()
	var exact_ids: Array[int] = []
	for entry: Dictionary in Catalog.entries("special_monster"):
		if str(entry.get("spawn_classification", "")) != RespawnPolicy.SPECIAL_NORMAL:
			continue
		var monster_id := int(entry.get("monster_id", -1))
		exact_ids.append(monster_id)
		assert(EXPECTED.has(monster_id))
		assert(str(entry.get("placement_kind", "")) == "monster_spawn")
		assert(int(entry.get("default_respawn_seconds", 0)) == 900)
		assert(str(entry.get("default_respawn_policy_id", "")) == RespawnPolicy.SPECIAL_NORMAL)
		var spawn_authority: Dictionary = entry.get("spawn_authority", {})
		var binding: Dictionary = spawn_authority.get("drop_binding", {})
		assert(str(binding.get("drop_role", "")) == str(EXPECTED[monster_id][0]))
		assert(float(binding.get("role_factor", 0.0)) == float(EXPECTED[monster_id][1]))
		assert(binding.has("additional_multiplier"))
		assert(binding.get("additional_multiplier") == null)
	exact_ids.sort()
	assert(exact_ids == EXPECTED.keys())

	var guardian := Catalog.find_by_monster_id("special_monster", 74)
	assert(str(guardian.get("classification", "")) == "elite")
	assert(Catalog.find_by_monster_id("boss_spawn", 74).is_empty())

	var runtime := {"design": {"design_size": [64, 64]}}
	var converted := RuntimeBridge._combat_spawn(runtime, {
		"monster_id": 74,
		"tile": [20, 20],
		"count": 1,
		"max_alive": 1,
		"respawn_seconds": 480,
		"respawn_policy_id": RespawnPolicy.NORMAL_CAVE,
	}, "monster_spawn")
	assert(not converted.is_empty())
	assert(str(converted.get("classification", "")) == "elite")
	assert(str(converted.get("spawn_classification", "")) == RespawnPolicy.SPECIAL_NORMAL)
	assert(str(converted.get("respawn_policy_id", "")) == RespawnPolicy.SPECIAL_NORMAL)
	assert(float(converted.get("respawn_seconds", 0.0)) == 900.0)
	assert(RuntimeBridge._combat_spawn(runtime, {
		"monster_id": 74, "tile": [20, 20], "count": 1, "max_alive": 1,
	}, "boss_spawn").is_empty())
	assert(RuntimeBridge._combat_spawn(runtime, {
		"monster_id": 74, "tile": [20, 20], "count": 2, "max_alive": 2,
	}, "monster_spawn").is_empty())

	var resolved := RespawnPolicy.resolve(
		RespawnPolicy.SPECIAL_NORMAL, "elite", 480.0, RespawnPolicy.SPECIAL_NORMAL
	)
	assert(resolved.valid and resolved.seconds == 900.0)
	print("SPECIAL_NORMAL_SPAWN_AUTHORITY_PASS: ids=8 id74=ELITE@3 respawn=900 extra_drop_multiplier=none")
	get_tree().quit(0)
