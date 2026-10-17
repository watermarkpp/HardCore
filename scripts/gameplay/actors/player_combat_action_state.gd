extends RefCounted

## Original PlayerCharacter accepted-action and struck/cooldown state.
## P-tail accepted release producers are separate from the body action slot:
## an expired animation must not retire an uncommitted accepted release.
const STRUCK_PROTECTION_SECONDS := 0.8

var attack_timer := 0.0
var action_timer := 0.0
var movement_visual_lock_timer := 0.0
var skill_cooldowns: Dictionary = {}
var struck_lock_remaining := 0.0
var struck_reaction_lock_remaining := 0.0
var queued_struck_reaction := false
var struck_protection_remaining := 0.0
var struck_cooldown_pause_remaining := 0.0
var action_sequence := 0
var pending_action_id := 0
var pending_action_active := false
var pending_action_committed := false
var pending_action_epoch := 0
var pending_action_kind := ""
var time_s := 0.0


func is_struck_locked() -> bool:
	return struck_lock_remaining > 0.0 or struck_reaction_lock_remaining > 0.0 or struck_cooldown_pause_remaining > 0.0


func advance_before_reaction(delta: float) -> void:
	time_s += maxf(0.0, delta)
	action_timer = maxf(0.0, action_timer - delta)
	struck_protection_remaining = maxf(0.0, struck_protection_remaining - delta)
	if struck_protection_remaining < 0.000001:
		struck_protection_remaining = 0.0
	movement_visual_lock_timer = maxf(0.0, movement_visual_lock_timer - delta)
	if action_timer <= 0.0 and pending_action_active and pending_action_committed:
		finish_action(pending_action_id)


func queued_reaction_ready() -> bool:
	return action_timer <= 0.0 and not pending_action_active and queued_struck_reaction


## Called after the owner's queued-hit admission/render notification, exactly
## where the original physics function resumed. The first hit interval does
## not retroactively consume cooldown time preceding that boundary.
func advance_cooldowns(delta: float, struck_started_this_tick: bool) -> void:
	var cooldown_delta := delta
	if struck_started_this_tick:
		cooldown_delta = delta
	else:
		var paused_slice := minf(cooldown_delta, struck_cooldown_pause_remaining)
		struck_cooldown_pause_remaining = maxf(0.0, struck_cooldown_pause_remaining - paused_slice)
		cooldown_delta -= paused_slice
	attack_timer = maxf(0.0, attack_timer - cooldown_delta)
	for stable_skill_id: Variant in skill_cooldowns.keys():
		var remaining := maxf(0.0, float(skill_cooldowns.get(stable_skill_id, 0.0)) - cooldown_delta)
		if remaining <= 0.0:
			skill_cooldowns.erase(stable_skill_id)
		else:
			skill_cooldowns[stable_skill_id] = remaining
	struck_lock_remaining = maxf(0.0, struck_lock_remaining - delta)
	struck_reaction_lock_remaining = maxf(0.0, struck_reaction_lock_remaining - delta)
	if struck_lock_remaining < 0.000001:
		struck_lock_remaining = 0.0


func can_start_attack(dead: bool, control_time: float) -> bool:
	return not dead and attack_timer <= 0.0 and action_timer <= 0.0 and struck_lock_remaining <= 0.0 and struck_reaction_lock_remaining <= 0.0 and struck_cooldown_pause_remaining <= 0.0 and control_time <= 0.0


func begin_action(action_kind: String, epoch: int) -> int:
	action_sequence += 1
	pending_action_id = action_sequence
	pending_action_active = true
	pending_action_committed = false
	pending_action_kind = action_kind
	pending_action_epoch = epoch
	return pending_action_id


func commit_action(action_id: int, dead: bool) -> bool:
	if dead or not pending_action_active or action_id != pending_action_id:
		return false
	pending_action_committed = true
	return true


func finish_action(action_id: int) -> void:
	if action_id != pending_action_id:
		return
	pending_action_active = false
	pending_action_kind = ""


func start_struck_reaction(duration: float) -> void:
	struck_reaction_lock_remaining = maxf(struck_reaction_lock_remaining, duration)
	struck_protection_remaining = STRUCK_PROTECTION_SECONDS
	struck_cooldown_pause_remaining = maxf(struck_cooldown_pause_remaining, duration)


func start_queued_struck_reaction(duration: float) -> void:
	queued_struck_reaction = false
	start_struck_reaction(duration)


func action_snapshot() -> Dictionary:
	return {
		"action_id": pending_action_id,
		"kind": pending_action_kind,
		"active": pending_action_active,
		"committed": pending_action_committed,
		"epoch": pending_action_epoch,
	}


func skill_cooldown_remaining_ms(stable_skill_id: String) -> int:
	return ceili(maxf(0.0, float(skill_cooldowns.get(stable_skill_id, 0.0))) * 1000.0)
