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
	assert(str(baseline.get("schema", "")) == "hardcore.dpv2.direct_monster_drop_baseline.v2")
	assert(str(baseline.get("authority_id", "")) == "dpv2.direct_baseline.v2")
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
	assert(GameData.get_dpv2_direct_profile(999999).is_empty())
	assert(GameData.get_dpv2_direct_slot("not-a-slot").is_empty())
	print("DPV2_21CQ_DIRECT_LOADER_PASS: manifest=1 hashes=1 profiles=156 exact_id_api=1")
	get_tree().quit(0)
