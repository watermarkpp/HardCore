extends "res://scripts/game_root.gd"

# Deterministic fixture input at the existing seed boundary, not another RNG.
func _next_canonical_seed() -> int:
	_canonical_cast_serial += 1
	return 760000 + _canonical_cast_serial
