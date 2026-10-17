extends RefCounted

## Numeric summon state, with the original growth and support-buff rules.
## This owner directly accesses no scene, actor identity, clock or autoload.
## The caller owns the two read-only rule ports. Legacy scripts still have
## lazy static content caches; S must use the content owner's frozen ports.
signal passive_wakeup_changed()

const STEALTH_STATE_CONTRACT_ID := "skills.summon_actor.stealth_state.v1"
const BUFF_STATE_CONTRACT_ID := "skills.summon_actor.buff_state.v1"

var summon_rules: Object
var rank_rules: Object

var summon_id := "skeleton"
var skill_level := 0
var effective_skill_rank := 0
var divine_damage_more := 1.0
var summon_exp_level := 0
var maximum_pet_level := 1
var pet_growth_exp := 0
var max_hp := 80
var current_hp := 80
var attack_min := 3
var attack_max := 6
var ac_min := 0
var ac_max := 0
var mac_min := 0
var mac_max := 0
var accuracy := 1
var agility := 1
var name_color_index := 255
var attack_interval := 1.25
var move_speed_gu_per_sec := 0.0
var stealth_remaining_seconds := 0.0
var stealth_buff_id := ""
var ac_buff_bonus := 0
var ac_buff_remaining_seconds := 0.0
var ac_buff_id := ""
var mac_buff_bonus := 0
var mac_buff_remaining_seconds := 0.0
var mac_buff_id := ""


func _init(p_summon_rules: Object, p_rank_rules: Object, initial_move_speed_gu_per_sec: float) -> void:
	summon_rules = p_summon_rules
	rank_rules = p_rank_rules
	assert(summon_rules != null and rank_rules != null)
	move_speed_gu_per_sec = initial_move_speed_gu_per_sec


func synchronize_skill_rank(rank: int) -> bool:
	var new_rank := maxi(skill_level, rank_rules.formula_rank(rank))
	var resolved_effective := maxi(new_rank, summon_rules.clamp_skill_level(rank))
	var changed_more := resolved_effective != effective_skill_rank
	effective_skill_rank = resolved_effective
	divine_damage_more = rank_rules.more_multiplier(effective_skill_rank) if summon_id == "divine_beast" else 1.0
	var new_cap := maxi(maximum_pet_level, summon_rules.maximum_summon_pet_level(new_rank))
	if new_rank == skill_level and new_cap == maximum_pet_level and not changed_more:
		return false
	skill_level = new_rank
	maximum_pet_level = new_cap
	attack_interval = float(summon_rules.effective_summon_attack_interval_ms(
		summon_id, new_rank
	)) / 1000.0
	move_speed_gu_per_sec = 1000.0 / float(maxi(1,
		summon_rules.effective_summon_move_interval_ms(summon_id, new_rank)
	))
	return true


func gain_growth_from_kill(killed_monster_level: int) -> bool:
	if summon_exp_level >= maximum_pet_level:
		return false
	pet_growth_exp += summon_rules.summon_kill_growth_credit(killed_monster_level)
	var threshold: int = summon_rules.summon_growth_threshold(
		summon_id, summon_exp_level
	)
	if pet_growth_exp <= threshold:
		return false
	pet_growth_exp -= threshold
	summon_exp_level = mini(maximum_pet_level, summon_exp_level + 1)
	apply_growth_stats_preserving_current_hp()
	return true


func growth_contract_snapshot() -> Dictionary:
	return {
		"contract_id": summon_rules.summon_baseline_contract_id(),
		"summon_id": summon_id,
		"skill_rank": skill_level,
		"pet_level": summon_exp_level,
		"maximum_pet_level": maximum_pet_level,
		"growth_exp": pet_growth_exp,
		"growth_policy_id": summon_rules.SUMMON_GROWTH_POLICY_ID,
		"kill_growth_multiplier": summon_rules.SUMMON_KILL_GROWTH_MULTIPLIER,
		"next_threshold": summon_rules.summon_growth_threshold(
			summon_id, summon_exp_level
		),
		"name_color_index": name_color_index,
		"persistence": "transient_non_permanent_pet",
	}


