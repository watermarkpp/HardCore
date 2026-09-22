extends Node

# Level 1 contract tests for the user loot sheet authority (v1). The compiled
# sheet is the sole production probability source: E is the final pre-RNG
# per-slot probability, D is the final gold amount, and no legacy probability
# stage (SPB, V5, denominator policy, v80/v81, global multiplier, gold x5) may
# run for compiled monsters.

const LootRuntimeScript := preload(
	"res://scripts/layers/runtime/loot_runtime_service.gd"
)
const ProviderScript := preload("res://scripts/drop/user_loot_sheet_provider.gd")

const EXPECTED_MONSTERS := 126
const EXPECTED_SLOTS := 6042
const EXPECTED_NEW_SLOTS := 41
const EXPECTED_OVERLAY := 168
const EXPECTED_EMPTY := 5


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded(), "GameData failed: %s" % GameData.load_error)
	_test_provider_load_contract()
	_test_probability_direct_read()
	_test_fate_blade_identity()
	_test_new_equipment_slots()
	_test_roll_smoke_live_monster()
	_test_niumo_classification_elite()
	print(
		"USER_LOOT_SHEET_AUTHORITY_PASS: monsters=%d slots=%d new=%d fate=1 empty=%d"
		% [EXPECTED_MONSTERS, EXPECTED_SLOTS, EXPECTED_NEW_SLOTS, EXPECTED_EMPTY]
	)
	get_tree().quit(0)


func _test_provider_load_contract() -> void:
	var provider: Variant = ProviderScript.new()
	assert(provider != null)
	assert(provider.valid, provider.load_error)
	assert(provider.monster_count == EXPECTED_MONSTERS)
	assert(provider.slot_count == EXPECTED_SLOTS)
	assert(provider.new_slot_count == EXPECTED_NEW_SLOTS)
	assert(provider.overlay_slot_count == EXPECTED_OVERLAY)
	assert(provider.empty_profile_ids.size() == EXPECTED_EMPTY)
	assert(provider.authority_id == "dpv2.user_loot_sheet.v1")
	assert(not str(provider.sheet_sha256).is_empty())
	assert(not str(provider.digest).is_empty())
	for expected_empty_id: int in [30, 45, 18, 96, 100]:
		assert(provider.is_empty_profile(expected_empty_id))
	# Live-spawn coverage: every live-spawn monster has a compiled profile.
	for live_id: int in [18, 19, 21, 24, 26, 28, 30, 34, 36, 39, 43, 45, 46, 47, 50, 52, 57, 60, 62, 64, 66, 68, 70, 74, 77, 79, 81, 83, 85, 87, 90, 92, 94, 96, 97, 100, 101, 103, 104, 105, 107, 110, 112, 114, 116, 118, 121, 126, 128, 129, 132, 137, 138, 142, 148, 150, 153, 156, 164, 166, 168, 170, 172, 174, 176, 178, 182, 185, 200, 202, 204, 206, 210, 212, 214, 216, 218, 220, 222, 228, 229, 230, 231, 232, 233, 234]:
		assert(provider.has_profile(live_id), "live monster %d missing profile" % live_id)


