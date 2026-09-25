extends Node

## HC-MONSTER-COMBAT-R1 Task 7 (F06) counterexample.
## The resolved-damage entry must reject non-positive amounts: negative values
## must never heal through a damage path, and zero must not create threat,
## wake maintenance or struck work. Legal positive damage stays untouched.


func _ready() -> void:
	var player := PlayerCharacter.new()
	add_child(player)
	var enemy := EnemyActor.new()
	enemy.max_hp = 100
	enemy.current_hp = 100
	add_child(enemy)

	# Zero damage: no HP change and no aggro from a non-hit.
	var hp_before := enemy.current_hp
	enemy.take_damage(0, player)
	assert(enemy.current_hp == hp_before, "zero damage must not change HP")
	assert(enemy._threat_for(player) == 0.0, "zero damage must not create threat")

	# Negative damage: never a disguised heal and never aggro.
	enemy.take_damage(-5, player)
	assert(
		enemy.current_hp == hp_before,
		"negative damage must not heal through the damage path"
	)
	assert(enemy._threat_for(player) == 0.0, "negative damage must not create threat")

	# The ordinary positive path keeps working end to end.
	enemy.take_damage(30, player)
	assert(enemy.current_hp == hp_before - 30, "positive damage must still apply")
	assert(enemy._threat_for(player) > 0.0, "positive damage must still build threat")

	enemy.queue_free()
	player.queue_free()
	print("HC_MCR1_DAMAGE_BOUNDARY_PASS")
	get_tree().quit()
