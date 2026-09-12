extends Node
const Style := preload("res://scripts/ui_item_name_style.gd")
var failures: Array[String] = []
var checks := 0
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()
func _run() -> void:
	expect(Style.ensure_loaded(), "generated UI identity map loads")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Style.DATA_PATH))
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/drop/dpv2_item_tier_authority_v1.json"))
	var expected_groups := {
		"WOOMA_GEAR": "wooma", "ZUMA_GEAR": "zuma", "REDMOON_SET": "redmoon",
		"LEGENDARY_WEAPON": "ultra_rare", "SPECIAL_RING": "ultra_rare",
		"FUNCTIONAL_SPECIAL": "ultra_rare", "RARE_LEGACY": "ultra_rare",
	}
	var covered := {"wooma": 0, "zuma": 0, "redmoon": 0, "ultra_rare": 0}
	for row: Dictionary in source["records"]:
		var item_id := int(row["canonical_item_id"])
		var expected := str(expected_groups.get(row["tier"], "default"))
		var result := Style.describe({"itemId": item_id, "name": row["canonical_name"]})
		expect(result["group"] == expected, "exact tier color id=" + str(item_id))
		expect((result["color"] as Color).is_equal_approx(Color(data["palette"][expected])), "palette id=" + str(item_id))
		if covered.has(expected):
			covered[expected] += 1
		var renamed := Style.describe({"itemId": item_id, "name": "任意显示名"}, {"name": "极品+9", "instance_id": "not-a-canonical-id", "modifiers": {"attack": 99}})
		expect(renamed["group"] == expected, "name/affixes must not change rarity")
	for group: String in covered:
		expect(covered[group] > 0, "real source coverage " + group)
	expect(Style.display_name({"itemId": 191, "name": "三眼手镯"}, {"name": "   "}) == "三眼手镯", "empty instance name fallback")
	expect(Style.canonical_id({"item_id": true, "itemId": 191}) == 191, "bool is not ID")
	expect(Style.canonical_id({"instance_id": "191"}) == -1, "opaque instance_id ignored")
	expect(Style.describe({"itemId": 999999999, "name": "麻痹戒指"})["group"] == "default", "unknown ID is not classified by name")
	expect(Style.describe({"itemId": 191}, {"item_id": 999999999})["identity_conflict"], "conflicting identities reported")
	for message: String in failures:
		push_error("R6_NAME_STYLE " + message)
	print("R6_1_NAME_STYLE_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
