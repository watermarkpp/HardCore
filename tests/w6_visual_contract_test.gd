extends Node

const FixtureActorScript := preload("res://tests/w6_visual_fixture_actor.gd")
const MonsterDisplayFormatterScript := preload("res://scripts/monster_display_formatter.gd")
const MonsterOverheadScript := preload("res://scripts/monster_overhead.gd")
const LootPickupScript := preload("res://scripts/loot_pickup.gd")
const LootVisualEffectScript := preload("res://scripts/loot_visual_effect.gd")
const CasterSkillRuntimeScript := preload("res://scripts/caster_skill_runtime.gd")
const CasterSkillVisualRegistryScript := preload("res://scripts/caster_skill_visual_registry.gd")
const CasterSkillSkyStrikeScript := preload("res://scripts/caster_skill_sky_strike_visual_effect.gd")
const PlayerCharacterScript := preload("res://scripts/player.gd")

const TIER_AUTHORITY_PATH := "res://assets/data/drop/dpv2_item_tier_authority_v1.json"
const ITEM_AUTHORITY_PATH := "res://assets/data/item_runtime_authority_v1.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_display_and_rank_contract()
	_test_overhead_markers()
	_test_sky_strike_world_sort_contract()
	_test_loot_visual_authority_and_lifecycle()
	_test_hp910008_exact_binding()
	print("W6_VISUAL_CONTRACT_PASS")
	get_tree().quit(0)


func _test_display_and_rank_contract() -> void:
	assert(
		MonsterDisplayFormatterScript.display_name("半兽勇士1", 39) == "半兽勇士",
		"confirmed one-digit monster variant was not formatted at display boundary",
	)
	assert(
		MonsterDisplayFormatterScript.display_name("祖玛卫士00", 159) == "祖玛卫士",
		"confirmed two-digit monster variant was not formatted exactly",
	)
	assert(
		MonsterDisplayFormatterScript.display_name("未确认怪物9") == "未确认怪物9",
		"unconfirmed numeric suffix was stripped",
	)
	assert(
		MonsterDisplayFormatterScript.display_name("半兽勇士1") == "半兽勇士1",
		"unknown ID was allowed to rename a matching legacy name",
	)
	assert(
		MonsterDisplayFormatterScript.display_name("半兽勇士9", 39) == "半兽勇士9",
		"mismatched exact ID was allowed to strip another variant suffix",
	)
	assert(
		str(MonsterDisplayFormatterScript.rank_for_context(41).get("rank", "")) == "elite",
		"canonical elite classification was not selected",
	)
	assert(
		str(MonsterDisplayFormatterScript.rank_for_context(199, "elite").get("rank", "")) == "boss",
		"boss did not take precedence over elite",
	)
	assert(
		str(MonsterDisplayFormatterScript.rank_for_context(18, "elite", "special_normal").get("rank", "")) == "ordinary",
		"special_normal was incorrectly promoted to an elite marker",
	)
	assert(
		str(MonsterDisplayFormatterScript.rank_for_context(-1, "", "elite_spawn").get("rank", "")) == "elite",
		"trusted explicit elite spawn classification was ignored",
	)


func _test_overhead_markers() -> void:
	var world := Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	var elite_actor := _new_fixture_actor(41, "半兽勇士9", "elite")
	world.add_child(elite_actor)
	var elite_overhead := MonsterOverheadScript.new()
	elite_overhead.setup(elite_actor.display_name, false, 10, 20)
	elite_actor.add_child(elite_overhead)
	assert(elite_overhead.marker_rank() == "elite", "elite overhead rank was not resolved")
	assert(elite_overhead.rank_marker != null, "elite marker was not created")
	assert(
		elite_overhead.marker_texture_path().ends_with("elite_skull.svg"),
		"elite overhead did not use the exact gray-white skull asset",
	)
	assert(elite_overhead.name_label.text == "半兽勇士", "overhead display name changed internal identity")

	var boss_actor := _new_fixture_actor(199, "恶灵尸王0", "boss")
	boss_actor.set_meta("spawn_is_boss", true)
	world.add_child(boss_actor)
	var boss_overhead := MonsterOverheadScript.new()
	boss_overhead.setup(boss_actor.display_name, true, 10, 20)
	boss_actor.add_child(boss_overhead)
	assert(boss_overhead.marker_rank() == "boss", "boss overhead rank was not resolved")
	assert(boss_overhead.rank_marker != null, "boss marker was not created")
	assert(
		boss_overhead.marker_texture_path().ends_with("boss_horned_gold_skull.svg"),
		"boss overhead did not use the exact golden horned skull asset",
	)

	var ordinary_actor := _new_fixture_actor(18, "毒蜘蛛", "ordinary")
	world.add_child(ordinary_actor)
	var ordinary_overhead := MonsterOverheadScript.new()
	ordinary_overhead.setup(ordinary_actor.display_name, false, 10, 20)
	ordinary_actor.add_child(ordinary_overhead)
	assert(ordinary_overhead.marker_rank() == "ordinary", "ordinary rank changed")
	assert(ordinary_overhead.rank_marker == null, "ordinary monster received a rank marker")
	world.free()


