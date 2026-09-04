class_name SkillRng
extends RefCounted

var _rng := RandomNumberGenerator.new()


func _init(seed_value := 0) -> void:
	_rng.seed = seed_value


func reseed(seed_value: int) -> void:
	_rng.seed = seed_value


func pascal_random_exclusive(bound: int) -> int:
	if bound <= 0:
		return 0
	return _rng.randi_range(0, bound - 1)


func inclusive(minimum: int, maximum: int) -> int:
	if maximum <= minimum:
		return minimum
	return _rng.randi_range(minimum, maximum)


func training_gain() -> int:
	return pascal_random_exclusive(3) + 1


func chance(probability: float) -> bool:
	return _rng.randf() < clampf(probability, 0.0, 1.0)
