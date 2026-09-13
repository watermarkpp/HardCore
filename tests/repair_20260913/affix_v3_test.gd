extends Node
const Rules := preload("res://scripts/item_drop_instance_rules.gd")

class ControlTarget extends PlayerCharacter:
	var received := 0
	func apply_control(_seconds: float) -> void:
		received += 1


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 60
	var weapon := GameData.get_item_rules_record({"item_id": 80})
	var counts := {"attack_max":0,"magic_max":0,"tao_max":0,"accuracy":0,"weapon_strong":0,"fast":0,"slow":0,"durability":0,"multiple":0,"above_one":0,"affixed":0}
	var durability_sum := 0
	var samples: Dictionary = {}
	# 24k independent deterministic drop identities. Expected marginal rates:
	# primary=1/30, accuracy=1/48, strong=1/20, durability=1/3.
	# Speed also needs Binomial(12,1/15)>=2 and its conditional sign is 1:2.
	for i in range(24000):
		var instance := Rules.create_instance(weapon, "jp-v3-distribution:%d" % i)
		assert(not instance.is_empty(), str(i))
		if bool(instance.drop_affix.applied): counts.affixed += 1
		if instance.modifiers.size() > 1: counts.multiple += 1
		var durability := int(instance.max_durability_raw) - int(weapon.maxDurability) * 1000
		if durability > 0:
			counts.durability += 1
			durability_sum += durability
			assert(durability % 2000 == 0)
		for modifier: Dictionary in instance.modifiers:
			var stat := str(modifier.stat)
			if stat == "attack_speed_tier":
				var sign_key := "fast" if int(modifier.value) > 0 else "slow"
				counts[sign_key] += 1
				if not samples.has(sign_key): samples[sign_key] = instance.duplicate(true)
			else:
				counts[stat] += 1
				if not samples.has(stat): samples[stat] = instance.duplicate(true)
			if int(modifier.value) > 1: counts.above_one += 1
	assert(counts.attack_max > 640 and counts.attack_max < 960, str(counts))
	assert(counts.magic_max > 640 and counts.magic_max < 960)
	assert(counts.tao_max > 640 and counts.tao_max < 960)
	assert(counts.accuracy > 370 and counts.accuracy < 640)
	assert(counts.weapon_strong > 1000 and counts.weapon_strong < 1400)
	assert(counts.durability > 7550 and counts.durability < 8450)
	assert(float(durability_sum) / counts.durability > 3850 and float(durability_sum) / counts.durability < 4150)
	assert(counts.fast > 12 and counts.fast < 80 and counts.slow > 35 and counts.slow < 160, str(counts))
	assert(counts.slow > counts.fast and counts.affixed > 8000 and counts.affixed < 10500)
	assert(counts.multiple > 350 and counts.above_one > 1000)
	# Independent original switch whitelist: slot labels alone cannot select
	# secondary attributes. Unknown/forbidden stats must never enter a roll.
	var secondary := {5:["attack_speed_tier","accuracy","weapon_strong"],10:["defense_max","magic_defense_max"],11:["defense_max","magic_defense_max"],15:["defense_max","magic_defense_max"],19:["anti_magic_points","luck"],20:["accuracy","agility"],21:[],22:[],23:["anti_poison"],24:["accuracy","agility"],26:["defense_max","magic_defense_max"]}
	var whitelist_by_id: Dictionary = {}
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/item_drop_affix_rules_v3.json"))
	for record: Dictionary in data.records:
		var allowed: Array = ["attack_max","magic_max","tao_max","durability_bonus_raw"] + secondary[int(record.original_rule_mode)]
		for rule: Dictionary in record.rolls:
			assert(bool(rule.excluded) == (str(rule.stat) in ["health_recovery","spell_recovery","poison_recovery"]))
			if not rule.excluded: assert(str(rule.stat) in allowed,"forbidden roll on item %d" % int(record.item_id))
		whitelist_by_id[int(record.item_id)] = allowed
	assert(whitelist_by_id.size()==175)
	# Full ID coverage, private JSON roundtrip and durability ceilings. A seeded
	# positive bonus may survive wear/normal repair loss but cannot be enlarged.
	for id: int in Rules._master_by_item_id:
		var catalog := GameData.get_item_rules_record({"item_id":id})
		for index in range(128):
			var item := Rules.create_instance(catalog, "jp-v3-all:%d:%d" % [id,index])
			assert(not item.is_empty())
			var saved: Dictionary = JSON.parse_string(JSON.stringify(item))
			assert(Rules.validate_instance(saved,catalog))
			assert(int(item.max_durability_raw) <= 65000)
			for m: Dictionary in item.modifiers:
				assert(str(m.stat) not in ["health_recovery","spell_recovery","poison_recovery"])
				assert(str(m.stat) in whitelist_by_id[id],"forbidden generated stat on item %d" % id)
			var forged := saved.duplicate(true)
			forged.max_durability_raw = 66000
			forged.max_durability = 66
			assert(not Rules.validate_instance(forged,catalog))
	var signed_sample: Dictionary = samples.slow
	assert(Rules.validate_instance(JSON.parse_string(JSON.stringify(signed_sample)),weapon))
	var malformed := signed_sample.duplicate(true)
	malformed.modifiers[0].value = "-1"
	assert(not Rules.validate_instance(malformed,weapon))
	var worn: Dictionary = samples.weapon_strong.duplicate(true)
	worn.max_durability_raw -= 1000
	worn.durability_raw = worn.max_durability_raw - 1
	worn.max_durability = int(ceil(worn.max_durability_raw / 1000.0))
	worn.durability = int(ceil(worn.durability_raw / 1000.0))
	assert(Rules.validate_instance(worn,weapon), "normal repair and wear keep v3 identity")
	var pair := _equip(samples.weapon_strong, "武器")
	var loss := PlayerState.apply_durability_event(PlayerState.DURABILITY_EVENT_WEAPON_PHYSICAL_HIT, {"confirmed_hit":true,"weapon_roll":4})
	var strong := _value(samples.weapon_strong,"weapon_strong")
	assert(int(loss.weapon_strong) == strong and int(loss.raw_loss) == maxi(0,6-strong), "strong changes actual wear")
	for key: String in ["fast","slow"]:
		pair = _equip(samples[key], "武器")
		var speed := _value(samples[key],"attack_speed_tier")
		assert(int(pair.after.attack_speed_tier) == int(pair.before.attack_speed_tier) + speed)
		var before_ms := CombatResolutionRules.physical_attack_interval_ms(int(pair.before.attack_speed_tier))
		var after_ms := CombatResolutionRules.physical_attack_interval_ms(int(pair.after.attack_speed_tier))
		assert(after_ms == before_ms - speed * 60, "actual combat cadence")
	pair = _equip(samples.accuracy,"武器")
	var accuracy := int(pair.before.accuracy)
	assert(not CombatResolutionRules.physical_hit_succeeds(accuracy,accuracy+10,accuracy))
	assert(CombatResolutionRules.physical_hit_succeeds(int(pair.after.accuracy),accuracy+10,accuracy))
	# A zero-base DC bracelet can get AC; accuracy bracelets get their own lane.
	var defense := _find(184,"defense_max")
	pair = _equip(defense,"左手镯")
	assert(pair.after.defense_max > pair.before.defense_max)
	var agility := _find(181,"agility")
	pair = _equip(agility,"左手镯")
	assert(CombatResolutionRules.physical_hit_probability(1,int(pair.after.agility)) < CombatResolutionRules.physical_hit_probability(1,int(pair.before.agility)))
	var evasion := _find(159,"anti_magic_points")
	pair = _equip(evasion,"项链")
	var roll := int(pair.before.anti_magic_points)
	assert(not CombatResolutionRules.resolve_magic_damage_for_target_stats("wizard.lightning",50,pair.before,roll).magic_evaded)
	assert(CombatResolutionRules.resolve_magic_damage_for_target_stats("wizard.lightning",50,pair.after,roll).damage_after_evasion == 0)
	var lucky := _find(229,"luck")
	pair = _equip(lucky,"项链")
	assert(int(pair.after.luck) == int(pair.before.luck) + _value(lucky,"luck"))
	var base_rng := RandomNumberGenerator.new()
	var lucky_rng := RandomNumberGenerator.new()
	base_rng.seed = 45791
	lucky_rng.seed = 45791
	var base_max := 0
	var lucky_max := 0
	for _i in range(5000):
		if WarriorCombatMath.roll_primary_stat(1,100,int(pair.before.luck),base_rng) == 100: base_max += 1
		if WarriorCombatMath.roll_primary_stat(1,100,int(pair.after.luck),lucky_rng) == 100: lucky_max += 1
	assert(lucky_max > base_max + 250, "luck affects actual attack roll")
	var poison := _find(208,"anti_poison")
	pair = _equip(poison,"左戒指")
	var enemy := EnemyActor.new()
	var target := ControlTarget.new()
	enemy.control_on_hit_seconds = 1.0
	enemy.control_chance_denominator_base = 5
	PlayerState.computed_stats = pair.before
	enemy._rng.seed = 89321
	for _i in range(10000): enemy._apply_on_hit_control(target)
	var ordinary_controls := target.received
	target.received = 0
	PlayerState.computed_stats = pair.after
	enemy._rng.seed = 89321
	for _i in range(10000): enemy._apply_on_hit_control(target)
	assert(target.received < ordinary_controls - 180, "original anti-poison affects real monster control gate")
	enemy.free()
	target.free()
	for instance: Dictionary in [evasion,poison,samples.weapon_strong,samples.slow]:
		var text := ItemDetailPresenter.format_item(GameData.get_item_rules_record(instance),instance)
		assert(not text.contains("anti_") and not text.contains("weapon_strong") and not text.contains("attack_speed"))
	assert(ItemDetailPresenter.format_item(GameData.get_item_rules_record(evasion),evasion).contains("魔法躲避 +%d%%" % (_value(evasion,"anti_magic_points")*10)))
	print("AFFIX_V3_PASS ",JSON.stringify(counts)," control_base=",ordinary_controls," luck_max=",lucky_max)
	get_tree().quit()


func _value(instance: Dictionary, stat: String) -> int:
	for m: Dictionary in instance.modifiers:
		if str(m.stat) == stat: return int(m.value)
	return 0


func _find(item_id: int, stat: String) -> Dictionary:
	var item := GameData.get_item_rules_record({"item_id":item_id})
	for i in range(10000):
		var instance := Rules.create_instance(item,"jp-v3-behavior:%d:%d" % [item_id,i])
		if _value(instance,stat) > 0: return instance
	assert(false,"no deterministic sample for %d:%s" % [item_id,stat])
	return {}


func _equip(instance: Dictionary, slot: String) -> Dictionary:
	for key: String in PlayerState.equipment: PlayerState.equipment[key] = {}
	var item := GameData.get_item_rules_record(instance)
	PlayerState.equipment[slot] = PlayerState._make_item_instance(str(item.name),item,99200)
	PlayerState.recalculate_stats(false)
	var before := PlayerState.computed_stats.duplicate(true)
	PlayerState.equipment[slot] = instance.duplicate(true)
	PlayerState.recalculate_stats(false)
	return {"before":before,"after":PlayerState.computed_stats.duplicate(true)}
