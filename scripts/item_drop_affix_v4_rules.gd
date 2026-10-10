class_name ItemDropAffixV4Rules
extends RefCounted

## New rolls only. Frozen v3 seeds and saved equipment retain their original law.
const Legacy := preload("res://scripts/item_drop_affix_v3_rules.gd")
const PATH := "res://assets/data/item_drop_affix_wooma_jp_policy.runtime.json"
const CONTRACT := "item.drop.affix.rules.v4"
const AFFIX_CONTRACT := "item.drop.affix.v4"
const TICK_COUNT := 9007199254740992
static var _records: Dictionary = {}
static var _expected: Dictionary = {}


static func ensure_loaded(master_ids: Array) -> bool:
	if not _records.is_empty():
		return true
	if not Legacy.ensure_loaded(master_ids):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if (not data is Dictionary or str(data.get("contract_id", "")) != CONTRACT
		or str(data.get("affix_contract_id", "")) != AFFIX_CONTRACT
		or int(data.get("runtime_denominator", 0)) != TICK_COUNT
		or int(data.get("record_count", 0)) != 92):
		return false
	var records: Dictionary = {}
	for raw_record: Variant in data.get("records", []):
		if not raw_record is Dictionary:
			return false
		var record: Dictionary = raw_record
		var id := int(record.get("canonical_item_id", -1))
		var gate := int(record.get("runtime_gate_numerator", -1))
		var no_jp_outer_gate := int(record.get("no_jp_outer_pass_gate_numerator", -1))
		if (id not in master_ids or records.has(id) or gate < 0 or gate > TICK_COUNT
			or no_jp_outer_gate < 0 or no_jp_outer_gate > TICK_COUNT
			or int(record.get("runtime_gate_denominator", 0)) != TICK_COUNT
			or not record.get("rolls") is Array):
			return false
		var original: Array = Legacy._records[id]
		if record.rolls.size() != original.size():
			return false
		for index in range(original.size()):
			var rule: Dictionary = record.rolls[index]
			if (str(rule.get("stat", "")) != str(original[index].stat)
				or bool(rule.get("excluded", false)) != bool(original[index].excluded)
				or bool(rule.get("event_eligible", false)) != (not bool(original[index].excluded) and str(original[index].stat) != "durability_bonus_raw")
				or not rule.get("outcomes") is Array or rule.outcomes.is_empty()):
				return false
			var previous := 0
			var previous_conditioned := 0
			for raw_outcome: Variant in rule.outcomes:
				if not raw_outcome is Dictionary:
					return false
				var outcome: Dictionary = raw_outcome
				var cdf := int(outcome.get("cdf_tick", -1))
				var conditioned := int(outcome.get("prefix_zero_cdf_tick", -1))
				if (cdf < previous or cdf > TICK_COUNT or conditioned < previous_conditioned
					or conditioned > TICK_COUNT or (bool(rule.excluded) and int(outcome.get("value", -1)) != 0)):
					return false
				previous = cdf
				previous_conditioned = conditioned
			if previous != TICK_COUNT or previous_conditioned != TICK_COUNT:
				return false
		records[id] = record
	if records.size() != 92:
		return false
	_records = records
	return true


static func targets(item_id: int) -> bool:
	return _records.has(item_id)


static func _uniform_tick(rng: RandomNumberGenerator) -> int:
	# Both bounds fit signed int32; their composition fits exact JSON/binary64.
	return rng.randi_range(0, 67108863) * 134217728 + rng.randi_range(0, 134217727)


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
	var record: Dictionary = _records[item_id]
	var jp_event := _uniform_tick(rng) < int(record.runtime_gate_numerator)
	# Original v3 | no JP is an outer-failure zero result mixed with outer-pass,
	# all modifiers zero, ordinary independent durability. It must survive too.
	# With Z=P(inner modifiers all zero), outer-pass | no JP is Z/(1+Z).
	# Increasing JP shrinks the no-JP branch, preserving its conditional law;
	# durability-only remains valid drop_affix.applied=true, but never counts as JP.
	var no_jp_outer_pass := false
	if not jp_event:
		no_jp_outer_pass = _uniform_tick(rng) < int(record.no_jp_outer_pass_gate_numerator)
	if jp_event or no_jp_outer_pass:
		var prefix_zero := true
		for rule: Dictionary in record.rolls:
			if not jp_event and bool(rule.event_eligible):
				continue
			var tick := _uniform_tick(rng)
			var value := 0
			var field := "prefix_zero_cdf_tick" if jp_event and prefix_zero else "cdf_tick"
			for outcome: Dictionary in rule.outcomes:
				if tick < int(outcome[field]):
					value = int(outcome.value)
					break
			if value == 0:
				continue
			if bool(rule.event_eligible):
				prefix_zero = false
			if str(rule.stat) == "durability_bonus_raw":
				durability = value
			else:
				var modifier := {"stat": str(rule.stat), "op": "add", "value": value}
				modifier.make_read_only()
				modifiers.append(modifier)
		# Final eligible modifier has zero probability of remaining all-zero.
		if jp_event and prefix_zero:
			return {}
	modifiers.make_read_only()
	var result := {"modifiers": modifiers, "durability_bonus_raw": durability}
	result.make_read_only()
	if _expected.size() >= 4096:
		_expected.clear()
	_expected[key] = result
	return result
