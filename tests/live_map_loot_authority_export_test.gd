extends Node

const LootService := preload("res://scripts/layers/runtime/loot_runtime_service.gd")

func _ready() -> void:
	assert(GameData.ensure_loaded(), GameData.load_error)
	var service := LootService.new()
	assert(service._sheet_authority.valid, service._sheet_authority.load_error)
	var monsters := {}
	var maps := MapEditorRuntimeBridge.released_map_ids()
	var spawn_count := 0
	for map_id: int in maps:
		var content := MapEditorRuntimeBridge.game_content_for_map(map_id)
		assert(not content.is_empty())
		var map_name := str(GameData.get_map_by_id(map_id).get("name", ""))
		for layer: String in ["spawns", "bosses"]:
			for spawn: Dictionary in content.get(layer, []):
				var mid := int(spawn.monster_id)
				var canonical := GameData.get_monster_by_id(mid)
				assert(not canonical.is_empty())
				assert(not str(canonical.get("canonical_name", "")).is_empty())
				if not monsters.has(mid):
					monsters[mid] = {
						"monster_id": mid, "name": str(canonical.canonical_name),
						"classification": str(canonical.get("classification", "")),
						"spawn_classification": canonical.get("spawn_classification", null),
						"maps": {}, "spawn_points": 0, "slots": [],
					}
				var row: Dictionary = monsters[mid]
				row.spawn_points += 1
				row.maps[map_id] = {"map_id": map_id, "name": map_name}
				spawn_count += 1
	var rows: Array = []
	var failures: Array = []
	var total_slots := 0
	for mid: int in monsters:
		var row: Dictionary = monsters[mid]
		row.maps = row.maps.values()
		var profile: Dictionary = service._production_profile(mid)
		row.profile_present = not profile.is_empty()
		if profile.is_empty():
			failures.append("missing_profile:%d" % mid)
		for slot: Dictionary in profile.get("slots", []):
			var probability: Dictionary = service._production_probability(mid, str(slot.slot_uid))
			var reward: Dictionary = service._production_reward(slot)
			if not probability.get("ok", false) or not reward.get("ok", false):
				failures.append("unresolved_slot:%s" % str(slot.slot_uid))
			var output: Dictionary = {}
			if str(reward.get("kind", "")) != "gold":
				output = service._drop_output_item_record(int(slot.get("canonical_item_id", -1)), str(reward.get("item_name", "")))
				if output.get("identity_status", "") != "resolved":
					failures.append("unresolved_output:%s" % str(slot.slot_uid))
			row.slots.append({"slot": slot, "probability": probability, "reward": reward, "output": {
				"item_id": output.get("output_item_id", -1), "name": output.get("item_name", "金币"),
			}})
			total_slots += 1
		# Execute both real production modes with the same RNG. No fixture drop
		# provider or fallback catalog can substitute for an incomplete sheet.
		for trial in range(3):
			var audit_rng := RandomNumberGenerator.new()
			var lean_rng := RandomNumberGenerator.new()
			audit_rng.seed = mid * 100 + trial
			lean_rng.seed = audit_rng.seed
			var audit: Dictionary = service.roll_monster_drops(mid, audit_rng, true)
			var lean: Dictionary = service.roll_monster_drops(mid, lean_rng, false)
			if not audit.configured or not str(audit.reason).is_empty() or not audit.rejected_entries.is_empty():
				failures.append("production_roll_rejected:%d:%s" % [mid, str(audit.reason)])
			for field: String in ["items", "item_records", "gold_drops", "rng_roll_count", "ground_output_count", "overflow_discarded_count"]:
				assert(audit[field] == lean[field], "audit/lean mismatch %d %s" % [mid, field])
			assert(audit_rng.state == lean_rng.state)
			assert(audit.ground_output_plus_discarded_equals_successful)
		rows.append(row)
	service.free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/repair_v92"))
	var file := FileAccess.open("res://outputs/repair_v92/live_map_loot_authority.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"map_count": maps.size(), "spawn_points": spawn_count,
		"monster_count": rows.size(), "slot_count": total_slots, "ground_limit": GameData.dpv2_ground_slot_limit(),
		"authority_path": "assets/data/drop/dpv2_user_loot_sheet_authority_v1.json",
		"monsters": rows, "failures": failures}, "\t"))
	file.close()
	print("LIVE_MAP_LOOT_AUTHORITY maps=%d monsters=%d spawns=%d slots=%d failures=%s" % [maps.size(), rows.size(), spawn_count, total_slots, str(failures)])
	assert(failures.is_empty())
	print("LIVE_MAP_LOOT_AUTHORITY_EXPORT_PASS")
	get_tree().quit()