func _test_sky_strike_world_sort_contract() -> void:
	var owner := PlayerCharacterScript.new()
	var target := Node2D.new()
	owner.global_position = Vector2(160.0, 88.0)
	target.global_position = Vector2(420.0, 296.0)
	add_child(owner)
	add_child(target)
	var profile: Dictionary = CasterSkillVisualRegistryScript.profile("wizard.lightning")
	var plan := {
		"success": true,
		"skill_id": "wizard.lightning",
		"visual": profile,
		"visual_radius_px": 72.0,
		"visual_duration": CasterSkillVisualRegistryScript.animation_duration("wizard.lightning"),
		"skill_footprint_snapshot": {},
	}
	var sky := CasterSkillRuntimeScript.create_visual(
		plan,
		owner.global_position,
		Vector2.RIGHT,
		target,
		"",
	)
	assert(sky is CasterSkillSkyStrikeScript, "canonical lightning visual factory changed type")
	add_child(sky)
	assert(sky.z_index == 0, "lightning did not rejoin world y-sort lane")
	assert(
		str(sky.get_meta("sky_strike_world_footpoint_sort_origin", "")) == "node_origin_minus_epsilon",
		"lightning must use a real Node2D origin proxy as its y-sort key",
	)
	assert(
		str(sky.get_meta("sky_strike_render_contract", "")) == "skills.sky_strike.world_footpoint_y_sort.actor_visible.v1",
		"lightning world footpoint render contract missing",
	)
	var drawable_body_lane_verified := false
	for child: Node in sky.get_children():
		if child is CasterSkillAnimationPlayer:
			var drawable := child as CasterSkillAnimationPlayer
			drawable_body_lane_verified = drawable.z_as_relative and drawable.z_index == 0 and not drawable.show_behind_parent
	assert(drawable_body_lane_verified, "lightning drawable did not stay behind same-footpoint body")
	var metadata: Dictionary = sky.sky_strike_visual_debug_metadata()
	assert(bool(metadata.get("world_footpoint_y_sort", false)), "lightning metadata lost world y-sort")
	assert(bool(metadata.get("same_footpoint_body_visibility", false)), "lightning body visibility contract missing")
	assert(bool(metadata.get("six_frame_gate_preserved", false)), "lightning six-frame gate was not preserved")
	target.global_position.y = 512.0
	sky._process(0.0)
	assert(sky.global_position.y < 512.0 and is_equal_approx(sky.global_position.y, 511.99), "lightning sort proxy left target footpoint")
	assert(is_equal_approx(float(sky.get_meta("sky_strike_world_footpoint_sort_y", -1.0)), 512.0), "lightning did not track target footpoint Y")
	sky.free()
	owner.free()
	target.free()


