extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	var fixtures: Array = [{"a": 1, "b": [1.0, -2, 0.25, "保存\n测试", null]}, {}, [1, 2.5], {"b": 2, "a": 1}]
	for value: Variant in fixtures:
		var expected := JSON.stringify(JSON.parse_string(JSON.stringify(value))).sha256_text()
		assert(PlayerState._shared_digest(value) == expected)
		assert(PlayerState._shared_digest(value) == expected)
	var path := "user://snapshot-cache-%d.json" % Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"nested":{"value":1}}'); file.close()
	var first := PlayerState._read_json_document(path)
	first.data.nested.value = 9
	assert(PlayerState._read_json_document(path).data.nested.value == 1)
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"nested":{"value":2}}'); file.close()
	assert(PlayerState._read_json_document(path).data.nested.value == 2, "same-size overwrite must invalidate")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"nested":{"value":?}}'); file.close()
	assert(not PlayerState._read_json_document(path).valid, "malformed overwrite must not reuse cached parse")
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
	assert(not PlayerState._read_json_document(path).exists)
	var item := GameData.get_item_record("木剑")
	var drop := ItemDropInstanceRules.create_instance(item, "cache-validation-contract")
	assert(not drop.is_empty())
	assert(ItemDropInstanceRules.validate_instance(drop, item))
	for field: String in drop:
		for invalid: Variant in [null, false, -99, "internal-invalid", {}, []]:
			var changed := drop.duplicate(true)
			changed[field] = invalid
			assert(ItemDropInstanceRules.validate_instance(changed, item) == ItemDropInstanceRules._validate_instance_uncached(changed, item), "changed field bypassed validation: " + field)
	var extra := drop.duplicate(true); extra["internal_extra"] = 1
	assert(not ItemDropInstanceRules.validate_instance(extra, item))
	for field: String in ["itemId", "name", "category", "kind", "maxDurability"]:
		var catalog := item.duplicate(true)
		catalog[field] = "invalid" if field in ["name", "category", "kind"] else -1
		assert(ItemDropInstanceRules.validate_instance(drop, catalog) == ItemDropInstanceRules._validate_instance_uncached(drop, catalog), "catalog changed without revalidation")
	assert(ItemDropInstanceRules.validate_instance(drop, item))
	print("PERSISTENCE_SNAPSHOT_CACHE_PASS")
	get_tree().quit()
