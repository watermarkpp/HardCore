extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Pricing := preload("res://scripts/pricing_service.gd")
const Equipment := preload("res://scripts/equipment_rules.gd")
const Ids := preload("res://scripts/identity/entity_registry.gd")
var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()

func _run() -> void:
	check(GameData.ensure_loaded(), "actual catalogs are loaded")
	var wood := GameData.get_item_price_record("hc.item.000080")
	var bracelet := GameData.get_item_price_record("hc.item.000190")
	check(Pricing.adjusted_database_price(wood) == 50 and Pricing.adjusted_database_price(bracelet) == 17520,
		"existing base price and user-authorized bracelet price remain exact")
	var before := {}
	for id: Variant in GameData._price_by_item_id:
		var row: Dictionary = GameData._price_by_item_id[id]
		before[str(id)] = {"base_price": row.base_price, "adjusted": Pricing.adjusted_database_price(row), "source": row.source}
	var file := FileAccess.open("res://outputs/test_logs/pricing_identity_census.json", FileAccess.WRITE)
	check(file != null, "price/provenance census has an owned evidence path")
	if file != null:
		file.store_string(JSON.stringify(before, "  "))
		file.close()
	var gear := GameData.get_entity_record("hc.item.000080")
	var repair := Equipment.repair_cost(gear, 0, 4)
	gear.name = "展示文字已更改"
	check(Equipment.reference_price(gear) == 50, "equipment reference valuation does not use display name")
	check(repair > 0 and Equipment.repair_cost(gear, 0, 4) == repair, "equipment repair valuation does not use display name")
	check(Equipment.reference_price({"name": "木剑", "itemId": 999999}) == 0,
		"unknown explicit equipment identity cannot use a familiar display name")
	check(Equipment.reference_price({"name": "木剑", "itemId": 80.5}) == 0
		and Equipment.reference_price({"name": "木剑", "itemId": "80"}) == 0,
		"authoring-shaped price identities cannot truncate or coerce types")
	check(GameData.get_item_price_record({"itemId": 80, "item_id": 81, "name": "木剑"}).is_empty(),
		"conflicting source/runtime numeric identities cannot select either owner")
	var formal := Pricing.policy()
	formal.modifiers.itemBps = {"hc.item.000080": 7000}
	check(Pricing.adjusted_database_price(wood, formal) == 35, "policy accepts the registered item identity")
	var renamed := wood.duplicate(true)
	renamed.item_name = "显示文字不同"
	check(Pricing.adjusted_database_price(renamed, formal) == 35, "policy adjustment follows identity after display rename")
	for bad: String in ["木剑", "hc.item.999999", "hc.skill.warrior.thrusting"]:
		var invalid := Pricing.policy()
		invalid.modifiers.itemBps = {bad: 7000}
		check(Pricing.adjusted_database_price(wood, invalid) == 0 and not Pricing.quote_buy(wood, 1, {}, invalid).valid,
			"invalid policy identity rejects the whole quote: " + bad)
		check(not Pricing.quote_repair(wood, gear, {"durability": 0, "max_durability": 4}, {}, invalid).valid,
			"nested repair cannot reload default policy after invalid identity: " + bad)
		check(not Pricing.quote_repair_delta(wood, gear, {"durability": 4, "max_durability": 4}, 0, {}, invalid).valid
			and not Pricing.quote_repair_raw_delta(wood, gear, {"durability_raw": 0, "max_durability_raw": 4000}, 1, {}, invalid).valid
			and not Pricing.estimate_forge_materials([], {}, invalid).valid,
			"full-durability, raw repair and empty forge still reject invalid policy: " + bad)
	var duplicate := Pricing.policy()
	duplicate.modifiers.itemBps = {"hc.item.000080": 7000, "service:221": 9000}
	check(Pricing.adjusted_database_price(wood, duplicate) == 0, "two policy keys cannot own the same price source")
	var forged := Pricing.estimate_forge_materials(
		[{"entity_id": "hc.item.000080", "item_name": "改显示", "quantity": 2}],
		{"hc.item.000080": wood}, formal)
	check(forged.get("valid", false) and forged.get("total_value", 0) == 70,
		"forge valuation keys supplied records by registered identity")
	check(not Pricing.estimate_forge_materials([{"item_name": "木剑", "quantity": 2}], {"木剑": wood}).get("valid", false),
		"forge valuation rejects a display-only material")
	var wrong := Pricing.estimate_forge_materials([{"entity_id": "hc.item.000080", "quantity": 2}], {"hc.item.000080": bracelet})
	check(not wrong.get("valid", false), "forge record owner must match the requested identity")
	var saved := {}
	for key: String in ["_price_by_name", "_price_by_item_id", "_price_by_service_index"]:
		saved[key] = GameData.get(key).duplicate(true)
	var candidates: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/equipment_price_candidates_v1.json"))
	var user_price_count := 0
	for candidate: Dictionary in candidates.records:
		var candidate_source: Dictionary = candidate.get("source", {})
		if str(candidate_source.get("distribution", "")) == "user.pricing_ruling":
			user_price_count += 1
	check(candidates.records.size() == 50 and user_price_count == 19,
		"31 existing candidates and 19 exact user-priced identities remain present")
	for candidate: Dictionary in candidates.records:
		var entity_id := str(candidate.get("entity_id", ""))
		check(Ids.resolve(entity_id).get("kind") in ["item", "service_item"], "candidate has a registered owner: " + str(candidate.name))
		if entity_id.is_empty(): continue
		for key: String in saved: GameData.set(key, {})
		var renamed_candidate := candidate.duplicate(true)
		renamed_candidate.name = "与任何正式名称均不相同"
		GameData._register_price_record(renamed_candidate)
		var resolved := GameData.get_item_price_record(entity_id)
		check(resolved.get("entity_id", "") == Ids.canonical(entity_id) and resolved.get("base_price", 0) == candidate.price,
			"candidate imports by identity with unrelated display: " + entity_id)
	for key: String in saved: GameData.set(key, {})
	for n in 2:
		var row: Dictionary = candidates.records[n].duplicate(true)
		row.name = "两个不同物品共享展示"
		GameData._register_price_record(row)
	check(GameData.get_item_price_record("hc.item.000140").get("base_price", 0) == 50000
		and GameData.get_item_price_record("hc.item.000232").get("base_price", 0) == 35000,
		"identical display text never hides another registered price owner")
	for key: String in saved: GameData.set(key, saved[key])
	var primary := wood.duplicate(true)
	GameData._register_price_record({"entity_id": "hc.item.000080", "name": "新展示", "kind": "equipment", "category": "武器", "price": 9999})
	check(GameData.get_item_price_record("hc.item.000080") == primary, "candidate cannot replace primary by changing its display")
	var invalid_candidate: Dictionary = candidates.records[0].duplicate(true)
	for numeric: Variant in [140.5, "140", 232, false]:
		invalid_candidate.itemId = numeric
		check(GameData._price_candidate_owner(invalid_candidate).is_empty(), "candidate cannot coerce or contradict explicit legacy identity: " + str(numeric))
	invalid_candidate.erase("itemId")
	invalid_candidate.entity_id = "hc.item.999999"
	invalid_candidate.name = "木剑"
	GameData._register_price_record(invalid_candidate)
	check(GameData.get_item_price_record("hc.item.000080") == primary, "unknown explicit candidate cannot claim a known display")
	proof.write_receipt("pricing_identity_test", proof.records.size(), failures.size())
	print("PRICING_IDENTITY_%s checks=%d errors=%s" % ["PASS" if failures.is_empty() else "FAIL", proof.records.size(), str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