func _test_probability_direct_read() -> void:
	var provider: Variant = ProviderScript.new()
	# m218 (牛魔将军) sheet value: 强效太阳水 1/2, 装备 1/60, 金币 1/10 @ 20000.
	var solar: Dictionary = provider.probability(218, "dpv2.direct.m218.slot_008")
	assert(bool(solar.get("ok", false)), str(solar))
	assert(int(solar.get("final_numerator", -1)) == 1)
	assert(int(solar.get("final_denominator", -1)) == 2)
	assert(int(solar.get("canonical_item_id", -1)) == 920016)
	assert(int(solar.get("final_gold_amount", 0)) == 0)
	var gold: Dictionary = provider.probability(218, "dpv2.direct.m218.v505_0001")
	assert(bool(gold.get("ok", false)), str(gold))
	assert(int(gold.get("final_numerator", -1)) == 1)
	assert(int(gold.get("final_denominator", -1)) == 10)
	# RV15 user-directive overlay slots: hp-1200 quartet (164/166/170/182)
	# v92: all seven elites retain the same independent slots/IDs; chiyue
	# probability is halved and zuma probability is exactly 3/4 of v91.
	var overlay_cy_ch: Dictionary = provider.probability(164, "dpv2.user.sheet.m164.set_cy_ch_001")
	assert(bool(overlay_cy_ch.get("ok", false)), str(overlay_cy_ch))
	assert(int(overlay_cy_ch.get("final_numerator", -1)) == 1)
	assert(int(overlay_cy_ch.get("final_denominator", -1)) == 280)
	assert(int(overlay_cy_ch.get("canonical_item_id", -1)) == 233)
	var overlay_zm_weap: Dictionary = provider.probability(164, "dpv2.user.sheet.m164.set_zm_weap_001")
	assert(bool(overlay_zm_weap.get("ok", false)), str(overlay_zm_weap))
	assert(int(overlay_zm_weap.get("final_numerator", -1)) == 1)
	assert(int(overlay_zm_weap.get("final_denominator", -1)) == 200)
	assert(int(overlay_zm_weap.get("canonical_item_id", -1)) == 105)
	var overlay_low_ch: Dictionary = provider.probability(168, "dpv2.user.sheet.m168.set_cy_ch_001")
	assert(bool(overlay_low_ch.get("ok", false)), str(overlay_low_ch))
	assert(int(overlay_low_ch.get("final_denominator", -1)) == 360)
	var overlay_low_weap3: Dictionary = provider.probability(168, "dpv2.user.sheet.m168.set_zm_weap_003")
	assert(bool(overlay_low_weap3.get("ok", false)), str(overlay_low_weap3))
	assert(int(overlay_low_weap3.get("final_numerator", -1)) == 3)
	assert(int(overlay_low_weap3.get("final_denominator", -1)) == 800)
	assert(int(overlay_low_weap3.get("canonical_item_id", -1)) == 107)
	var overlay_helm: Dictionary = provider.probability(170, "dpv2.user.sheet.m170.set_zm_helm_001")
	assert(bool(overlay_helm.get("ok", false)), str(overlay_helm))
	assert(int(overlay_helm.get("final_numerator", -1)) == 1)
	assert(int(overlay_helm.get("final_denominator", -1)) == 160)
	assert(int(overlay_helm.get("canonical_item_id", -1)) == 151)
	# 178 花吻蜘蛛 (hp 750) belongs to the "others" denominator group per the
	# original directive; the first delivery pass missed it and this slot set
	# closes that gap (overlay tally 144 -> 168).
	var overlay_178_ch: Dictionary = provider.probability(178, "dpv2.user.sheet.m178.set_cy_ch_001")
	assert(bool(overlay_178_ch.get("ok", false)), str(overlay_178_ch))
	assert(int(overlay_178_ch.get("final_denominator", -1)) == 360)
	assert(int(overlay_178_ch.get("canonical_item_id", -1)) == 233)
	var overlay_178_weap: Dictionary = provider.probability(178, "dpv2.user.sheet.m178.set_zm_weap_001")
	assert(bool(overlay_178_weap.get("ok", false)), str(overlay_178_weap))
	assert(int(overlay_178_weap.get("final_numerator", -1)) == 3)
	assert(int(overlay_178_weap.get("final_denominator", -1)) == 800)
	assert(int(overlay_178_weap.get("canonical_item_id", -1)) == 105)
	assert(not provider.owns(174, "dpv2.user.sheet.m174.set_cy_ch_001"))
	assert(not provider.owns(176, "dpv2.user.sheet.m176.set_cy_ch_001"))
	assert(int(gold.get("final_gold_amount", -1)) == 20000)
	# Equipment slot keeps the baseline identity and takes the sheet fraction.
	var equip: Dictionary = provider.probability(218, "dpv2.direct.m218.slot_002")
	assert(bool(equip.get("ok", false)), str(equip))
	assert(int(equip.get("final_numerator", -1)) == 1)
	assert(int(equip.get("final_denominator", -1)) == 60)
	# Cross-monster ownership fails closed.
	var wrong: Dictionary = provider.probability(21, "dpv2.direct.m218.slot_008")
	assert(not bool(wrong.get("ok", false)))
	# m222 merged groups resolved to full uid lists: 5x1/3 and 5x1/6.
	var group_a: Dictionary = provider.probability(222, "dpv2.direct.m222.slot_009")
	assert(int(group_a.get("final_denominator", -1)) == 3)
	var group_b: Dictionary = provider.probability(222, "dpv2.direct.m222.slot_005")
	assert(int(group_b.get("final_denominator", -1)) == 6)


func _test_fate_blade_identity() -> void:
	var provider: Variant = ProviderScript.new()
	var uid := "dpv2.user.v81.m76.fate_blade"
	assert(provider.owns(76, uid))
	assert(not provider.owns(21, uid))
	var fate: Dictionary = provider.probability(76, uid)
	assert(bool(fate.get("ok", false)), str(fate))
	assert(int(fate.get("canonical_item_id", -1)) == 110)
	# Sheet value for 命运之刃 is 1/15 (not the retired v81 2/3-derivation).
	assert(int(fate.get("final_numerator", -1)) == 1)
	assert(int(fate.get("final_denominator", -1)) == 15)


func _test_new_equipment_slots() -> void:
	var provider: Variant = ProviderScript.new()
	# 41 new equipment rows compiled with stable uids and resolved item ids.
	var new_count := 0
	for monster: Variant in provider.profiles_by_id.values():
		for slot: Variant in monster.get("slots", []):
			if str(slot.get("origin", "")) == "new_equip":
				new_count += 1
				assert(int(slot.get("canonical_item_id", -1)) > 0)
				assert(int(slot.get("final_numerator", -1)) >= 1)
				assert(int(slot.get("overflow_priority", -1)) == 300)
				assert(not bool(slot.get("protected_drop", true)))
	assert(new_count == EXPECTED_NEW_SLOTS)
	# The m76 fate blade keeps the v81 identity branch through reward
	# resolution (item 110 is absent from the frozen direct identity map).


func _test_roll_smoke_live_monster() -> void:
	var service: Variant = LootRuntimeScript.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260922
	var roll: Dictionary = service.roll_monster_drops(21, rng)
	assert(bool(roll.get("configured", false)), str(roll.get("reason", "")))
	assert(str(roll.get("runtime_authority", {}).get("authority_id", "")) == "dpv2.user_loot_sheet.v1")
	assert(int(roll.get("rng_roll_count", -1)) == int(roll.get("source_entry_count", -2)))
	assert(
		int(roll.get("ground_output_count", -1))
			+ int(roll.get("overflow_discarded_count", -1))
		== int(roll.get("successful_roll_count", -2))
	)
	for raw_attempt: Variant in roll.get("attempts", []):
		var attempt: Dictionary = raw_attempt
		assert(str(attempt.get("slot_uid", "")) != "")


func _test_niumo_classification_elite() -> void:
	for mid: int in [218, 222]:
		assert(
			GameData.canonical_monster_classification(mid) == "elite",
			"monster %d classification != elite" % mid
		)
	# Neighbours keep their gameplay classification (no collateral change).
	for mid: int in [212, 214, 216, 220, 224]:
		assert(GameData.canonical_monster_classification(mid) != "elite")
