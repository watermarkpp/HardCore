extends Node

## HC-MONSTER-COMBAT-R2 T4 player-chain verification (R2-09 coverage for the
## Sol package Task 5/6 behaviour):
##   1. dual-struck: a hit that lands while a committed combat action is
##      active must QUEUE its reaction, play it exactly once when the action
##      finishes, and never stack a second reaction while one is playing;
##   2. poison natural expiry: a legacy poison lane expires by its own
##      duration - the channel clears (no damage tick on the expiry frame)
##      and a later reapplication starts a clean full-duration channel.


func _drive(player: PlayerCharacter, seconds: float, fps := 30.0) -> void:
	var step := 1.0 / fps
	var ticks := int(ceil(seconds * fps))
	for _i in ticks:
		player._physics_process(step)


func _ready() -> void:
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.defense_min = 0
	player.defense_max = 0
	player.defense_buff = 0

	# --- 1. Dual-struck queue through a committed combat action ---
	player._pending_combat_action_active = true
	player._pending_combat_action_committed = true
	player._pending_combat_action_id = 1
	player._attack_action_timer = 0.5

	player.take_damage(5, true, {}, true)
	assert(
		player._queued_struck_reaction,
		"the first hit during an active action must queue its reaction"
	)
	assert(
		player._struck_reaction_lock_remaining == 0.0,
		"no reaction may start while the action owns the body"
	)
	var hp_after_first := player.current_hp

	# The second hit during the same action neither queues twice nor starts.
	player.take_damage(5, true, {}, true)
	assert(
		player._queued_struck_reaction,
		"the second hit keeps a single queued reaction"
	)
	assert(
		player._struck_reaction_lock_remaining == 0.0,
		"still no immediate reaction while the action owns the body"
	)

	# The action finishes; the queued reaction plays exactly once.
	player._pending_combat_action_active = false
	player._attack_action_timer = 0.0
	player._physics_process(0.016)
	assert(
		not player._queued_struck_reaction,
		"the queued reaction must be consumed exactly once"
	)
	assert(
		player._struck_reaction_lock_remaining > 0.0,
		"the queued reaction must start its reaction lock"
	)
	var lock_value: float = player._struck_reaction_lock_remaining
	player._physics_process(0.016)
	assert(
		player._struck_reaction_lock_remaining < lock_value,
		"the reaction lock decays naturally without restarting"
	)

	# Immediate (non-queued) reaction with no active action.
	player.take_damage(5, true, {}, true)
	assert(
		player._struck_reaction_lock_remaining >= lock_value - 2 * 0.016,
		"a hit with no active action starts its reaction immediately"
	)
	assert(
		not player._queued_struck_reaction,
		"an immediate reaction never queues"
	)

	# --- 2. Poison natural expiry and clean reapplication ---
	# Restore the body first: the struck-reaction hits above legitimately
	# lowered HP, and the multi-tick poison lane below must run its full
	# natural duration without pushing this fixture through the death
	# boundary (death clears the poison lanes by design).
	player.max_hp = 200
	player.current_hp = 200
	var hp_before_poison := player.current_hp
	player.apply_poison(5, 0.25)
	assert(
		player.poison_time > 0.0 and player.poison_damage == 5,
		"fixture: the short poison lane is applied"
	)
	_drive(player, 0.5)
	assert(
		player.poison_time == 0.0,
		"the poison lane must expire naturally by its own duration"
	)
	assert(
		player.poison_damage == 0,
		"natural expiry must clear the channel (no lingering damage field)"
	)
	assert(
		player.current_hp == hp_before_poison,
		"a sub-second poison must not tick any damage before it expires"
	)

	# Reapplication after natural expiry starts a clean full-duration lane.
	player.apply_poison(4, 8.0)
	assert(
		is_equal_approx(player.poison_time, 8.0) and player.poison_damage == 4,
		"reapplication after natural expiry owns a fresh full duration"
	)

	# Drive the 8 s lane to its own natural expiry: 7 second-boundary ticks
	# (ceil 8->7 ... 2->1; the final 1->0 crossing is the expiry cleanup, not
	# a tick), then a clean channel.
	var hp_before_lane := player.current_hp
	_drive(player, 8.2)
	assert(
		player.poison_time == 0.0 and player.poison_damage == 0,
		"the 8 s lane expires naturally into a clean channel"
	)
	assert(
		player.current_hp == hp_before_lane - 4 * 7,
		"the 8 s lane ticks exactly once per second boundary (hp delta %d)"
			% (hp_before_lane - player.current_hp)
	)

	# A fresh 1.2 s lane on the clean channel: exactly one tick (ceil 2->1).
	var hp_before_tick := player.current_hp
	player.apply_poison(5, 1.2)
	_drive(player, 1.2)
	assert(
		player.current_hp == hp_before_tick - 5,
		"exactly one poison tick lands across the single second boundary"
	)
	assert(
		player.poison_time == 0.0 and player.poison_damage == 0,
		"the 1.2 s lane also ends in a clean natural expiry"
	)

	player.queue_free()
	print("HC_MCR2_PLAYER_STRUCK_POISON_CHAIN_PASS")
	get_tree().quit()
