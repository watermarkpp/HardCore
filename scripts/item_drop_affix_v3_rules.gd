class_name ItemDropAffixV3Rules
extends RefCounted

const PATH := "res://assets/data/item_drop_affix_rules_v3.json"
const CONTRACT := "item.drop.affix.rules.v3"
const AFFIX_CONTRACT := "item.drop.affix.v3"
const MAXIMUM_DURABILITY_RAW := 65000
static var _records: Dictionary = {}
static var _expected: Dictionary = {}


static func ensure_loaded(master_ids: Array) -> bool:
	if not _records.is_empty():
		return true
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary or str(data.get("contract_id", "")) != CONTRACT:
		return false
	if (int(data.get("record_count", 0)) != master_ids.size()
		or int(data.get("single_player_outer_gate", {}).get("numerator", 0)) != 1
		or int(data.get("single_player_outer_gate", {}).get("denominator", 0)) != 2
		or int(data.get("maximum_durability_raw", 0)) != MAXIMUM_DURABILITY_RAW):
		return false
	var records: Dictionary = {}
	for record: Dictionary in data.get("records", []):
		var id := int(record.get("item_id", -1))
		if id not in master_ids or records.has(id) or not record.get("rolls") is Array:
			return false
		for rule: Dictionary in record.rolls:
			if (int(rule.get("trials", 0)) not in [6, 12]
				or int(rule.get("trial_denominator", 0)) <= 0
				or int(rule.get("gate_denominator", 0)) <= 0
				or int(rule.get("gate_accept_count", 0)) <= 0
				or int(rule.get("gate_accept_count", 0)) > int(rule.gate_denominator)
				or int(rule.get("divisor", 0)) <= 0):
				return false
		records[id] = record.rolls
	if records.size() != master_ids.size():
		return false
	_records = records
	return true


static func for_seed(item_id: int, digest: String) -> Dictionary:
	if not _records.has(item_id):
		return {}
	var key := "%d:%s" % [item_id, digest]
	if _expected.has(key):
		return _expected[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = ("0x" + (AFFIX_CONTRACT + "|" + digest).sha256_text().substr(0, 15)).hex_to_int()
	var modifiers: Array = []
	var durability := 0
	if rng.randi_range(0, 1) == 0:
		for rule: Dictionary in _records[item_id]:
			var successes := 0
			for trial in range(int(rule.trials)):
				if rng.randi_range(0, int(rule.trial_denominator) - 1) == 0:
					successes += 1
			if rng.randi_range(0, int(rule.gate_denominator) - 1) >= int(rule.gate_accept_count):
				continue
			var value := int((successes + int(rule.add_before_division)) / int(rule.divisor)) + int(rule.add_after_division)
			value *= int(rule.scale)
			if value == 0:
				continue
			# Original btValue[6] <=10 slows (2/3); >10 speeds up (1/3).
			# The sign draw exists only after a nonzero speed result.
			if bool(rule.original_speed_sign) and rng.randi_range(0, 2) != 0:
				value = -value
			# Preserve original draw ordering while omitting the three recovery
			# attributes explicitly excluded by the user's version decision.
			if bool(rule.excluded):
				continue
			if str(rule.stat) == "durability_bonus_raw":
				durability = value
			else:
				var modifier := {"stat": str(rule.stat), "op": "add", "value": value}
				modifier.make_read_only()
				modifiers.append(modifier)
	modifiers.make_read_only()
	var result := {"modifiers": modifiers, "durability_bonus_raw": durability}
	result.make_read_only()
	if _expected.size() >= 4096:
		_expected.clear()
	_expected[key] = result
	return result
