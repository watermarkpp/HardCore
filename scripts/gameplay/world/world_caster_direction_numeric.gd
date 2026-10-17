extends RefCounted

## Exact original pure numeric GetFlyDirection16; no registry mutable state.
static func direction_index(direction: Vector2) -> int:
	if direction.length_squared() <= 0.0:
		return 8
	# Exact port of MirClient/ClFunc.pas GetFlyDirection16. Its four strict
	# slope thresholds are intentionally asymmetric with angle rounding.
	var fx := direction.x
	var fy := direction.y
	if fx == 0.0:
		return 0 if fy < 0.0 else 8
	if fy == 0.0:
		return 12 if fx < 0.0 else 4
	var result := 4 if fx > 0.0 else 12
	var absolute_y := absf(fy)
	var absolute_x := absf(fx)
	if absolute_y > absolute_x / 4.0:
		result = 3 if fy < 0.0 and fx > 0.0 else (
			5 if fy > 0.0 and fx > 0.0 else (
				11 if fy > 0.0 else 13
			)
		)
	if absolute_y > absolute_x / 1.9:
		result = 2 if fy < 0.0 and fx > 0.0 else (
			6 if fy > 0.0 and fx > 0.0 else (
				10 if fy > 0.0 else 14
			)
		)
	if absolute_y > absolute_x * 1.4:
		result = 1 if fy < 0.0 and fx > 0.0 else (
			7 if fy > 0.0 and fx > 0.0 else (
				9 if fy > 0.0 else 15
			)
		)
	if absolute_y > absolute_x * 4.0:
		result = 0 if fy < 0.0 else 8
	return result

