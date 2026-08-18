extends Node

# P2: Monster editor identity rebind closure tests
# Verifies canonical monster_id survives save/load/rebind round-trip.

const CatalogService := preload("res://scripts/map_editor/map_editor_content_catalog_service.gd")

# Known canonical IDs from canonical_monster_catalog.json
const ID_CHICKEN := 14          # 鸡 (retired identity, absent from canonical catalog)
const ID_MULTI_HOOK_CAT := 24   # 多钩猫 (ordinary, formal)
const ID_NAIL_RAKE_CAT := 26    # 钉耙猫 (ordinary, formal)
const ID_MULTI_HOOK_CAT_KING := 31  # 多钩猫王 (elite, unresolved)
const ID_HALF_ORC_WARRIOR := 38 # 半兽勇士 (elite, formal)
const ID_SCORPION := 45         # 蝎子 (ordinary, unresolved)


func _ready() -> void:
	print("=== TEST 1: MONSTER_ID_SERIALIZATION_ROUNDTRIP ===")
	test_monster_id_serialization_roundtrip()
	print("PASSED")

	print("=== TEST 2: MONSTER_EDITOR_REBIND_ROUNDTRIP ===")
	test_monster_editor_rebind_roundtrip()
	print("PASSED")

	print("=== TEST 3: CATALOG_ORDER_INDEPENDENCE ===")
	test_catalog_order_independence()
	print("PASSED")

	print("=== TEST 4: UNRESOLVED_ID_MUST_NOT_FALLBACK ===")
	test_unresolved_id_must_not_fallback()
	print("PASSED")

	print("=== TEST 5: KIND_REBIND_CONTRACT ===")
	test_kind_rebind_contract()
	print("PASSED")

	print("=== TEST 6: SPECIFIC_BUG_REPRODUCTION ===")
	test_half_orc_warrior_not_multi_hook_cat_king()
	print("PASSED")

	print("=== TEST 7: SCORPION_NOT_CHICKEN ===")
	test_scorpion_not_chicken()
	print("PASSED")

	print("\n=== ALL TESTS PASSED ===")
	print("MSE_MONSTER_IDENTITY_REBIND_PASS tests=7")
	get_tree().quit()


func test_monster_id_serialization_roundtrip() -> void:
	var test_cases := [
		{"monster_id": ID_MULTI_HOOK_CAT, "kind": "monster_spawn", "name": "多钩猫"},
		{"monster_id": ID_SCORPION, "kind": "monster_spawn", "name": "蝎子"},
		{"monster_id": ID_HALF_ORC_WARRIOR, "kind": "boss_spawn", "name": "半兽勇士"},
	]

	for tc in test_cases:
		var semantic := {
			"kind": tc.kind,
			"monster_id": tc.monster_id,
			"display_name": tc.name,
			"content_id": "",
			"radius_tiles": 3,
			"count": 1,
			"respawn_seconds": 60 if tc.kind == "monster_spawn" else 1800,
			"max_alive": 1,
		}

		# Serialize to JSON and back (simulating save/load)
		var json_str: String = JSON.stringify(semantic)
		var parsed: Variant = JSON.parse_string(json_str)
		assert(parsed != null, "JSON parse should succeed for %s" % tc.name)

		var loaded: Dictionary = parsed as Dictionary
		assert(int(loaded.get("monster_id", -1)) == tc.monster_id,
			"%s: monster_id must survive JSON round-trip" % tc.name)
		assert(str(loaded.get("kind", "")) == tc.kind,
			"%s: kind must survive JSON round-trip" % tc.name)


func test_monster_editor_rebind_roundtrip() -> void:
	var test_cases := [
		{"monster_id": ID_MULTI_HOOK_CAT, "kind": "monster_spawn", "expected_name": "多钩猫"},
		{"monster_id": ID_SCORPION, "kind": "monster_spawn", "expected_name": "蝎子"},
		{"monster_id": ID_HALF_ORC_WARRIOR, "kind": "boss_spawn", "expected_name": "半兽勇士"},
	]

	for tc in test_cases:
		var entry := CatalogService.find_by_monster_id(tc.kind, tc.monster_id)
		assert(not entry.is_empty(),
			"%s (ID %d) must be found in kind=%s" % [tc.expected_name, tc.monster_id, tc.kind])
		assert(int(entry.get("monster_id", -1)) == tc.monster_id,
			"%s: resolved monster_id must match" % tc.expected_name)
		assert(str(entry.get("display_name", "")) == tc.expected_name,
			"%s: resolved display_name must match" % tc.expected_name)