func apply_growth_stats_preserving_current_hp() -> void:
	var absolute_hp_before := current_hp
	var stats: Dictionary = summon_rules.summon_stats(summon_id, summon_exp_level)
	max_hp = int(stats.get("max_hp", max_hp))
	attack_min = int(stats.get("dc_min", attack_min))
	attack_max = int(stats.get("dc_max", attack_max))
	ac_min = int(stats.get("ac_min", ac_min))
	ac_max = int(stats.get("ac_max", ac_max))
	mac_min = int(stats.get("mac_min", mac_min))
	mac_max = int(stats.get("mac_max", mac_max))
	accuracy = int(stats.get("accuracy", accuracy))
	agility = int(stats.get("agility", agility))
	current_hp = mini(absolute_hp_before, max_hp)
	name_color_index = summon_rules.summon_name_color_index(summon_exp_level)


func apply_stealth(seconds: float, buff_id := "buff.taoist.mass_invisibility") -> void:
	## Refresh semantics: keep the longer remaining duration, mirroring the
	## player stealth contract (player.apply_stealth uses max).
	if seconds <= 0.0:
		return
	var was_hidden := is_stealthed()
	stealth_remaining_seconds = maxf(stealth_remaining_seconds, seconds)
	if not buff_id.is_empty():
		stealth_buff_id = buff_id
	if not was_hidden:
		passive_wakeup_changed.emit()


func is_stealthed() -> bool:
	return stealth_remaining_seconds > 0.0


func stealth_remaining() -> float:
	return stealth_remaining_seconds


func apply_ac_buff(bonus: int, seconds: float, buff_id := "") -> void:
	if seconds <= 0.0:
		return
	## Reliable refresh: a weaker or shorter refresh never downgrades an
	## active buff. A fresh cast after expiry starts from the new value.
	var safe_bonus := maxi(0, bonus)
	if ac_buff_remaining_seconds <= 0.0:
		ac_buff_bonus = safe_bonus
	else:
		ac_buff_bonus = maxi(ac_buff_bonus, safe_bonus)
	ac_buff_remaining_seconds = maxf(ac_buff_remaining_seconds, seconds)
	if not buff_id.is_empty():
		ac_buff_id = buff_id


func apply_mac_buff(bonus: int, seconds: float, buff_id := "") -> void:
	if seconds <= 0.0:
		return
	var safe_bonus := maxi(0, bonus)
	if mac_buff_remaining_seconds <= 0.0:
		mac_buff_bonus = safe_bonus
	else:
		mac_buff_bonus = maxi(mac_buff_bonus, safe_bonus)
	mac_buff_remaining_seconds = maxf(mac_buff_remaining_seconds, seconds)
	if not buff_id.is_empty():
		mac_buff_id = buff_id


func physical_defence_bonus() -> int:
	return ac_buff_bonus if ac_buff_remaining_seconds > 0.0 else 0


func magic_defence_bonus() -> int:
	return mac_buff_bonus if mac_buff_remaining_seconds > 0.0 else 0


func clear_ac_buff() -> void:
	ac_buff_bonus = 0
	ac_buff_remaining_seconds = 0.0
	ac_buff_id = ""


func clear_mac_buff() -> void:
	mac_buff_bonus = 0
	mac_buff_remaining_seconds = 0.0
	mac_buff_id = ""


func buff_state_snapshot() -> Dictionary:
	return {
		"contract_id": BUFF_STATE_CONTRACT_ID,
		"stealth_contract_id": STEALTH_STATE_CONTRACT_ID,
		"stealth_remaining_seconds": stealth_remaining_seconds,
		"stealth_buff_id": stealth_buff_id,
		"is_stealthed": is_stealthed(),
		"physical_defence": {
			"bonus": physical_defence_bonus(),
			"remaining_seconds": ac_buff_remaining_seconds,
			"buff_id": ac_buff_id,
		},
		"magic_defence": {
			"bonus": magic_defence_bonus(),
			"remaining_seconds": mac_buff_remaining_seconds,
			"buff_id": mac_buff_id,
		},
	}


func update_support_buff_timers(delta: float) -> void:
	if stealth_remaining_seconds > 0.0:
		stealth_remaining_seconds = maxf(0.0, stealth_remaining_seconds - delta)
		if stealth_remaining_seconds <= 0.0:
			stealth_buff_id = ""
			passive_wakeup_changed.emit()
	if ac_buff_remaining_seconds > 0.0:
		ac_buff_remaining_seconds = maxf(0.0, ac_buff_remaining_seconds - delta)
		if ac_buff_remaining_seconds <= 0.0:
			clear_ac_buff()
	if mac_buff_remaining_seconds > 0.0:
		mac_buff_remaining_seconds = maxf(0.0, mac_buff_remaining_seconds - delta)
		if mac_buff_remaining_seconds <= 0.0:
			clear_mac_buff()
