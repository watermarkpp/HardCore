class_name Mir2SkillFormulaReference
extends RefCounted

## 这是施工参考，不应由客户端单独权威计算。
## 所有随机函数必须注入可复现 RNG，测试中禁止使用全局随机状态。

static func pascal_random_exclusive(rng: RandomNumberGenerator, n: int) -> int:
	if n <= 0:
		return 0
	return rng.randi_range(0, n - 1)

static func roll_inclusive(
	rng: RandomNumberGenerator,
	min_value: int,
	max_value: int
) -> int:
	if max_value <= min_value:
		return min_value
	return rng.randi_range(min_value, max_value)

static func mpow(
	rng: RandomNumberGenerator,
	power: int,
	max_power: int
) -> int:
	return power + pascal_random_exclusive(rng, max_power - power)

static func get_power(
	rng: RandomNumberGenerator,
	rank: int,
	base_input: int,
	def_power: int = 0,
	def_max_power: int = 0
) -> int:
	var safe_rank := clampi(rank, 0, 3)
	var scaled := roundi(base_input / 4.0 * (safe_rank + 1))
	return scaled + def_power + pascal_random_exclusive(
		rng,
		def_max_power - def_power
	)

static func get_power13(
	rng: RandomNumberGenerator,
	rank: int,
	base_input: int,
	def_power: int = 0,
	def_max_power: int = 0,
	train_rank_max: int = 3
) -> int:
	var safe_rank := clampi(rank, 0, train_rank_max)
	var fixed_third := base_input / 3.0
	var scalable_two_thirds := base_input - fixed_third
	return roundi(
		scalable_two_thirds / float(train_rank_max + 1) * (safe_rank + 1)
		+ fixed_third
		+ def_power
		+ pascal_random_exclusive(rng, def_max_power - def_power)
	)

static func training_gain(rng: RandomNumberGenerator) -> int:
	return pascal_random_exclusive(rng, 3) + 1

static func slaying_proc_probability(rank: int) -> float:
	const VALUES := [0.10, 0.125, 1.0 / 6.0, 0.25]
	return VALUES[clampi(rank, 0, 3)]

static func repulsion_probability(
	rank: int,
	caster_level: int,
	target_level: int
) -> float:
	return clampf(
		(6.0 + 3.0 * clampi(rank, 0, 3) +
			caster_level - target_level) / 20.0,
		0.0,
		1.0
	)

static func wild_rush_probability(
	rank: int,
	caster_level: int,
	target_level: int
) -> float:
	return clampf(
		(6.0 + 6.0 * clampi(rank, 0, 3) +
			caster_level - target_level) / 20.0,
		0.0,
		1.0
	)

static func teleport_success(
	rng: RandomNumberGenerator,
	rank: int
) -> bool:
	var safe_rank := clampi(rank, 0, 3)
	return pascal_random_exclusive(rng, 11) < safe_rank * 2 + 4

static func holy_word_success(
	rng: RandomNumberGenerator,
	rank: int,
	caster_level: int,
	target_level: int
) -> bool:
	if pascal_random_exclusive(rng, 2) + caster_level - 1 <= target_level:
		return false
	var chance_percent := clampi(
		7 * clampi(rank, 0, 3) + 15 + caster_level - target_level,
		0,
		100
	)
	return pascal_random_exclusive(rng, 100) < chance_percent
