extends Node

## B07A-GD-005/006. The fixture uses the real READY catalog and real
## GameData builders. Only detached dictionaries are mutated; formal JSON
## authorities and the production singleton are restored after reload checks.
const GameDataScript := preload("res://scripts/game_data.gd")
const CanonicalSkills := preload("res://scripts/skills/skill_data_loader.gd")
const EquipmentGrantedSkillRules := preload("res://scripts/equipment_granted_skill_rules.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failures: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _new_fixture() -> Node:
	var fixture: Node = GameDataScript.new()
	fixture.maps = GameData.maps.duplicate(true)
	fixture.items = GameData.items.duplicate(true)
	fixture.skills = GameData.skills.duplicate(true)
	fixture.drops = GameData.drops.duplicate(true)
	fixture.tasks = GameData.tasks.duplicate(true)
	fixture.item_catalog = GameData.item_catalog.duplicate(true)
	fixture.service_item_catalog = GameData.service_item_catalog.duplicate(true)
	fixture.equipment_price_candidates = GameData.equipment_price_candidates.duplicate(true)
	fixture.item_runtime_authority = GameData.item_runtime_authority.duplicate(true)
	fixture.bich_community_baseline = GameData.bich_community_baseline.duplicate(true)
	return fixture

func _release_fixture(fixture: Node) -> void:
	if is_instance_valid(fixture):
		fixture.free()

func _skill_books(source: Array) -> Array:
	var result: Array = []
	for raw: Variant in source:
		if raw is Dictionary and str(raw.get("kind", "")) == "skill_book" and bool(raw.get("usable", true)):
			result.append(raw)
	return result

func _first_book_service_index() -> int:
	for row: Dictionary in _skill_books(GameData.item_catalog):
		var service_index := GameData._service_index(row)
		if service_index >= 0:
			return service_index
	return -1

func _run() -> void:
	check(ContentLayers.ensure_loaded(), "formal content-layer catalog reaches component READY")
	check(GameData.ensure_loaded(), "formal GameData catalog reaches component READY: " + GameData.load_error)

	var formal_books := _skill_books(GameData.item_catalog)
	check(not formal_books.is_empty(), "component READY catalog contains skill-book records")
	var normal := _new_fixture()
	check(normal._build_indexes(), "complete detached catalog builds through the unique index owner")
	check(normal._skill_books_by_skill.size() == GameData._skill_books_by_skill.size(),
		"complete detached index preserves component READY target count")
	for target: String in GameData._skill_books_by_skill:
		check(normal._skill_books_by_skill.get(target, "") == GameData._skill_books_by_skill[target],
			"complete detached index preserves target identity: " + target)
	check(normal._skill_books_by_skill.size() == CanonicalSkills.skill_ids().size() - EquipmentGrantedSkillRules.grant_definitions().size(),
		"complete index has the expected book target closure")
	_release_fixture(normal)

	# Mutate only a detached authority copy so the actual _build_indexes caller
	# rejects the relation and clears every public catalog projection.
	var invalid := _new_fixture()
	var invalid_index := _first_book_service_index()
	var invalid_policies: Dictionary = invalid.item_runtime_authority.get("policies", {}).duplicate(true)
	var invalid_overrides: Dictionary = invalid_policies.get("serviceOverridesByIndex", {}).duplicate(true)
	invalid_overrides[str(invalid_index)] = {"learnSkillId": "hc.skill.invalid.fixture"}
	invalid_policies["serviceOverridesByIndex"] = invalid_overrides
	invalid.item_runtime_authority["policies"] = invalid_policies
	var invalid_signal := {"count": 0}
	invalid.database_reloaded.connect(func(): invalid_signal["count"] += 1)
	check(invalid_index >= 0, "invalid fixture selects an actual skill-book service index")
	check(not invalid._build_indexes(), "invalid target rejects through the unique index owner")
	check(invalid.load_error == "skill_book_index_incomplete",
		"runtime importer rejects sanitized unknown target as stable incomplete load_error")
	check(invalid.item_catalog.is_empty() and invalid._catalog_by_item_id.is_empty()
		and invalid._catalog_by_service_index.is_empty() and invalid._skill_books_by_skill.is_empty(),
		"invalid relation publishes no partial catalog or skill-book index")
	check(int(invalid_signal["count"]) == 0, "failed index build publishes no database_reloaded signal")
	check(invalid._price_by_name.is_empty() and invalid._price_by_item_id.is_empty()
		and invalid._price_by_service_index.is_empty(),
		"invalid relation publishes no partial price projection")
	_release_fixture(invalid)

	var invalid_direct := _new_fixture()
	var invalid_direct_catalog: Array = invalid_direct.item_catalog.duplicate(true)
	for row: Dictionary in invalid_direct_catalog:
		if str(row.get("kind", "")) == "skill_book" and bool(row.get("usable", true)):
			row["learnSkillId"] = "hc.skill.invalid.fixture"
			row["usable"] = true
			break
	invalid_direct.item_catalog = invalid_direct_catalog
	check(not invalid_direct._build_skill_book_index(), "direct usable unknown target rejects the skill-book index")
	check(invalid_direct.load_error == "skill_book_index_relation_invalid",
		"direct usable unknown target exposes stable relation load_error")
	_release_fixture(invalid_direct)

	var duplicate := _new_fixture()
	var duplicate_books: Array = _skill_books(duplicate.item_catalog)
	check(duplicate_books.size() >= 2, "duplicate fixture has two distinct books")
	if duplicate_books.size() >= 2:
		var duplicate_catalog: Array = duplicate.item_catalog.duplicate(true)
		var first_target := str(duplicate_books[0].get("learnSkillId", ""))
		var changed := false
		for row: Dictionary in duplicate_catalog:
			if changed or str(row.get("kind", "")) != "skill_book" or not bool(row.get("usable", true)):
				continue
			if str(row.get("learnSkillId", "")) != first_target:
				row["learnSkillId"] = first_target
				changed = true
		duplicate.item_catalog = duplicate_catalog
		check(changed, "duplicate fixture changes a second book target")
		check(not duplicate._build_skill_book_index(), "duplicate target rejects the skill-book index")
		check(str(duplicate.load_error).begins_with("skill_book_index_duplicate_target"),
			"duplicate target exposes stable duplicate load_error")
	_release_fixture(duplicate)

	var missing := _new_fixture()
	var missing_catalog: Array = []
	var removed := false
	for row: Variant in missing.item_catalog:
		if not removed and row is Dictionary and str(row.get("kind", "")) == "skill_book" and bool(row.get("usable", true)):
			removed = true
			continue
		missing_catalog.append(row)
	missing.item_catalog = missing_catalog
	check(removed, "missing fixture removes one actual book")
	check(not missing._build_skill_book_index(), "missing target rejects the skill-book index")
	check(missing.load_error == "skill_book_index_incomplete", "missing target exposes stable incomplete load_error")
	_release_fixture(missing)

	var equipment_misbinding := _new_fixture()
	var grant_id := ""
	for grant: Dictionary in EquipmentGrantedSkillRules.grant_definitions():
		if bool(grant.get("equipment_granted", false)):
			grant_id = str(grant.get("skill_id", ""))
			break
	var misbound_catalog: Array = equipment_misbinding.item_catalog.duplicate(true)
	for row: Dictionary in misbound_catalog:
		if str(row.get("kind", "")) == "skill_book" and bool(row.get("usable", true)):
			row["learnSkillId"] = grant_id
			break
	equipment_misbinding.item_catalog = misbound_catalog
	check(not grant_id.is_empty(), "equipment-granted fixture has a registered target")
	check(not equipment_misbinding._build_skill_book_index(), "equipment-granted skill relation rejects the index")
	check(str(equipment_misbinding.load_error).begins_with("skill_book_index_equipment_grant_conflict"),
		"equipment-granted relation exposes stable conflict load_error")
	_release_fixture(equipment_misbinding)

	# Exercise the actual direct reload state owner when its content owner is
	# unavailable, then restore readiness and reload the formal source.
	var content_ready_before := ContentLayers._initial_load_complete
	var reload_signals := {"count": 0}
	var connection := func(): reload_signals["count"] += 1
	GameData.database_reloaded.connect(connection)
	GameData._initial_load_complete = true
	ContentLayers._initial_load_complete = false
	check(not GameData.load_database(), "direct reload rejects an unavailable content owner")
	check(not GameData.is_loaded(), "direct reload failure clears the loaded state")
	check(GameData.load_error == "content_layers_not_ready", "direct reload reports its unavailable content owner")
	check(int(reload_signals["count"]) == 0, "direct reload failure publishes no success signal")
	ContentLayers._initial_load_complete = content_ready_before
	check(GameData.load_database(), "formal merged database restores successfully")
	check(int(reload_signals["count"]) == 1, "restored direct reload publishes one success signal")
	GameData.database_reloaded.disconnect(connection)
	check(GameData.is_loaded(), "restored direct reload publishes loaded state")
	_finish()

func _finish() -> void:
	var failed := failures.size()
	var receipt_ok := proof.write_receipt("skill_book_load_rejection_20261010_test", checks, failed)
	if not receipt_ok:
		failures.append("framework receipt write failed")
	print("SKILL_BOOK_LOAD_REJECTION_%s checks=%d errors=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if receipt_ok and failures.is_empty() else 1)
