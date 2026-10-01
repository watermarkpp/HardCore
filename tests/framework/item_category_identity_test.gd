extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Ids := preload("res://scripts/identity/entity_registry.gd")
const Categories := preload("res://scripts/identity/item_category_identity.gd")
const Slots := preload("res://scripts/identity/equipment_identity_codec.gd")
const Forge := preload("res://scripts/layers/rules/equipment_enhancement_rules.gd")
const Pricing := preload("res://scripts/pricing_service.gd")
const Gem := preload("res://scripts/items/socket_gem_rules.gd")
var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var loaded := GameData.ensure_loaded()
	check(loaded, "actual production catalog is available: " + GameData.load_error)
	var census := {}
	var members := []
	for item: Dictionary in GameData.item_catalog:
		var category := str(item.get("category", ""))
		census[category] = int(census.get(category, 0)) + 1
		members.append({"item_id": GameData._stable_item_id(item), "service_index": GameData._service_index(item),
			"entity_id": GameData.item_entity_id(item), "category": category, "kind": item.get("kind", ""),
			"category_id": item.get("category_id", "")})
	var file := FileAccess.open("res://outputs/test_logs/item_category_runtime_inventory.json", FileAccess.WRITE)
	check(file != null, "mechanical category census has an owned local evidence path")
	if file != null:
		file.store_string(JSON.stringify({"counts": census, "members": members}, "  "))
		file.close()
	var expected := {"武器": "hc.item_category.weapon", "盔甲": "hc.item_category.armor", "头盔": "hc.item_category.helmet",
		"项链": "hc.item_category.necklace", "手镯": "hc.item_category.bracelet", "戒指": "hc.item_category.ring"}
	for legacy_category: String in expected:
		var actual: Dictionary = {}
		for item: Dictionary in GameData.item_catalog:
			if item.get("category") == legacy_category:
				actual = GameData.get_entity_record(GameData.item_entity_id(item))
				break
		check(not actual.is_empty() and actual.get("category_id") == expected[legacy_category],
			"actual primary equipment has the declared category identity: " + legacy_category)
		check(not Ids.resolve(expected[legacy_category], "item_category").is_empty(),
			"category identity is formally registered: " + str(expected[legacy_category]))
	var has_query := GameData.has_method("item_category_id")
	check(has_query, "actual consumers have a strict typed category query")
	if has_query:
		var weapon_id := GameData.item_entity_id("木剑")
		check(GameData.call("item_category_id", weapon_id) == "hc.item_category.weapon",
			"typed item query resolves its primary category owner")
		check(GameData.call("item_category_id", "武器") == "" and GameData.call("item_category_id", "木剑") == ""
			and GameData.call("item_category_id", "hc.skill.warrior.thrusting") == "",
			"category query rejects display strings and cross-kind references")
		check(GameData.call("item_category_id", {"item_id": 81.5, "name": "木剑"}) == "",
			"invalid numeric item identity cannot select a category through its display")
		check(GameData.call("item_category_id", {"itemId": 81.5, "name": "木剑"}) == ""
			and GameData.call("item_category_id", {"serviceIndex": true, "name": "木剑"}) == "",
			"source-shaped malformed identity also cannot fall through to display")
		var weapon := GameData.get_entity_record(weapon_id)
		weapon["name"] = "任意物品展示文字"
		weapon["category"] = "任意类别展示文字"
		check(GameData.call("item_category_id", weapon) == "hc.item_category.weapon",
			"changing presentation metadata leaves the typed category owner unchanged")
		weapon["category_id"] = "hc.item_category.unknown"
		check(GameData.call("item_category_id", weapon) == "",
			"unknown explicit category cannot be repaired through legacy display")
	var missing_ids := 0
	for item: Dictionary in GameData.item_catalog:
		if Ids.resolve(str(item.get("category_id", "")), "item_category").is_empty(): missing_ids += 1
	check(missing_ids == 0, "every actual runtime catalog member carries a known category ID")
	var equipment_missing := 0
	for item: Dictionary in GameData.items:
		if Ids.resolve(str(item.get("category_id", "")), "item_category").is_empty(): equipment_missing += 1
	check(equipment_missing == 0 and GameData.items.size() == 175,
		"primary equipment API carries all 175 formal categories without replacing attributes")
	check(GameData.item_category_id(Gem.ENTITY_ID) == "hc.item_category.gems",
		"default-off socket fixture has the same formal category metadata boundary")
	check(Categories.import_legacy_category("衣服") == "hc.item_category.armor"
		and Categories.import_legacy_category("盔甲") == "hc.item_category.armor",
		"exact legacy armor aliases share one formal category")
	check(Categories.import_legacy_category("木剑") == "" and Categories.import_legacy_category("武") == ""
		and Categories.import_legacy_category("hc.slot.weapon") == "",
		"category import does not infer names prefixes or cross-kind symbols")
	check(Slots.slots_for_category("hc.item_category.bracelet") == ["hc.slot.bracelet_left", "hc.slot.bracelet_right"]
		and Slots.slots_for_category("hc.item_category.ring") == ["hc.slot.ring_left", "hc.slot.ring_right"],
		"paired slot ordering and cycle ownership are explicitly retained")
	check(Slots.slots_for_category("戒指").is_empty() and Slots.slots_for_category("hc.slot.ring_left").is_empty(),
		"formal slot lookup rejects legacy and wrong kind references")
	for pair: Array in [["hc.item_category.weapon", "武器", 7], ["hc.item_category.armor", "盔甲", 3], ["hc.item_category.helmet", "头盔", 3]]:
		for stage in range(1, int(pair[2]) + 1):
			check(Forge.quote_probability(pair[0], stage, 20, 3, 3, 3) == Forge.quote_probability(pair[1], stage, 20, 3, 3, 3)
				and Forge.forge_gold_cost(pair[0], stage) == Forge.forge_gold_cost(pair[1], stage),
				"formal forge probabilities and costs preserve the exact legacy stage: %s/%d" % [pair[0], stage])
	check(Forge.max_stage("hc.item_category.unknown") == 0 and Forge.max_stage("木剑") == 0,
		"forge rejects unknown category identities")
	var price := {"base_price": 100, "category_id": "hc.item_category.weapon", "category": "任意展示类别", "item_key": "item:81"}
	check(Pricing.adjusted_database_price(price, {"modifiers": {"categoryBps": {"hc.item_category.weapon": 7000}}}) == 70,
		"price modifier uses formal category despite changed display metadata")
	check(Pricing.adjusted_database_price(price, {"modifiers": {"categoryBps": {"武器": 7000}}}) == 70,
		"old policy enums enter through the one declared import boundary")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Categories.PATH))
	var bad := source.duplicate(true)
	bad.records[0].equipment_slots = ["hc.skill.warrior.thrusting"]
	check(not Categories.publish(bad) and Categories.slots("hc.item_category.weapon") == ["hc.slot.weapon"],
		"invalid slot relation cannot partially replace the accepted table")
	bad = source.duplicate(true)
	bad.records[1].legacy_categories.append("武器")
	check(not Categories.publish(bad) and Categories.import_legacy_category("武器") == "hc.item_category.weapon",
		"duplicate legacy ownership fails atomically")
	bad = source.duplicate(true)
	bad.schema_version = 2
	check(not Categories.publish(bad), "future category contract is terminal")
	bad = source.duplicate(true)
	bad.records[0].display_name = "类别显示已更名"
	check(Categories.publish(bad) and Categories.import_legacy_category("武器") == "hc.item_category.weapon",
		"display rename cannot move a registered category or legacy relation")
	check(Categories.publish(source), "authoritative runtime category table restored after candidate checks")
	proof.write_receipt("item_category_identity_test", proof.records.size(), failures.size())
	print("ITEM_CATEGORY_IDENTITY_%s checks=%d categories=%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", proof.records.size(), JSON.stringify(census), str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
