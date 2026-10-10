extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const CanonicalSkills := preload("res://scripts/skills/skill_data_loader.gd")
const EquipmentGrantedSkillRules := preload("res://scripts/equipment_granted_skill_rules.gd")
var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _prepare() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	check(PlayerState.set_profession_identity("hc.profession.wizard"), "fixture enters the actual registered wizard owner")
	PlayerState.level = 50
	PlayerState.inventory = [{"item_id": 920026, "name": "可修改的展示文字", "count": 1}]

func _run() -> void:
	check(ContentLayers.ensure_loaded(), "formal content-layer catalog reaches component READY")
	check(GameData.ensure_loaded(), "formal GameData catalog reaches component READY: " + GameData.load_error)
	_prepare()
	var typed := GameData.get_skill("hc.skill.wizard.fireball", 0)
	check(typed.get("skill_id") == "wizard.fireball" and int(typed.get("skillLevel", -1)) == 0,
		"actual rank query accepts the registered skill identity")
	var result: Dictionary = PlayerState._learn_skill_result("火球术", 0)
	check(result.get("success", false), "legacy UI entrance consumes a real book by item ID despite changed display")
	check(PlayerState.item_count("hc.item.920026") == 0 and PlayerState.is_skill_learned("hc.skill.wizard.fireball"),
		"real book consumption and actual progression commit exactly once")
	check(PlayerState.learned_skills.has("hc.skill.wizard.fireball") and not PlayerState.learned_skills.has("火球术"),
		"actual progression has only formal skill ownership")
	_prepare()
	result = PlayerState.use_inventory_index_result(0)
	check(result.get("success", false) and PlayerState.is_skill_learned("hc.skill.wizard.fireball"),
		"real inventory-use entry routes the book ID into the same skill owner")
	_prepare()
	result = PlayerState._learn_skill_result("hc.skill.wizard.fireball", 0)
	check(result.get("success", false), "formal learning command uses the same real book identity")
	_prepare()
	PlayerState.inventory = [{"item_id": 920014, "name": "火球术", "count": 1}]
	var before: Array = PlayerState.inventory.duplicate(true)
	var progress: Dictionary = PlayerState._skill_progression.snapshot()
	result = PlayerState._learn_skill_result("hc.skill.wizard.fireball", 0)
	check(not result.get("success", false) and PlayerState.inventory == before
		and PlayerState._skill_progression.snapshot() == progress,
		"a potion forged with the book display name cannot consume or learn")
	_prepare()
	PlayerState.inventory.insert(0, {"item_id": 920014, "name": "火球术", "count": 1})
	result = PlayerState._learn_skill_result("hc.skill.wizard.fireball", 0)
	check(result.get("success", false) and PlayerState.item_count("hc.item.920026") == 0
		and PlayerState.item_count("hc.item.920014") == 1,
		"stale requested index relocates the actual book without consuming a similarly named potion")
	_prepare()
	before = PlayerState.inventory.duplicate(true)
	progress = PlayerState._skill_progression.snapshot()
	PlayerState._test_force_atomic_write_failure = true
	result = PlayerState._learn_skill_result("hc.skill.wizard.fireball", 0)
	PlayerState._test_force_atomic_write_failure = false
	check(not result.get("success", false) and result.get("reason") == "save_failed"
		and PlayerState.inventory == before and PlayerState._skill_progression.snapshot() == progress,
		"actual writer rejection restores the same typed book and original progression")
	var has_binding_query := GameData.has_method("skill_book_entity_id") and GameData.has_method("skill_book_skill_id")
	check(has_binding_query, "production publishes an explicit ID relation for book queries")
	if has_binding_query:
		check(GameData.call("skill_book_entity_id", "hc.skill.wizard.fireball") == "hc.item.920026",
			"actual source relation returns the hand-verified canonical fireball book")
		check(GameData.call("skill_book_skill_id", "hc.service_item.000990") == "hc.skill.wizard.fireball",
			"the existing service alias reaches the same registered skill")
		check(GameData.call("skill_book_skill_id", {"item_id": 920014, "name": "火球术"}) == ""
			and GameData.call("skill_book_entity_id", "hc.item.920026") == ""
			and GameData.call("skill_book_skill_id", "火球术") == ""
			and GameData.call("skill_book_skill_id", {"item_id": 920026.5, "name": "火球术"}) == ""
			and GameData.call("skill_book_skill_id", "hc.service_item.000978") == "",
			"cross-kind, forged-name and unsupported later books cannot enter the relation")
		var canonical_skill_ids := PackedStringArray()
		for skill_alias: String in CanonicalSkills.skill_ids():
			canonical_skill_ids.append(CanonicalSkills.entity_skill_id(skill_alias))
		var equipment_grants := {}
		for grant: Dictionary in EquipmentGrantedSkillRules.grant_definitions():
			equipment_grants[str(grant.get("skill_id", ""))] = true
		var ordinary_count := 0
		var ordinary_books := {}
		for skill_id: String in canonical_skill_ids:
			var book: String = GameData.call("skill_book_entity_id", skill_id)
			if equipment_grants.has(skill_id):
				check(book.is_empty(), "equipment-granted skill has no skill-book relation: " + skill_id)
				continue
			ordinary_count += 1
			check(not book.is_empty() and not ordinary_books.has(book)
				and GameData.call("skill_book_skill_id", book) == skill_id,
				"ordinary registered skill has one unambiguous book relation: " + skill_id)
			ordinary_books[book] = true
		check(ordinary_books.size() == ordinary_count and GameData._skill_books_by_skill.size() == ordinary_count,
			"book relation count equals the formal ordinary-skill closure")
	_finish()

func _finish() -> void:
	var receipt_ok := proof.write_receipt("skill_book_identity_test", proof.records.size(), failures.size())
	if not receipt_ok:
		failures.append("framework receipt write failed")
	print("SKILL_BOOK_IDENTITY_%s checks=%d failures=%s" % ["PASS" if receipt_ok and failures.is_empty() else "FAIL", proof.records.size(), str(failures)])
	get_tree().quit(0 if receipt_ok and failures.is_empty() else 1)