func _test_loot_visual_authority_and_lifecycle() -> void:
	var ordinary := _wooma_identity(false)
	var wooma := ordinary.duplicate(true)
	assert(LootVisualEffectScript.tier_for_record(wooma) == "WOOMA_GEAR", "loot tier did not use exact item ID authority")
	assert(LootVisualEffectScript.has_golden_beam_for_record(wooma), "authoritative Woma equipment has no beam")
	assert(not LootVisualEffectScript.affix_is_valid(wooma), "ordinary Woma template was treated as affixed")
	var affixed := _wooma_identity(true)
	assert(LootVisualEffectScript.affix_is_valid(affixed), "valid W7 affix was not accepted")
	assert(LootVisualEffectScript.has_golden_beam_for_record(affixed), "affix unexpectedly changed tier beam authority")
	assert(
		LootVisualEffectScript.label_color_for_record(affixed, Color("112233")) == LootVisualEffectScript.AFFIX_LABEL_COLOR,
		"affix label color was not instance-local",
	)
	assert(
		LootVisualEffectScript.label_color_for_record(wooma, Color("112233")) == Color("112233"),
		"ordinary instance inherited an affix label color",
	)
	var forged_name := wooma.duplicate(true)
	(forged_name["output_record"] as Dictionary)["name"] = "屠龙"
	(forged_name["output_record"] as Dictionary)["price"] = 999999999
	assert(LootVisualEffectScript.tier_for_record(forged_name) == "WOOMA_GEAR", "loot tier inferred from name/price")

	var potion := {
		"item_id": 910008,
		"output_item_id": 910008,
		"output_record": {"itemId": 910008, "name": "HP强化水", "kind": "consumable"},
	}
	assert(not LootVisualEffectScript.has_golden_beam_for_record(potion), "consumable received equipment beam")
	var invalid_affix := affixed.duplicate(true)
	(invalid_affix["item_instance"] as Dictionary)["modifiers"][0]["value"] = "bad"
	assert(not LootVisualEffectScript.affix_is_valid(invalid_affix), "malformed modifier received affix highlight")
	var top_level_only := ordinary.duplicate(true)
	top_level_only["drop_affix"] = (affixed["item_instance"] as Dictionary)["drop_affix"].duplicate(true)
	top_level_only["modifiers"] = (affixed["item_instance"] as Dictionary)["modifiers"].duplicate(true)
	assert(not LootVisualEffectScript.affix_is_valid(top_level_only), "top-level affix bypassed the W7 item_instance authority")

	var player := PlayerCharacterScript.new()
	add_child(player)
	var pickup := LootPickupScript.new()
	pickup.setup_item_record(affixed, player)
	add_child(pickup)
	assert(pickup.loot_visual_effect != null, "LootPickup did not own its visual helper")
	assert(pickup.loot_visual_effect.has_golden_beam(), "LootPickup helper lost exact tier beam")
	assert(pickup.loot_visual_effect.is_affix_highlighted(), "LootPickup helper lost instance affix state")
	pickup.manager_evaluate_collection(true, 0.0)
	assert(pickup.collection_pending(), "collection candidate was not pending")
	pickup.reject_collection("test rejection")
	assert(not pickup.is_queued_for_deletion(), "rejected pickup was destroyed")
	assert(is_instance_valid(pickup.loot_visual_effect), "rejected pickup lost its helper")
	pickup.manager_advance_time(5.0)
	pickup.manager_evaluate_collection(true, 0.0)
	pickup.confirm_collect()
	assert(pickup.is_queued_for_deletion(), "confirmed pickup was not destroyed")
	pickup.free()
	player.free()


func _test_hp910008_exact_binding() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ITEM_AUTHORITY_PATH))
	assert(parsed is Dictionary, "item runtime authority JSON failed to parse")
	var found: Dictionary = {}
	for raw_item: Variant in (parsed as Dictionary).get("newItems", []) as Array:
		if raw_item is Dictionary and int((raw_item as Dictionary).get("itemId", -1)) == 910008:
			found = raw_item as Dictionary
	assert(not found.is_empty(), "HP910008 authority record is missing")
	var art: Dictionary = found.get("art", {})
	var inventory: Dictionary = art.get("inventoryIcon", {})
	var ground: Dictionary = art.get("groundIcon", {})
	assert(str(inventory.get("binding", "")) == "item_id=910008", "HP910008 inventory binding is not exact")
	assert(str(ground.get("binding", "")) == "item_id=910008", "HP910008 ground binding is not exact")
	assert(str(inventory.get("distribution", "")) == "project.hardcore.w6_hp910008_supplement", "HP910008 inventory source lane is unclear")
	assert(not bool(inventory.get("exact", true)), "project supplement was incorrectly labelled primary exact")
	assert(FileAccess.file_exists(str(inventory.get("path", ""))), "HP910008 inventory art file missing")
	assert(FileAccess.file_exists(str(ground.get("path", ""))), "HP910008 ground art file missing")


func _new_fixture_actor(id: int, name: String, classification: String) -> Node2D:
	var actor := FixtureActorScript.new()
	actor.monster_id = id
	actor.display_name = name
	actor.monster_data = {"monster_id": id, "canonical_name": name, "classification": classification}
	return actor


func _wooma_identity(with_affix: bool) -> Dictionary:
	var catalog: Dictionary = GameData.get_item_record({"item_id": 168})
	var base_record := {
		"item_id": 168,
		"canonical_item_id": 168,
		"canonical_name": "幽灵项链",
		"item_name": "幽灵项链",
		"output_item_id": 168,
		"output_record": catalog.duplicate(true),
		"identity_status": "resolved",
	}
	for index in range(1000):
		var created := PlayerState.create_drop_item_instance(
			base_record,
			"w6_visual:%d" % index,
		)
		var instance_value: Variant = created.get("item_instance", null)
		if not instance_value is Dictionary:
			continue
		var affix_value: Variant = (instance_value as Dictionary).get("drop_affix", {})
		var applied := affix_value is Dictionary and bool((affix_value as Dictionary).get("applied", false))
		if applied == with_affix:
			return created
	return {}
