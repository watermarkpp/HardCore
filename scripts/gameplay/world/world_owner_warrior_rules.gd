extends RefCounted
## Borrowed view of the SAME original rule/model authority. No state copy.
const Source := preload("res://scripts/warrior_combat_math.gd")
var _owner := OS.get_thread_caller_id()
func owner_thread_id() -> int: return _owner
func _get(field: StringName) -> Variant:
	var script: Script = Source
	return script.get_script_constant_map().get(String(field), script.get(field))

func clamp_skill_level(level_value: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.clamp_skill_level(level_value)

func basic_sword_accuracy_bonus(level_value: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.basic_sword_accuracy_bonus(level_value)

func slaying_accuracy_bonus(level_value: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.slaying_accuracy_bonus(level_value)

func total_accuracy(item_accuracy: int, basic_level := -1, slaying_level := -1) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.total_accuracy(item_accuracy, basic_level, slaying_level)

func hit_succeeds(accuracy: int, target_agility: int, random_roll: int) -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.hit_succeeds(accuracy, target_agility, random_roll)

func hit_probability(accuracy: int, target_agility: int) -> float:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.hit_probability(accuracy, target_agility)

func roll_hit(accuracy: int, target_agility: int, rng: RandomNumberGenerator) -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.roll_hit(accuracy, target_agility, rng)

func physical_attack_interval_ms(attack_speed_tier: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.physical_attack_interval_ms(attack_speed_tier)

func physical_attack_interval_seconds(attack_speed_tier: int) -> float:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.physical_attack_interval_seconds(attack_speed_tier)

func attack_power_for_roll(attack_min: int, attack_max: int, roll: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.attack_power_for_roll(attack_min, attack_max, roll)

func roll_primary_stat(stat_min: int, stat_max: int, total_luck: int, rng: RandomNumberGenerator) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.roll_primary_stat(stat_min, stat_max, total_luck, rng)

func roll_attack_power(attack_min: int, attack_max: int, total_luck: int, rng: RandomNumberGenerator) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.roll_attack_power(attack_min, attack_max, total_luck, rng)

func slaying_proc_cycle(level_value: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.slaying_proc_cycle(level_value)

func slaying_proc_probability(level_value: int) -> float:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.slaying_proc_probability(level_value)

func slaying_flat_damage_bonus(level_value: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.slaying_flat_damage_bonus(level_value)

func slaying_damage(base_damage: int, level_value: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.slaying_damage(base_damage, level_value)

func thrust_secondary_damage(base_damage: int, level_value: int, sword_long_rate := Source.SWORD_LONG_POWER_RATE) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.thrust_secondary_damage(base_damage, level_value, sword_long_rate)

func thrust_segment_ignores_ac(segment: int) -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.thrust_segment_ignores_ac(segment)

func resolve_enemy_physical_damage(raw_damage: int, target_defense: int, ignore_ac := false) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.resolve_enemy_physical_damage(raw_damage, target_defense, ignore_ac)

func half_moon_secondary_damage(base_damage: int, level_value: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.half_moon_secondary_damage(base_damage, level_value)

func fire_sword_multiplier(level_value: int) -> float:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.fire_sword_multiplier(level_value)

func fire_sword_damage(base_damage: int, level_value: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.fire_sword_damage(base_damage, level_value)

func wild_rush_success_threshold(skill_level: int, player_level: int, target_level: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.wild_rush_success_threshold(skill_level, player_level, target_level)

func wild_rush_success_probability(skill_level: int, player_level: int, target_level: int) -> float:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.wild_rush_success_probability(skill_level, player_level, target_level)

func wild_rush_max_cells(skill_level: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.wild_rush_max_cells(skill_level)

func client_attack_duration_seconds() -> float:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.client_attack_duration_seconds()

func client_effect_time_seconds() -> float:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.client_effect_time_seconds()

func active_skill_damage(skill_name: String, base_damage: int, level_value: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.active_skill_damage(skill_name, base_damage, level_value)
