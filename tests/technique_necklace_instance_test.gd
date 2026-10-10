extends Node

## RED contract fixture. Dynamic load is intentional: before the dedicated
## script exists this reports a controlled missing-API failure instead of a
## preload parse error.

const SKILL_POOL_PATH := "res://assets/data/relic_synthesis_v1.json"
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var script := load("res://scripts/equipment_random_special_instance_rules.gd")
	check(script != null, "dedicated random-special instance script must load")
	if script == null:
		_finish()
		return
	for method_name: String in [
		"is_technique_necklace",
		"allowed_technique_skill_ids",
		"create_technique_instance",
		"validate_technique_instance",
		"technique_skill_level_modifiers",
	]:
		check(method_name in script, "missing public API: " + method_name)
	if not failures.is_empty():
		_finish()
		return

	check(script.is_technique_necklace(250), "integer item 250 is technique necklace")
	check(script.is_technique_necklace(250.0), "integral float item 250 is technique necklace")
	check(script.is_technique_necklace({"itemId": 250}), "camel-case catalog item 250 is technique necklace")
	check(not script.is_technique_necklace({"item_id": 250, "itemId": 251}), "conflicting catalog IDs are rejected")
	check(not script.is_technique_necklace({"item_id": 251}), "item 251 is not technique necklace")
	var declared: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SKILL_POOL_PATH))
	var expected: Array[String] = []
	for profession: String in [
		"hc.profession.warrior",
		"hc.profession.wizard",
		"hc.profession.taoist",
	]:
		for skill_id: String in declared.get("skill_pools", {}).get(profession, []):
			expected.append(skill_id)
	var pool: Array = script.allowed_technique_skill_ids()
	check(pool.size() == 17, "technique pool must contain exactly 17 approved skills")
	check(pool == expected, "technique pool preserves source order and stable IDs")

	var catalog := {"itemId": 250, "name": "技巧项链", "kind": "equipment", "maxDurability": 8}
	var first: Dictionary = script.create_technique_instance(catalog, "fixture:technique:one")
	var repeated: Dictionary = script.create_technique_instance(catalog, "fixture:technique:one")
	check(first == repeated, "same stable drop key must produce the same roll")
	check(script.validate_technique_instance(first, catalog), "generated roll validates")
	var roll: Dictionary = first.get("technique_roll", {})
	check(str(roll.get("skill_id", "")) in pool, "rolled skill belongs to approved pool")
	check(int(roll.get("value", -1)) == 1, "rolled technique value is exactly +1")
	check(str(roll.get("drop_key_digest", "")) == "fixture:technique:one", "roll is bound to existing drop digest")
	var modifiers: Array = script.technique_skill_level_modifiers(first)
	check(modifiers.size() == 1, "technique instance exposes exactly one skill modifier")
	if modifiers.size() == 1:
		check(int(modifiers[0].get("value", -1)) == 1, "modifier value is +1")

	var legacy := {"item_id": 250, "name": "技巧项链", "count": 1}
	check(script.validate_technique_instance(legacy, catalog), "legacy item 250 remains load-compatible")
	var forged := first.duplicate(true)
	forged.technique_roll.skill_id = "hc.skill.wizard.fireball"
	check(not script.validate_technique_instance(forged, catalog), "unapproved skill is rejected")
	var allowed_but_wrong := first.duplicate(true)
	for skill_id: String in pool:
		if skill_id != str(roll.get("skill_id", "")):
			allowed_but_wrong.technique_roll.skill_id = skill_id
			break
	check(not script.validate_technique_instance(allowed_but_wrong, catalog), "allowed but digest-mismatched skill is rejected")
	_finish()


func _finish() -> void:
	print("TECHNIQUE_NECKLACE_INSTANCE_%s failures=%s" % ["PASS" if failures.is_empty() else "RED", str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
