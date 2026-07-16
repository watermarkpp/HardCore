extends Node


func _ready() -> void:
	var catalog := _json("res://assets/data/vanilla_176/profession_magic_info.json")
	var skills := _json("res://assets/data/vanilla_176/skills.json")
	var growth := _json("res://assets/data/vanilla_176/profession_growth.json")
	assert(catalog.classification == "B/C-candidate")
	assert(catalog.source.distribution_id == "server.crystal.cjlaaa")
	assert(catalog.source.source_priority.tier == "primary" and catalog.source.source_priority.weight == 100)
	assert(catalog.source.original_path == "Server.MirDB")
	assert(catalog.source.magic_info_record_count == 107)
	assert(catalog.reader_contract.distribution_id == "source.minipizza_mir2.server")
	assert(catalog.reader_contract.original_path == "Server/MirDatabase/MagicInfo.cs")
	assert(catalog.reader_contract.source_priority.tier == "auxiliary_1")
	assert(catalog.primary_missing_evidence.size() == 1)
	assert(catalog.primary_missing_evidence[0].status == "incompatible")
	assert(catalog.records.size() == 33)
	assert(growth.sourcePolicy.character_presentation == "male_only")

	var ids := {}
	var counts := {"warrior": 0, "wizard": 0, "taoist": 0}
	for record: Dictionary in catalog.records:
		var skill_id := str(record.skill_id)
		assert(skill_id.contains("."))
		assert(not ids.has(skill_id) and not str(record.display_name).is_empty())
		assert(record.classification == "B/C-candidate")
		assert(record.mana_cost_by_level.size() == 4 and record.cooldown_ms_by_level.size() == 4)
		ids[skill_id] = true
		counts[record.profession_id] += 1
	assert(counts == {"warrior": 6, "wizard": 14, "taoist": 13})
	assert(skills.records.size() == 132)
	for row: Dictionary in skills.records:
		assert(ids.has(row.skill_id))
		assert(row.manaCost != null)
		assert(row.service_candidate.classification == "B/C-candidate")
		assert(row.source_trace.mana_cost.distribution_id == "server.crystal.cjlaaa")
	print("PROFESSION_MAGIC_INFO_PASS: 3 profession IDs, 33 skill IDs, 132 traced level rows")
	get_tree().quit(0)


func _json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var value: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	assert(value is Dictionary, "%s is invalid JSON" % path)
	return value
