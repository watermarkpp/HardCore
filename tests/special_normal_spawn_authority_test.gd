extends Node

const Catalog := preload("res://scripts/map_editor/map_editor_content_catalog_service.gd")
const RuntimeBridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const RespawnPolicy := preload("res://scripts/monster_respawn_policy.gd")

const EXPECTED_IDS := [39, 57, 74, 77, 90, 121, 137, 142]


func _ready() -> void:
	Catalog.reset_source_parse_counts()
	var exact_ids: Array[int] = []
	for entry: Dictionary in Catalog.entries("special_monster"):
		if str(entry.get("spawn_classification", "")) != RespawnPolicy.SPECIAL_NORMAL:
			continue
		var monster_id := int(entry.get("monster_id", -1))
		exact_ids.append(monster_id)
		assert(monster_id in EXPECTED_IDS)
		assert(str(entry.get("placement_kind", "")) == "monster_spawn")
		assert(int(entry.get("default_respawn_seconds", 0)) == 900)
		assert(str(entry.get("default_respawn_policy_id", "")) == RespawnPolicy.SPECIAL_NORMAL)
		var spawn_authority: Dictionary = entry.get("spawn_authority", {})
		for forbidden: String in ["drop_binding", "drop_role", "role_factor", "item_tier_resolution", "item_tier_sha", "monster_role_sha", "global_scale_sha"]:
			assert(not spawn_authority.has(forbidden), "special_normal spawn authority leaked %s" % forbidden)
		assert(spawn_authority.get("spawn_classification", "") == RespawnPolicy.SPECIAL_NORMAL)
		assert(str(spawn_authority.get("placement_kind", "")) == "monster_spawn")
		assert(str(spawn_authority.get("respawn_policy_id", "")) == RespawnPolicy.SPECIAL_NORMAL)
		assert(int(spawn_authority.get("respawn_seconds", 0)) == 900)
		assert(int(spawn_authority.get("random_seconds", -1)) == 0)
		assert(int(spawn_authority.get("count", 0)) == 1)
		assert(int(spawn_authority.get("max_alive", 0)) == 1)
	exact_ids.sort()
	assert(exact_ids == EXPECTED_IDS)

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
	print("SPECIAL_NORMAL_SPAWN_AUTHORITY_PASS: ids=8 classification_preserved=1 respawn=900 drop_probability=external_direct_baseline")
	get_tree().quit(0)
