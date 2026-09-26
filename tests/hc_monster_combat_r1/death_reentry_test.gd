extends Node

## HC-MONSTER-COMBAT-R1 Task 7 (F08) counterexample.
## The lethal outcome must be committed atomically BEFORE stats/resources
## notifications run. A synchronous listener that reenters take_damage() while
## the old window (HP already 0, _dead still false) is open used to commit a
## second full death lifecycle: duplicated epoch, duplicated gold loss and a
## second death coroutine. The reentry must be rejected by the death commit
## and the lifecycle effects must happen exactly once.
##
## HC-MONSTER-COMBAT-R2 T5: the listener no longer self-suppresses on
## `not player._dead`. The R1 test checked that flag inside the listener,
## which silently disabled the reentry (stats_changed now emits after the
## death commit, so the guard always short-circuited). The listener now
## reenters unconditionally on the killing-hit notification, exactly like a
## real external proc would; the production guard owns the rejection.


var _reentry_done := false
var _death_requested_count := 0
var _reentry_accepted := false


func _ready() -> void:
	var player := PlayerCharacter.new()
	add_child(player)
	var base_epoch := player.combat_epoch
	player.death_requested.connect(func() -> void: _death_requested_count += 1)
	player.stats_changed.connect(_on_stats_changed_reentry.bind(player))

	player.take_damage(999999)
	assert(
		player.combat_epoch == base_epoch + 1,
		"death must commit its lifecycle exactly once (epoch)"
	)
	assert(
		not _reentry_accepted,
		"the reentrant take_damage must be rejected by the death commit"
	)

	# The deferred death notification is presentation-only; wait for it.
	await get_tree().create_timer(1.0).timeout
	assert(
		_death_requested_count == 1,
		"death_requested must be emitted exactly once per lethal hit"
	)
	assert(player._dead, "the player must stay formally dead")

	# F07 boundary: a formally dead actor accepts no new poison or control
	# state (mirrors the existing apply_monster_poison() guard).
	player.apply_poison(5, 10.0)
	assert(player.poison_time == 0.0 and player.poison_damage == 0, "a dead player must not accept new poison")
	player.apply_control(3.0)
	assert(player.control_time == 0.0, "a dead player must not accept new control")

	player.queue_free()
	print("HC_MCR1_DEATH_REENTRY_PASS")
	get_tree().quit()


func _on_stats_changed_reentry(hp: int, _max_hp: int, player: PlayerCharacter) -> void:
	# Simulates an external listener reacting to the killing hit (for example a
	# UI/equipment proc that deals trailing damage synchronously). HC-MONSTER-
	# COMBAT-R2: no `not player._dead` self-suppression - the listener fires on
	# every notification including the death-commit one, and the production
	# guard must reject the reentry.
	if hp == 0 and not _reentry_done:
		_reentry_done = true
		var epoch_before := player.combat_epoch
		player.take_damage(10)
		_reentry_accepted = player.combat_epoch != epoch_before