func test_catalog_order_independence() -> void:
	# Get all boss_spawn entries
	var boss_entries := CatalogService.entries("boss_spawn", 4)
	assert(boss_entries.size() > 0, "boss_spawn catalog must have entries")

	# Find 半兽勇士 by monster_id, not by index
	var warrior_entry := CatalogService.find_by_monster_id("boss_spawn", ID_HALF_ORC_WARRIOR)
	assert(not warrior_entry.is_empty(), "半兽勇士 must be findable by ID")
	assert(int(warrior_entry.get("monster_id", -1)) == ID_HALF_ORC_WARRIOR,
		"半兽勇士 ID must be 38")
	assert(str(warrior_entry.get("display_name", "")) == "半兽勇士",
		"半兽勇士 name must be correct")

	# Verify it's NOT the first entry (which would be the bug)
	if boss_entries.size() > 1:
		var first_entry: Dictionary = boss_entries[0]
		var first_id := int(first_entry.get("monster_id", -1))
		assert(first_id != ID_HALF_ORC_WARRIOR,
			"半兽勇士 should NOT be the first boss_spawn entry (order independence)")


func test_unresolved_id_must_not_fallback() -> void:
	var fake_id := 99999

	# find_by_monster_id must return empty for non-existent ID
	var result := CatalogService.find_by_monster_id("monster_spawn", fake_id)
	assert(result.is_empty(),
		"Non-existent monster_id %d must NOT resolve to any entry" % fake_id)

	# Also check boss_spawn
	var boss_result := CatalogService.find_by_monster_id("boss_spawn", fake_id)
	assert(boss_result.is_empty(),
		"Non-existent monster_id %d must NOT resolve to any boss entry" % fake_id)

	# find_any_monster must also return empty
	var any_result := CatalogService.find_any_monster(fake_id)
	assert(any_result.is_empty(),
		"find_any_monster(%d) must return empty" % fake_id)


func test_kind_rebind_contract() -> void:
	# Ordinary monsters -> monster_spawn
	var ordinary_entry := CatalogService.find_by_monster_id("monster_spawn", ID_MULTI_HOOK_CAT)
	assert(not ordinary_entry.is_empty(), "多钩猫 must be found in monster_spawn")
	assert(str(ordinary_entry.get("display_name", "")) == "多钩猫")

	# Elite monsters -> boss_spawn
	var elite_entry := CatalogService.find_by_monster_id("boss_spawn", ID_HALF_ORC_WARRIOR)
	assert(not elite_entry.is_empty(), "半兽勇士 must be found in boss_spawn")
	assert(str(elite_entry.get("display_name", "")) == "半兽勇士")
	assert(int(elite_entry.get("monster_id", -1)) == ID_HALF_ORC_WARRIOR)

	# Verify 多钩猫王 is also elite/boss_spawn
	var king_entry := CatalogService.find_by_monster_id("boss_spawn", ID_MULTI_HOOK_CAT_KING)
	assert(not king_entry.is_empty(), "多钩猫王 must be found in boss_spawn")
	assert(str(king_entry.get("display_name", "")) == "多钩猫王")

	# Verify 鸡 (ID 14) is retired: it must not resolve anywhere.
	assert(CatalogService.find_any_monster(ID_CHICKEN).is_empty(),
		"retired 鸡 must not resolve to any entry")


func test_half_orc_warrior_not_multi_hook_cat_king() -> void:
	var warrior := CatalogService.find_by_monster_id("boss_spawn", ID_HALF_ORC_WARRIOR)
	var king := CatalogService.find_by_monster_id("boss_spawn", ID_MULTI_HOOK_CAT_KING)

	assert(not warrior.is_empty(), "半兽勇士 must exist in boss_spawn")
	assert(not king.is_empty(), "多钩猫王 must exist in boss_spawn")

	# They must be different entries
	assert(int(warrior.get("monster_id", -1)) != int(king.get("monster_id", -1)),
		"半兽勇士 and 多钩猫王 must have different monster_ids")
	assert(str(warrior.get("display_name", "")) != str(king.get("display_name", "")),
		"半兽勇士 and 多钩猫王 must have different names")

	# Looking up ID 38 must return 半兽勇士, NOT 多钩猫王
	assert(str(warrior.get("display_name", "")) == "半兽勇士",
		"ID 38 must resolve to 半兽勇士")


func test_scorpion_not_chicken() -> void:
	var scorpion := CatalogService.find_by_monster_id("monster_spawn", ID_SCORPION)

	assert(not scorpion.is_empty(), "蝎子 must exist in monster_spawn")

	assert(int(scorpion.get("monster_id", -1)) == ID_SCORPION,
		"蝎子 entry must keep monster_id 45")

	assert(str(scorpion.get("display_name", "")) == "蝎子",
		"ID 45 must resolve to 蝎子")

	# Retired 鸡 (ID 14) must never resurface through any lookup path.
	assert(CatalogService.find_any_monster(ID_CHICKEN).is_empty(),
		"retired ID 14 must not resolve anywhere")
