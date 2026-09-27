extends Node

const EquipmentRulesScript := preload("res://scripts/equipment_rules.gd")


## HC-MONSTER-COMBAT-R2 T5 counterexample (R2-01).
## The lethal physical hit that triggers the automatic revival must still owe
## exactly one incoming-struck durability event: the revival ring loses its
## revival charge once AND the struck durability applies once. The R1 build
## returned from the revival branch before the durability block, silently
## skipping the struck durability on the lethal hit.
##
## Deterministic harness: only the revival ring is equipped, and the caller
## supplies durability_context slot_rolls that force the ring slot roll to 0
## (the event then damages the ring by the armor-roll loss) with a pinned
## armor_roll, so the expected ring durability delta is exact.


func _equip_only_revival_ring() -> Dictionary:
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.gold = 1000
	PlayerState.test_mode = true
	PlayerState.recalculate_stats()
	PlayerState.add_item("复活戒指")
	assert(
		PlayerState.equip_inventory_index(_inventory_index("复活戒指")).begins_with("已装备"),
		"复活戒指穿戴失败"
	)
	var ring: Dictionary = PlayerState.equipment["左戒指"]
	assert(
		PlayerState.has_special_effect("revival"),
		"fixture: the equipped revival ring must register the revival effect"
	)
	return ring


func _inventory_index(item_name: String) -> int:
	for index: int in PlayerState.inventory.size():
		if str(PlayerState.inventory[index].get("name", "")) == item_name:
			return index
	return -1


func _ready() -> void:
	var player := PlayerCharacter.new()
	add_child(player)
	var ring := _equip_only_revival_ring()
	var durability_before := int(ring.get("durability", 0))
	assert(durability_before == 5, "fixture: the revival ring fixture must start at 5 durability")

	# One lethal physical hit with a durability context that pins the rolls:
	# armor_roll=0 -> incoming loss 5, and the ring slot roll forced to 0 so
	# the ring itself takes that loss (no armor equipped, so the armor branch
	# no-ops). Raw durability arithmetic (1 display point = 1000 raw units):
	# revival charge -1000, struck event -5. The R1 regression (early return
	# before the durability block) leaves 4000 instead of 3995. The display
	# point is too coarse (ceil) to discriminate; the raw field is exact.
	var durability_context := {
		"armor_roll": 0,
		"slot_rolls": {"左戒指": 0},
	}
	player.take_damage(999999, true, durability_context)

	assert(
		player.current_hp == player.max_hp and not player._dead,
		"the automatic revival must restore the player in place"
	)
	var durability_raw_after := int(ring.get("durability_raw", 0))
	assert(
		durability_raw_after == 5 * 1000 - 1000 - 5,
		(
			"the lethal hit must consume the revival charge once (1000 raw) AND "
			+ "apply the struck durability once (5 raw); ring raw durability "
			+ "%d (a skipped struck event leaves 4000)"
		)
			% durability_raw_after
	)

	# The revived actor must be a clean combat state, not half-dead.
	assert(player.poison_time == 0.0 and player.poison_damage == 0, "revival must not inherit poison")
	assert(not player.combat_transition_is_active(), "revival must not leave a combat transition active")

	player.queue_free()
	print("HC_MCR2_REVIVAL_DURABILITY_PASS")
	get_tree().quit()
