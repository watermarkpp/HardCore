extends RefCounted
## Build-time sealed V5 extension to the existing SPB validation.
## Gameplay still reads the existing SPB effective ledger, not a new override.

const AUTHORITY_SHA256 := "CD2AC726050B480D06115C39B9FA7E78A2AEB909B828741FD276AD9C5F2CAD2A"
const EFFECTIVE_SHA256 := "70A25D6A8CE3A016AA00E07CE7F3D7E4003C898BA5797E99DD965EE039931E86"
const BASELINE_SHA256 := "93E16AB952A428AC1B130CF75844A91F7A11858CA15A56AEB06689E63BA30940"
const MAX_RATIONAL := 2147483647


static func _integer(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float:
		var number := float(value)
		if is_finite(number) and number == floor(number) and abs(number) <= MAX_RATIONAL:
			return int(number)
	return -1


static func _sha256_lf(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var text := FileAccess.get_file_as_string(path).replace("\r\n", "\n").replace("\r", "\n")
	return text.sha256_text().to_upper()


static func verify_documents(authority: Dictionary, effective: Dictionary) -> bool:
	if _sha256_lf("res://assets/data/drop/dpv2_single_player_drop_boost_v1.json") != AUTHORITY_SHA256:
		return false
	if _sha256_lf("res://assets/data/drop/dpv2_single_player_effective_probability_v1.json") != EFFECTIVE_SHA256:
		return false
	if _sha256_lf("res://assets/data/drop/dpv2_direct_baseline_v2.json") != BASELINE_SHA256:
		return false
	var av: Variant = authority.get("repair_v5_contract", null)
	var ev: Variant = effective.get("repair_v5_contract", null)
	if not av is Dictionary or not ev is Dictionary or av != ev:
		return false
	return _integer(av.get("revision", null)) == 5


static func _gcd(a: int, b: int) -> int:
	while b > 0:
		var remainder := a % b
		a = b
		b = remainder
	return a


static func _ratio(numerator: int, denominator: int) -> Dictionary:
	if numerator <= 0 or denominator <= 0 or numerator > denominator:
		return {}
	var divisor := _gcd(numerator, denominator)
	@warning_ignore("integer_division")
	numerator = numerator / divisor
	@warning_ignore("integer_division")
	denominator = denominator / divisor
	if denominator > MAX_RATIONAL:
		return {}
	return {"numerator": numerator, "denominator": denominator}


static func _multiply(n: int, d: int, mn: int, md: int) -> Dictionary:
	if mn <= 0 or md <= 0 or mn > MAX_RATIONAL or md > MAX_RATIONAL:
		return {}
	var left := _gcd(n, md)
	var right := _gcd(mn, d)
	@warning_ignore("integer_division")
	n = n / left
	@warning_ignore("integer_division")
	md = md / left
	@warning_ignore("integer_division")
	mn = mn / right
	@warning_ignore("integer_division")
	d = d / right
	# Every operand is at most INT32_MAX; each product fits signed int64.
	return {"numerator": n * mn, "denominator": d * md}


static func final_formula(
	record: Dictionary,
	contract: Dictionary,
	base_stage: Dictionary,
	monster_classification: String,
) -> Dictionary:
	var mid := _integer(record.get("canonical_monster_id", null))
	var item := _integer(record.get("canonical_item_id", null))
	var uid := str(record.get("slot_uid", ""))
	var n := _integer(base_stage.get("numerator", null))
	var d := _integer(base_stage.get("denominator", null))
	if n <= 0 or d <= 0 or n > d:
		return {}
	if _integer(record.get("repair_v5_pre_numerator", null)) != n or _integer(record.get("repair_v5_pre_denominator", null)) != d:
		return {}
	var expected_rule := "NONE"
	if uid in contract.get("armor_slot_uids", []):
		expected_rule = "ARMOR_BASE_1_OVER_60"
		if mid < 235 or mid > 240 or _integer(record.get("base_numerator", null)) != 1 or _integer(record.get("base_denominator", null)) != 60:
			return {}
		n = 1
		d = 60
	elif bool(contract.get("boss_k_enabled", false)) and uid in contract.get("boss_allowed_slot_uids", []):
		expected_rule = "BOSS_K"
		if mid not in [76, 198, 199, 225]:
			return {}
		var multiplied := _multiply(n, d, _integer(contract.get("boss_k_numerator", null)), _integer(contract.get("boss_k_denominator", null)))
		if multiplied.is_empty():
			return {}
		# min(p*K, max(p, 1/4)), never reduce an already higher probability.
		var cap_n := n if n * 4 >= d else 1
		var cap_d := d if n * 4 >= d else 4
		var product_n: int = int(multiplied.numerator)
		var product_d: int = int(multiplied.denominator)
		# These bounds are enforced by the build-time rational gate as well.
		if product_n > MAX_RATIONAL or product_d > MAX_RATIONAL:
			return {}
		if product_n * cap_d > cap_n * product_d:
			n = cap_n
			d = cap_d
		else:
			n = product_n
			d = product_d
	elif item in contract.get("book_item_ids", []) and mid in contract.get("verified_book_monster_ids", []) and (mid < 235 or mid > 240):
		if monster_classification in ["ordinary", "elite", "boss"]:
			expected_rule = "BOOK_ORDINARY" if monster_classification == "ordinary" else "BOOK_ELITE_BOSS"
			n = _integer(record.get("base_numerator", null))
			d = _integer(record.get("base_denominator", null))
			var cap_d := 100 if monster_classification == "ordinary" else 20
			var multiplier := 5 if monster_classification == "ordinary" else 25
			if n <= 0 or d <= 0:
				return {}
			if n * cap_d < d:
				n *= multiplier
				if n * cap_d > d:
					n = 1
					d = cap_d
	if str(record.get("repair_v5_rule", "")) != expected_rule:
		return {}
	var output := _ratio(n, d)
	if output.is_empty():
		return {}
	if _integer(record.get("repair_v5_final_numerator", null)) != int(output.numerator) or _integer(record.get("repair_v5_final_denominator", null)) != int(output.denominator):
		return {}
	# Legacy ceiling_applied refers to the original SPB stage, not the Boss K.
	output["ceiling_applied"] = bool(base_stage.get("ceiling_applied", false))
	output["ok"] = true
	return output
