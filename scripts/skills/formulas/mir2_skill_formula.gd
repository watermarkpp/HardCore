class_name Mir2SkillFormula
extends RefCounted

const SkillRankResolverScript := preload(
	"res://scripts/skills/skill_rank_resolver.gd"
)


static func mpow(rng: RefCounted, power: int, max_power: int) -> int:
	return power + int(rng.call("pascal_random_exclusive", max_power - power))


static func get_power(
	rng: RefCounted,
	rank: int,
	base_input: int,
	def_power := 0,
	def_max_power := 0
) -> int:
	## Base ranks 0..3 are exact; above 3 the formula's per-rank slope IS the
	## last-delta linear extension (skills.rank_extension.v1).
	var safe_rank := SkillRankResolverScript.safe_effective_rank(rank)
	var scaled := roundi(float(base_input) / 4.0 * float(safe_rank + 1))
	return scaled + def_power + int(rng.call("pascal_random_exclusive", def_max_power - def_power))


static func get_power13(
	rng: RefCounted,
	rank: int,
	base_input: int,
	def_power := 0,
	def_max_power := 0,
	train_rank_max := 3
) -> int:
	## train_rank_max keeps the historical divisor; the rank itself is not
	## clamped to it because effective ranks above base max extend linearly
	## with the same last-delta slope.
	var safe_rank := SkillRankResolverScript.safe_effective_rank(rank)
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
