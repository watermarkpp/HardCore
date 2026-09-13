extends Node
const Service := preload("res://scripts/layers/runtime/loot_runtime_service.gd")

func _ready() -> void:
	assert(GameData.ensure_loaded())
	var service := Service.new()
	assert(service._user_balance.valid)
	var count := 0
	for uid: String in service._user_balance.records:
		var row: Dictionary = service._user_balance.records[uid]
		var actual := service._production_probability(int(row.monster_id), uid)
		assert(actual.ok, str(actual))
		assert(actual.final_numerator == int(row.after[0]) and actual.final_denominator == int(row.after[1]), uid)
		count += 1
	assert(count == 782)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8080
	for mid in [79,81,83,85,87,158,159,76,198,199,225,18]:
		var audited := service.roll_monster_drops(mid,rng,true)
		assert(audited.reason.is_empty(), "%d %s" % [mid,audited.reason])
		assert(audited.all_resolved_slots_rng)
		assert(audited.ground_output_count <= 15)
		if mid == 159:
			assert(audited.source_entry_count == GameData.dpv2_direct_profile(159).slots.size() + 17)
		var state := rng.state
		var next_audit := service.roll_monster_drops(mid,rng,true)
		rng.state = state
		var lean := service.roll_monster_drops(mid,rng,false)
		assert(lean.items == next_audit.items and lean.gold_drops == next_audit.gold_drops)
		assert(lean.successful_roll_count == next_audit.successful_roll_count)
	# An unmodified ordinary equipment probability still receives its old /3 policy.
	for slot: Dictionary in GameData.dpv2_direct_profile(18).slots:
		var uid := str(slot.slot_uid)
		assert(not service._user_balance.records.has(uid))
		assert(service._production_probability(18,uid) == service._apply_drop_probability_policy(GameData.dpv2_effective_slot_probability(18,uid),"ordinary"))
	service.free()
	print("DROP_BALANCE_V80_PASS: 782 exact rows, 17 copied slots, real rolls, audited/lean parity, unchanged ordinary policy")
	get_tree().quit(0)
