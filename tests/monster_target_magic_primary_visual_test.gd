extends Node

const EffectScript := preload("res://scripts/monster_target_magic_effect.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const SOURCE_PATH := "res://assets/data/monster_target_magic_sources_v1.json"
const BEHAVIOR_PATH := "res://assets/data/monster_behavior_profiles.json"
const COMBAT_SOURCE_PATH := "res://assets/data/canonical_monster_combat_source_v1.json"
const VANILLA_PATH := "res://assets/data/vanilla_176/monsters.json"
const PRIMARY_CLIENT_DATA := "dev_art_sources/reference/mir2_client_raw/Data/"
const AUXILIARY_CLIENT_DATA := "dev_art_sources/external/mir2opensource_full/Data/"
const PRIMARY_MAGIC2_SHA256 := "398E5376F19638DF063CD6299199BF5C2365FA8525FE0C9E639EB3BB6C955D07"
const PRIMARY_MAGIC_SHA256 := "BE46A0258349B26DB9BA7DBA595ABAC1F0767D52FEF11D9F508E704F2F6DEAAC"
const AUXILIARY_MON21_SHA256 := "948E500FDB4C5677D73C4A500809057A08D858B92F2AA7CB59074F0AC0098106"


func _ready() -> void:
	var sources := _load_json(SOURCE_PATH)
	var behavior := _load_json(BEHAVIOR_PATH)
	var combat := _load_json(COMBAT_SOURCE_PATH)
	var vanilla := _load_json(VANILLA_PATH)
	_assert_exact_id_mapping(sources, behavior, combat, vanilla)
	_assert_primary_asset_contract(sources)
	_assert_runtime_visual_dispatch()
	await _assert_priest_dynamic_world_cutoff()
	print(
		"MONSTER_TARGET_MAGIC_PRIMARY_VISUAL_PASS "
		+ "220=magic2_thunder 222=wmon21_plus_magic_fly retired=221,223"
	)
	get_tree().quit(0)


func _assert_exact_id_mapping(
	sources: Dictionary,
	behavior: Dictionary,
	combat: Dictionary,
	vanilla: Dictionary,
) -> void:
	var profiles: Dictionary = behavior.get("profiles", {})
	var by_id: Dictionary = behavior.get("profileByMonsterId", {})
	assert(str(by_id.get("220", "")) == "cow_mage")
	assert(str(by_id.get("222", "")) == "cow_priest")
	assert(not by_id.has("221"), "retired ID 221 must not inherit cow_mage")
	assert(not by_id.has("223"), "retired ID 223 must not inherit cow_priest")
	var legacy_names: Dictionary = behavior.get("legacyNameToProfile", {})
	assert(not legacy_names.has("牛魔法师0"))
	assert(not legacy_names.has("牛魔祭司0"))
	assert(
		str(profiles.get("cow_mage", {}).get("attackDelivery", {}).get(
			"presentationEffectId", ""
		)) == EffectScript.COW_MAGE_PRESENTATION_EFFECT_ID
	)
	assert(
		str(profiles.get("cow_priest", {}).get("attackDelivery", {}).get(
			"presentationEffectId", ""
		)) == EffectScript.COW_PRIEST_PRESENTATION_EFFECT_ID
	)
	var combat_by_id: Dictionary = combat.get("records_by_monster_id", {})
	assert(int(combat_by_id.get("220", {}).get("ai_code", -1)) == 200)
	assert(int(combat_by_id.get("222", {}).get("ai_code", -1)) == 200)
	assert(int(combat_by_id.get("221", {}).get("ai_code", -1)) == 81)
	assert(int(combat_by_id.get("223", {}).get("ai_code", -1)) == 81)
	var vanilla_by_id := {}
	for value: Variant in vanilla.get("records", []):
		if value is Dictionary:
			vanilla_by_id[str(int(value.get("monsterId", -1)))] = value
	assert(str(vanilla_by_id.get("221", {}).get("recordStatus", "")) == "retired")
	assert(str(vanilla_by_id.get("223", {}).get("recordStatus", "")) == "retired")
	var source_by_id: Dictionary = sources.get("effects_by_monster_id", {})
	assert(str(source_by_id.get("221", {}).get("runtime_policy", "")).contains("must_not"))
	assert(str(source_by_id.get("223", {}).get("runtime_policy", "")).contains("must_not"))


func _assert_primary_asset_contract(sources: Dictionary) -> void:
	var source_by_id: Dictionary = sources.get("effects_by_monster_id", {})
	var mage: Dictionary = source_by_id.get("220", {})
	var priest: Dictionary = source_by_id.get("222", {})
	assert(str(mage.get("presentation_effect_id", "")) == EffectScript.COW_MAGE_PRESENTATION_EFFECT_ID)
	assert(str(priest.get("presentation_effect_id", "")) == EffectScript.COW_PRIEST_PRESENTATION_EFFECT_ID)
	assert(int(mage.get("client_magic_release_frame", -1)) == 4)
	assert(int(priest.get("client_magic_release_frame", -1)) == 4)
	var mage_assets: Array = mage.get("assets", [])
	var priest_assets: Array = priest.get("assets", [])
	assert(mage_assets.size() == 1)
	assert(priest_assets.size() == 2)
	_assert_asset(
		mage_assets[0],
		"target_thunder",
		6,
		PRIMARY_CLIENT_DATA + "Magic2.wil",
		PRIMARY_MAGIC2_SHA256,
		"primary",
	)
	_assert_asset(
		priest_assets[0],
		"caster_directional_overlay",
		48,
		AUXILIARY_CLIENT_DATA + "Mon21.wil",
		AUXILIARY_MON21_SHA256,
		"auxiliary_1",
	)
	_assert_asset(
		priest_assets[1],
		"flying_spell",
		96,
		PRIMARY_CLIENT_DATA + "Magic.wil",
		PRIMARY_MAGIC_SHA256,
		"primary",
	)
	assert(str(mage_assets[0].get("source_index_rule", "")).contains("10 + frame"))
	assert(str(priest_assets[0].get("source_index_rule", "")).contains("2960"))
	assert(str(priest_assets[1].get("source_index_rule", "")).contains("FLYBASE(10)"))
	assert(
		str(mage_assets[0].get("distribution", ""))
		== "client.classic_raw_complete"
	)
	assert(
		str(priest_assets[1].get("distribution", ""))
		== "client.classic_raw_complete"
	)
	assert(
		str(priest_assets[0].get("distribution", ""))
		== "client.mir2opensource_2013_complete"
	)
	_assert_mon21_fallback_evidence(priest_assets[0])
	for profile: Dictionary in [mage, priest]:
		for rule_value: Variant in profile.get("client_rule_sources", []):
			assert(rule_value is Dictionary)
			var rule := rule_value as Dictionary
			assert(
				str(rule.get("path", "")).begins_with(
					"dev_art_sources/reference/original_gameofmir/MirClient/"
				)
			)
			assert(str(rule.get("tier", "")) == "primary")
			assert(
				str(rule.get("distribution", ""))
				== "source.original_gameofmir.mirclient"
			)


func _assert_asset(
	asset: Dictionary,
	expected_role: String,
	expected_frames: int,
	expected_library: String,
	expected_library_sha256: String,
	expected_tier: String,
) -> void:
	assert(str(asset.get("role", "")) == expected_role)
	assert(str(asset.get("source_library", "")) == expected_library)
	assert(
		str(asset.get("source_library_sha256", "")).to_upper()
		== expected_library_sha256
	)
	assert(str(asset.get("tier", "")) == expected_tier)
	var frames: Array = asset.get("frames", [])
	assert(frames.size() == expected_frames)
	var atlas_path := str(asset.get("atlas_path", ""))
	assert(ResourceLoader.exists(atlas_path))
	assert(ResourceLoader.load(atlas_path) is Texture2D)
	assert(
		FileAccess.get_sha256(atlas_path).to_upper()
		== str(asset.get("atlas_sha256", "")).to_upper()
	)
	for frame_value: Variant in frames:
		assert(frame_value is Dictionary)
		var frame := frame_value as Dictionary
		assert((frame.get("atlas_region", []) as Array).size() == 4)
		assert((frame.get("source_offset", []) as Array).size() == 2)
		assert(int(frame.get("wil_byte_offset", 0)) > 0)
		assert(str(frame.get("source_library", "")) == expected_library)
		assert(
			str(frame.get("source_library_sha256", "")).to_upper()
			== expected_library_sha256
		)
		assert(str(frame.get("source_frame_rgba_sha256", "")).length() == 64)


func _assert_mon21_fallback_evidence(asset: Dictionary) -> void:
	var fallback: Dictionary = asset.get("fallback_evidence", {})
	assert(str(fallback.get("higher_tier_result", "")) == "exact_object_missing")
	var required: Dictionary = fallback.get("required_higher_tier", {})
	assert(str(required.get("tier", "")) == "primary")
	assert(
		str(required.get("distribution", ""))
		== "client.classic_raw_complete"
	)
	var queries: Array = fallback.get("queries", [])
	assert(queries.size() == 2)
	assert(
		str(queries[0].get("path", ""))
		== PRIMARY_CLIENT_DATA + "Mon21.wil"
	)
	assert(
		str(queries[1].get("path", ""))
		== PRIMARY_CLIENT_DATA + "Mon21.WIX"
	)
	for query_value: Variant in queries:
		assert(query_value is Dictionary)
		var query := query_value as Dictionary
		assert(str(query.get("query_result", "")) == "missing")
		assert(not bool(query.get("exists", true)))
	var selected: Dictionary = fallback.get("fallback_selected", {})
	assert(str(selected.get("tier", "")) == "auxiliary_1")
	assert(str(selected.get("path", "")) == AUXILIARY_CLIENT_DATA + "Mon21.wil")


func _assert_runtime_visual_dispatch() -> void:
	var mage: Node2D = EffectScript.create_visual(_descriptor(220))
	var priest: Node2D = EffectScript.create_visual(_descriptor(222))
	var retired_mage: Node2D = EffectScript.create_visual(_descriptor(221))
	var retired_priest: Node2D = EffectScript.create_visual(_descriptor(223))
	assert(mage.visible)
	assert(priest.visible)
	assert(not retired_mage.visible)
	assert(not retired_priest.visible)
	assert(
		str(mage.visual_descriptor().get("presentation_effect_id", ""))
		== EffectScript.COW_MAGE_PRESENTATION_EFFECT_ID
	)
	assert(
		str(priest.visual_descriptor().get("presentation_effect_id", ""))
		== EffectScript.COW_PRIEST_PRESENTATION_EFFECT_ID
	)
	assert(
		str(mage.visual_descriptor().get("world_collision_policy", ""))
		== "none_target_anchored_thunder"
	)
	assert(
		str(priest.visual_descriptor().get("world_collision_policy", ""))
		== "swept_world_mask_body_and_area"
	)
	assert(
		str(mage.visual_descriptor().get("background_policy", ""))
		== "transparent_source_policy_compliant_client_frames_only"
	)
	assert(EffectScript._client_fly_direction16(Vector2(0.0, -10.0)) == 0)
	assert(EffectScript._client_fly_direction16(Vector2(10.0, 0.0)) == 4)
	assert(EffectScript._client_fly_direction16(Vector2(0.0, 10.0)) == 8)
	assert(EffectScript._client_fly_direction16(Vector2(-10.0, 0.0)) == 12)
	mage.queue_free()
	priest.queue_free()
	retired_mage.queue_free()
	retired_priest.queue_free()


func _assert_priest_dynamic_world_cutoff() -> void:
	var priest: Node2D = EffectScript.create_visual({
		"effect_id": EffectScript.EFFECT_ID,
		"release_id": "dynamic-world-magic-test",
		"source_monster_id": 222,
		"source_world_px": Vector2.ZERO,
		"target_world_px": Vector2(200.0, 0.0),
		"damage_owner": "enemy.target_magic_release",
	})
	add_child(priest)
	priest.set_process(false)
	await get_tree().physics_frame

	# Begin flight on a clear path, then insert a live WORLD body ahead of it.
	priest.call("_process", 0.58)
	assert(not bool(priest.visual_descriptor().get("flight_blocked_by_world", true)))

	var wall := StaticBody2D.new()
	wall.collision_layer = WorldSpatialRulesScript.WORLD_LAYER
	wall.collision_mask = 0
	wall.position = Vector2(75.0, 0.0)
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(4.0, 80.0)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	add_child(wall)
	await get_tree().physics_frame

	priest.call("_process", 0.1)
	var descriptor: Dictionary = priest.visual_descriptor()
	assert(bool(descriptor.get("flight_blocked_by_world", false)))
	assert(
		str(descriptor.get("world_collision_policy", ""))
		== "swept_world_mask_body_and_area"
	)
	assert(
		str(descriptor.get("damage_owner", ""))
		== "enemy.target_magic_release"
	)
	# The node can retain the source cast overlay, but its mtFly draw path is
	# now closed and cannot visually cross the dynamic wall.
	assert(priest.visible)

	priest.queue_free()
	wall.queue_free()
	await get_tree().process_frame


func _descriptor(monster_id: int) -> Dictionary:
	return {
		"effect_id": EffectScript.EFFECT_ID,
		"release_id": "test-%d" % monster_id,
		"source_monster_id": monster_id,
		"source_world_px": Vector2.ZERO,
		"target_world_px": Vector2(64.0, 16.0),
		"damage_owner": "enemy.target_magic_release",
	}


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "missing JSON: %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "invalid JSON: %s" % path)
	return parsed
