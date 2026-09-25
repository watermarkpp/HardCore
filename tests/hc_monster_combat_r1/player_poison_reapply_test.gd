extends Node

## HC-MONSTER-COMBAT-R1 Task 1 (F05) counterexample.
## After the old player poison channel expires naturally, a newly applied
## weaker poison must use its own strength; expired strength must not leak
## into the new cycle. Invalid input is rejected, not floored into a poison.


func _ready() -> void:
	var player := PlayerCharacter.new()
	# Expired strong poison left its strength behind (the residual state).
	player.poison_time = 0.0
	player.poison_damage = 12
	player.apply_poison(3, 10.0)
	assert(
		player.poison_damage == 3,
		"A new poison cycle after expiry must use its own strength"
	)
	assert(is_equal_approx(player.poison_time, 10.0))
	# While active, a stronger refresh upgrades; a weaker one must not downgrade.
	player.apply_poison(7, 12.0)
	assert(player.poison_damage == 7, "An active stronger refresh must upgrade the strength")
	player.apply_poison(4, 13.0)
	assert(player.poison_damage == 7, "An active weaker refresh must not downgrade the strength")
	assert(is_equal_approx(player.poison_time, 13.0))
	# Non-positive input is rejected instead of becoming a valid poison.
	player.poison_time = 0.0
	player.poison_damage = 5
	player.apply_poison(0, 6.0)
	assert(
		player.poison_damage == 5 and is_equal_approx(player.poison_time, 0.0),
		"Non-positive poison input must be rejected"
	)
	player.apply_poison(3, -1.0)
	assert(
		is_equal_approx(player.poison_time, 0.0),
		"Non-positive poison duration must be rejected"
	)
	player.free()
	print("HC_MCR1_PLAYER_POISON_REAPPLY_PASS")
	get_tree().quit()
