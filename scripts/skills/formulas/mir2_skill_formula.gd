class_name Mir2SkillFormula
extends RefCounted


static func mpow(rng: RefCounted, power: int, max_power: int) -> int:
	return power + int(rng.call("pascal_random_exclusive", max_power - power))


static func get_power(
	rng: RefCounted,
	rank: int,
	base_input: int,
	def_power := 0,
	def_max_power := 0
) -> int:
	var scaled := roundi(float(base_input) / 4.0 * float(clampi(rank, 0, 3) + 1))
	return scaled + def_power + int(rng.call("pascal_random_exclusive", def_max_power - def_power))


static func get_power13(
	rng: RefCounted,
	rank: int,
	base_input: int,
	def_power := 0,
	def_max_power := 0,
	train_rank_max := 3
) -> int:
	var safe_rank := clampi(rank, 0, train_rank_max)
	var fixed_third := float(base_input) / 3.0
	var scalable_two_thirds := float(base_input) - fixed_third
	return roundi(
		scalable_two_thirds / float(train_rank_max + 1) * float(safe_rank + 1)
		+ fixed_third
		+ float(def_power)
		+ float(rng.call("pascal_random_exclusive", def_max_power - def_power))
	)


static func raw_magic_power(
	rng: RefCounted,
	rank: int,
	magic_db: Dictionary,
	primary_stat_roll: int,
	use_power13 := false
) -> int:
	var base_input := mpow(
		rng,
		int(magic_db.get("power", 0)),
		int(magic_db.get("max_power", magic_db.get("power", 0)))
	)
	if use_power13:
		return get_power13(
			rng,
			rank,
			base_input,
			int(magic_db.get("def_power", 0)),
			int(magic_db.get("def_max_power", 0))
		) + primary_stat_roll
	return get_power(
		rng,
		rank,
		base_input,
		int(magic_db.get("def_power", 0)),
		int(magic_db.get("def_max_power", 0))
	) + primary_stat_roll
