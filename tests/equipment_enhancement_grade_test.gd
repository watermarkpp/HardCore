extends Node

const Grade := preload("res://scripts/layers/rules/equipment_enhancement_grade.gd")


func _ready() -> void:
	var master: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/equipment_attribute_master.json"))
	var classification: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/ui/item_name_rarity_v1.json"))
	var expected_grades := {"default": 0, "wooma": 1, "zuma": 2, "redmoon": 3, "ultra_rare": 3}
	var forbidden_tiers := ["PRAYER_MEMORY", "MYSTERY_SIGNATURE", "MAGICBLOOD_RAINBOW", "SPECIAL_RING", "FUNCTIONAL_SPECIAL"]
	var accessory_categories := ["戒指", "手镯", "项链"]
	assert(Grade.records().size() == 175)
	for item: Dictionary in master.records:
		var item_id := int(item.itemId)
		var row := Grade.record_for_id(item_id)
		var source: Dictionary = classification.records[str(item_id)]
		assert(row.item_id == item_id and row.name == item.name and row.category == item.category)
		assert(int(row.material_grade) == int(expected_grades[source.name_style]))
		var allowed := str(item.category) in accessory_categories and str(source.source_tier) not in forbidden_tiers and item_id not in [250, 251]
		assert(Grade.can_use_as_accessory_material(item_id) == allowed)
	assert(Grade.grade_for_id(940010) == -1)
	for forbidden_id: int in [219, 220, 225, 226, 227, 229, 230, 231, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260]:
		assert(not Grade.can_use_as_accessory_material(forbidden_id), "special gear must not be forge material: %d" % forbidden_id)
	print("EQUIPMENT_ENHANCEMENT_GRADE_PASS")
	get_tree().quit(0)
