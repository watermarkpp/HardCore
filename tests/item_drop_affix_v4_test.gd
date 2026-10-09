extends Node

const Rules := preload("res://scripts/item_drop_instance_rules.gd")
const V3 := preload("res://scripts/item_drop_affix_v3_rules.gd")
const V4 := preload("res://scripts/item_drop_affix_v4_rules.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded())
	assert(Rules.prepare_runtime())
	var targets := 0
	var low := 0
	var real_bonus := 0
	var durability_only := 0
	var plain := 0
	for id: int in Rules._master_by_item_id:
		var catalog := GameData.get_item_rules_record({"item_id": id})
		if V4.targets(id):
			targets += 1
		else:
			low += 1
		for sample in range(8):
			var key := "v4-finite-contract:%d:%d" % [id,sample]
			var created := Rules.create_instance(catalog,key)
			assert(not created.is_empty(),key)
			assert(created == Rules.create_instance(catalog,key),"deterministic new seed")
			var wire: Dictionary = JSON.parse_string(JSON.stringify(created))
			assert(Rules.validate_instance(wire,catalog),"JSON wire retains exact integer values")
			var legacy := _old_v3(catalog,key)
			assert(Rules.validate_instance(legacy,catalog),"old v3 seed stays valid")
			assert(Rules.validate_instance(JSON.parse_string(JSON.stringify(legacy)),catalog))
			if not V4.targets(id):
				assert(created == legacy,"83 non-target IDs preserve full original RNG output")
				continue
			assert(str(created.drop_rules_contract_id) == V4.CONTRACT)
			assert(str(created.drop_affix.contract_id) == V4.AFFIX_CONTRACT)
			assert(str(created.instance_id).begins_with("drop:v4:"))
			var nonzero: bool = not created.modifiers.is_empty()
			assert(Rules.is_affixed_instance(wire,catalog)==nonzero,"JP event must match production predicate; durability-only is not JP")
			if nonzero:
				real_bonus += 1
			elif bool(created.drop_affix.applied):
				durability_only += 1
				assert(int(created.max_durability_raw)>int(catalog.maxDurability)*1000)
			else:
				plain += 1
			var event_rng := RandomNumberGenerator.new()
			event_rng.seed = ("0x" + (V4.AFFIX_CONTRACT+"|"+str(created.drop_key_digest)).sha256_text().substr(0,15)).hex_to_int()
			assert(nonzero==(V4._uniform_tick(event_rng)<int(V4._records[id].runtime_gate_numerator)),"production JP predicate exactly follows target event gate")
			var worn := wire.duplicate(true)
			worn.max_durability_raw -= 1000
			worn.durability_raw = maxi(0,int(worn.max_durability_raw)-1)
			worn.max_durability = int(ceil(int(worn.max_durability_raw)/1000.0))
			worn.durability = int(ceil(int(worn.durability_raw)/1000.0))
			assert(Rules.validate_instance(worn,catalog),"new v4 identity survives ordinary wear and repair")
			var expected := V4.for_seed(id,str(created.drop_key_digest))
			assert(expected == V4.for_seed(id,str(created.drop_key_digest)))
			var row: Dictionary = V4._records[id]
			for modifier: Dictionary in created.modifiers:
				var allowed := false
				for rule: Dictionary in row.rolls:
					if str(rule.stat) != str(modifier.stat):
						continue
					assert(not bool(rule.excluded))
					for outcome: Dictionary in rule.outcomes:
						if int(outcome.value)==int(modifier.value) and int(modifier.value)!=0:
							allowed = true
				assert(allowed,"new law cannot invent stat/value/sign")
			var forged := wire.duplicate(true)
			forged.drop_affix.contract_id = V3.AFFIX_CONTRACT
			assert(not Rules.validate_instance(forged,catalog),"cross-version affix rejected")
			forged = wire.duplicate(true)
			forged.drop_rules_contract_id = V3.CONTRACT
			forged.drop_affix.contract_id = V3.AFFIX_CONTRACT
			assert(not Rules.validate_instance(forged,catalog),"v4 identity cannot be relabelled v3")
			forged = legacy.duplicate(true)
			forged.drop_rules_contract_id = V4.CONTRACT
			forged.drop_affix.contract_id = V4.AFFIX_CONTRACT
			assert(not Rules.validate_instance(forged,catalog),"old saved identity cannot be relabelled v4")
			forged = wire.duplicate(true)
			forged.modifiers.append({"stat":"health_recovery","op":"add","value":1})
			assert(not Rules.validate_instance(forged,catalog),"excluded forged bonus rejected")
			if not wire.modifiers.is_empty():
				forged = wire.duplicate(true)
				forged.modifiers[0].value = str(forged.modifiers[0].value)
				assert(not Rules.validate_instance(forged,catalog),"string bonus value rejected")
			forged = wire.duplicate(true)
			forged.max_durability_raw = 66000
			forged.max_durability = 66
			assert(not Rules.validate_instance(forged,catalog))
		var v1 := Rules.create_legacy_instance(catalog,"v4-compat-v1:%d" % id)
		var v2 := Rules.create_v2_instance(catalog,"v4-compat-v2:%d" % id)
		assert(not v1.is_empty() and not v2.is_empty())
		assert(Rules.validate_instance(JSON.parse_string(JSON.stringify(v1)),catalog))
		assert(Rules.validate_instance(JSON.parse_string(JSON.stringify(v2)),catalog))
	assert(targets==92 and low==83 and real_bonus>0 and durability_only>0 and plain>0)
	print("AFFIX_V4_PASS targets=",targets," legacy_rng_ids=",low," production_jp=",real_bonus," durability_only_non_jp=",durability_only," plain=",plain," create_validate_wire=1400")
	get_tree().quit()


func _old_v3(catalog: Dictionary,key: String) -> Dictionary:
	var instance := Rules.create_legacy_instance(catalog,key)
	assert(not instance.is_empty())
	var expected := V3.for_seed(int(instance.item_id),str(instance.drop_key_digest))
	instance.drop_rules_contract_id = V3.CONTRACT
	instance.modifiers = expected.modifiers
	var maximum := mini(V3.MAXIMUM_DURABILITY_RAW,int(catalog.maxDurability)*1000+int(expected.durability_bonus_raw))
	instance.max_durability_raw = maximum
	instance.durability_raw = maximum
	instance.max_durability = int(ceil(maximum/1000.0))
	instance.durability = instance.max_durability
	instance.drop_affix = {"contract_id":V3.AFFIX_CONTRACT,"applied":not expected.modifiers.is_empty() or int(expected.durability_bonus_raw)>0}
	return instance
