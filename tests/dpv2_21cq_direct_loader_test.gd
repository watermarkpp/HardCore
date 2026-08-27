extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded(), "GameData failed: %s" % GameData.load_error)
	assert(GameData.is_dpv2_direct_baseline_loaded())
	var manifest: Dictionary = GameData.dpv2_direct_baseline_manifest
	var baseline: Dictionary = GameData.dpv2_direct_baseline
	assert(str(manifest.get("schema", "")) == "hardcore.dpv2.direct_baseline_manifest.v2")
	assert(str(manifest.get("manifest_id", "")) == "dpv2.direct_baseline.manifest.v2")
	assert(str(manifest.get("status", "")) == "REPRODUCIBLE_PRODUCTION_BUILD_PASS")
	assert(bool(manifest.get("production_active", false)))
	assert(str(baseline.get("schema", "")) == "hardcore.dpv2.direct_monster_drop_baseline.v2")
	assert(str(baseline.get("authority_id", "")) == "dpv2.direct_baseline.v2")
	assert(str(baseline.get("status", "")) == "PRODUCTION_ACTIVE_DIRECT_BASELINE")
	assert(bool(baseline.get("production_active", false)))
	assert(str(baseline.get("production_runtime", "")) == "V2_DIRECT_BASELINE")
	assert(str(baseline.get("identity_key", "")) == "canonical_monster_id")
	var artifacts: Dictionary = manifest.get("artifacts", {})
	for key: String in [
		"direct_baseline_authority", "global_drop_rate_authority", "item_mapping",
	]:
		assert(artifacts.has(key), "manifest artifact missing: %s" % key)
		assert(str(artifacts[key].get("sha256", "")).length() == 64)
		assert(str(artifacts[key].get("hash_normalization", "")) == "lf_text")
	var profile := GameData.get_dpv2_direct_profile(18)
	assert(int(profile.get("canonical_monster_id", -1)) == 18)
	assert(str(profile.get("drop_profile_id", "")) == "dpv2.direct.18")
	var slot := GameData.get_dpv2_direct_slot("dpv2.direct.m18.slot_001")
	assert(int(slot.get("canonical_monster_id", -1)) == 18)
	assert(int(slot.get("base_numerator", -1)) == 1)
	assert(int(slot.get("base_denominator", -1)) == 3)
	var mapped_reward := GameData.resolve_canonical_drop_reward({"item": "毒蜘蛛牙齿"})
	assert(bool(mapped_reward.get("ok", false)))
	assert(int(mapped_reward.get("canonical_item_id", -1)) == 920039)
	assert(GameData.get_dpv2_direct_profile(999999).is_empty())
	assert(GameData.get_dpv2_direct_slot("not-a-slot").is_empty())
	var game_data_source := FileAccess.get_file_as_string("res://scripts/game_data.gd")
	var loot_source := FileAccess.get_file_as_string(
		"res://scripts/layers/runtime/loot_runtime_service.gd"
	)
	for forbidden: String in [
		"DPV2_ITEM_TIER", "DPV2_MONSTER_ROLE", "DPV2_DROP_RUNTIME",
		"dpv2_item_tier", "dpv2_monster_role", "dpv2_drop_runtime",
		"role_factor", "tier_denominator", "dpv2_resolve_reward_policy",
		"dpv2_monster_drop_state", "_load_dpv2_drop_authorities",
	]:
		assert(
			not game_data_source.contains(forbidden)
			and not loot_source.contains(forbidden),
			"legacy Production drop symbol remains: %s" % forbidden,
		)
	print("DPV2_21CQ_DIRECT_LOADER_PASS: manifest=1 hashes=1 profiles=156 exact_id_api=1")
	get_tree().quit(0)
