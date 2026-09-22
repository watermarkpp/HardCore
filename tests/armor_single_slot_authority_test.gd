extends Node

const Provider := preload("res://scripts/drop/user_loot_sheet_provider.gd")
const LootRuntime := preload("res://scripts/layers/runtime/loot_runtime_service.gd")
const DIRECTIVE_PATH := "res://tools/loot_sheet_compiler/evidence/armor_single_slot_directive_v92.json"
const MASTER_PATH := "res://assets/data/equipment_attribute_master.json"
const EXPECTED_SLOTS := 6042
const EXPECTED_GROUPS := 102
const EXPECTED_AFFECTED_MONSTERS := 37
const EXPECTED_EXCEPTION_IDS := {235: 140, 236: 144, 237: 142, 238: 141, 239: 145, 240: 143}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded(), GameData.load_error)
	var directive: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIRECTIVE_PATH))
	var master: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MASTER_PATH))
	var authority: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Provider.PATH))
	assert(str(directive.get("directive_id")) == "armor.single_slot.user.20260922.v92")
	assert(str(authority.source.get("armor_single_slot_directive_sha256")) == FileAccess.get_sha256(DIRECTIVE_PATH))
	assert(int(authority.summary.get("armor_single_slot_removed_slots")) == EXPECTED_GROUPS)
	var provider := Provider.new()
	assert(provider.valid, provider.load_error)
	assert(provider.monster_count == 126 and provider.slot_count == EXPECTED_SLOTS)
	assert(provider.overlay_slot_count == 168 and provider.new_slot_count == 41)
	var loot := LootRuntime.new()
	var master_armor := {}
	for record: Dictionary in master.records:
		if str(record.category) == "盔甲":
			master_armor[int(record.itemId)] = record
	var output_by_source := {}
	for identity: Dictionary in directive.armor_output_identities:
		var source_id := int(identity.source_item_id)
		var output_id := int(identity.output_item_id)
		assert(master_armor.has(source_id) and master_armor.has(output_id))
		assert(str(master_armor[source_id].name) == str(identity.source_name))
		var actual: Dictionary = loot._drop_output_item_record(source_id, str(identity.source_name))
		assert(str(actual.get("identity_status")) == "resolved", str(actual))
		assert(int(actual.get("item_id", -1)) == output_id, str(actual))
		output_by_source[source_id] = output_id
	assert(output_by_source.size() == 24 and master_armor.size() == 24)
	var affected_monsters := {}
	var removed_count := 0
	for group: Dictionary in directive.groups:
		var monster_id := int(group.monster_id)
		var output_id := int(group.output_item_id)
		affected_monsters[monster_id] = true
		var profile: Dictionary = provider.profile(monster_id)
		var retained: Array = []
		for slot: Dictionary in profile.get("slots", []):
			if int(output_by_source.get(int(slot.get("canonical_item_id", -1)), -1)) == output_id:
				retained.append(slot)
		assert(retained.size() == 1, "armor trial count %d/%d: %d" % [monster_id, output_id, retained.size()])
		assert(str(retained[0].slot_uid) == str(group.keep_slot_uid))
		var expected_keep := {}
		for expected: Dictionary in group.expected_slots:
			if str(expected.slot_uid) == str(group.keep_slot_uid):
				expected_keep = expected
		assert(not expected_keep.is_empty() and retained[0] == expected_keep, "retained probability/priority/identity changed")
		var actual_probability: Dictionary = provider.probability(monster_id, str(group.keep_slot_uid))
		assert(bool(actual_probability.get("ok", false)))
		assert(int(actual_probability.final_numerator) == int(expected_keep.final_numerator))
		assert(int(actual_probability.final_denominator) == int(expected_keep.final_denominator))
		for removed_uid: String in group.remove_slot_uids:
			assert(not provider.owns(monster_id, removed_uid), "deleted armor trial was restored: " + removed_uid)
			removed_count += 1
	assert(directive.groups.size() == EXPECTED_GROUPS and removed_count == EXPECTED_GROUPS)
	assert(affected_monsters.size() == EXPECTED_AFFECTED_MONSTERS)
	# Check every compiled profile, including monsters without an edited group.
	for monster: Dictionary in authority.monsters:
		var seen_outputs := {}
		for slot: Dictionary in monster.slots:
			var source_id := int(slot.get("canonical_item_id", -1))
			if not output_by_source.has(source_id):
				continue
			var output_id := int(output_by_source[source_id])
			assert(not seen_outputs.has(output_id), "unresolved duplicate armor output on monster %d" % int(monster.monster_id))
			seen_outputs[output_id] = true
	var exceptions_seen := {}
	for exception: Dictionary in directive.frozen_exceptions:
		var monster_id := int(exception.monster_id)
		assert(EXPECTED_EXCEPTION_IDS.has(monster_id))
		assert(int(exception.source_item_id) == int(EXPECTED_EXCEPTION_IDS[monster_id]))
		var expected: Dictionary = exception.expected_slots[0]
		var profile: Dictionary = provider.profile(monster_id)
		var exact: Array = profile.get("slots", []).filter(func(slot: Dictionary) -> bool:
			return str(slot.slot_uid) == str(expected.slot_uid))
		assert(exact.size() == 1 and exact[0] == expected, "dark-boss top armor was changed")
		exceptions_seen[monster_id] = true
	assert(exceptions_seen.size() == 6)
	# Exercise the actual RNG path: exactly one eligible/rolled source slot for
	# each output armor, rather than merely counting rows in the exported data.
	for monster_id: int in affected_monsters:
		var rng := RandomNumberGenerator.new()
		rng.seed = 92022000 + monster_id
		var rolled: Dictionary = loot.roll_monster_drops(monster_id, rng, true)
		assert(str(rolled.get("reason", "")).is_empty(), str(rolled))
		assert(int(rolled.rng_roll_count) == provider.profile(monster_id).slots.size())
		var armor_attempts := {}
		for attempt: Dictionary in rolled.attempts:
			var source_id := int(attempt.get("canonical_item_id", -1))
			if not output_by_source.has(source_id):
				continue
			var output_id := int(output_by_source[source_id])
			assert(not armor_attempts.has(output_id), "production RNG rolled armor twice: %d/%d" % [monster_id, output_id])
			armor_attempts[output_id] = true
	assert(GameData.dpv2_ground_slot_limit() == 15)
	loot.free()
	print("ARMOR_SINGLE_SLOT_AUTHORITY_PASS monsters=126 slots=6042 affected=37 groups=102 removed=102 frozen_dark_boss=6 production_rng_single_trial=true ground_limit=15")
	get_tree().quit(0)
