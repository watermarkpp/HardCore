extends Node

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var script := load("res://scripts/mystery_equipment_instance_rules.gd")
	check(script != null, "mystery instance rule script must load")
	if script == null:
		_finish()
		return
	for method_name: String in ["is_mystery_item", "create_roll", "validate_roll", "modifiers", "requirement"]:
		check(script.new().has_method(method_name), "missing public API: " + method_name)
	if not failures.is_empty():
		_finish()
		return
	check(script.is_mystery_item(218), "218 is mystery")
	check(script.is_mystery_item({"itemId": 219}), "219 camel catalog is mystery")
	check(script.is_mystery_item(220.0), "220 integral float is mystery")
	check(not script.is_mystery_item(221), "non-mystery item rejected")
	check(not script.is_mystery_item({"itemId": 218, "item_id": 219}), "conflicting IDs rejected")

	for item_id: int in [218, 219, 220]:
		var catalog := {"itemId": item_id, "requirementType": "level", "requirementValue": 18}
		var first: Dictionary = script.create_roll(catalog, "mystery-fixture:" + str(item_id))
		var repeated: Dictionary = script.create_roll(catalog, "mystery-fixture:" + str(item_id))
		if first.is_empty() or repeated.is_empty():
			failures.append("source validation blocked mystery roll for item %d: %s" % [item_id, script.source_validation_error()])
			continue
		check(first == repeated, "roll is deterministic for item " + str(item_id))
		check(script.validate_roll({"item_id": item_id, "count": 1, "drop_key_digest": first.get("drop_key_digest"), "mystery_roll": first}, catalog), "roll validates for item " + str(item_id))
		check(first.get("stats", {}).has("magic_max"), "formal magic_max key is present")
		check(first.get("stats", {}).get("magic_attack_max", null) == null, "legacy magic_attack_max is absent")
		check(script.requirement({"mystery_roll": first}) == first.get("requirement", {}), "requirement API returns roll requirement")
		var forged: Dictionary = first.duplicate(true)
		forged.stats.attack_max = int(forged.stats.attack_max) + 1
		check(not script.validate_roll({"item_id": item_id, "count": 1, "drop_key_digest": first.get("drop_key_digest"), "mystery_roll": forged}, catalog), "tampered stat rejected")
		var outer_digest := {"item_id": item_id, "count": 1, "drop_key_digest": "other", "mystery_roll": first}
		check(not script.validate_roll(outer_digest, catalog), "outer digest mismatch rejected")
		var extra_field: Dictionary = first.duplicate(true)
		extra_field.extra = true
		check(not script.validate_roll({"item_id": item_id, "count": 1, "drop_key_digest": first.get("drop_key_digest"), "mystery_roll": extra_field}, catalog), "extra roll field rejected")

	check(script.validate_roll({"item_id": 218, "count": 1}, {"itemId": 218, "requirementValue": 18}), "legacy no-roll item remains valid")
	check(not script.validate_roll({"item_id": 218.5, "count": 1}, {"itemId": 218, "requirementValue": 18}), "fractional instance ID rejected")
	check(not script.validate_roll({"item_id": 218, "count": 2}, {"itemId": 218, "requirementValue": 18}), "legacy wrong count rejected")
	_finish()

func _finish() -> void:
	print("MYSTERY_EQUIPMENT_INSTANCE_%s failures=%s" % ["PASS" if failures.is_empty() else "RED", str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
