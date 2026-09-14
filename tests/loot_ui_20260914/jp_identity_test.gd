extends Node
const Rules := preload("res://scripts/item_drop_instance_rules.gd")
const NameStyle := preload("res://scripts/ui_item_name_style.gd")

func _ready() -> void:
	assert(GameData.ensure_loaded())
	var catalog := GameData.get_item_rules_record({"item_id": 80})
	var durability_only := 0
	var stat_bonus := 0
	for index in range(1000):
		var rolled := Rules.create_instance(catalog, "v81-jp:%d" % index)
		var saved: Dictionary = JSON.parse_string(JSON.stringify(rolled))
		assert(Rules.validate_instance(saved, catalog), "old roll data must remain valid")
		if not saved.modifiers.is_empty():
			stat_bonus += 1
			assert(Rules.is_affixed_instance(saved, catalog))
			assert(NameStyle.display_name(catalog, saved).begins_with("★"))
		elif bool(saved.drop_affix.applied):
			durability_only += 1
			assert(int(saved.max_durability_raw) > int(catalog.maxDurability) * 1000)
			assert(not Rules.is_affixed_instance(saved, catalog))
			assert(not NameStyle.display_name(catalog, saved).begins_with("★"))
	assert(durability_only > 100 and stat_bonus > 50)
	print("JP_IDENTITY_V81_PASS durability_only=%d stat_bonus=%d" % [durability_only, stat_bonus])
	get_tree().quit()
