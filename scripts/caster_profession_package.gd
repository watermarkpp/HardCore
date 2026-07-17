class_name CasterProfessionPackage
extends RefCounted

var package_path := ""
var manifest: Dictionary = {}
var profession_id := ""
var package_id := ""
var display_name := ""
var gender := "male"
var character_level := 1
var current_mana := 0
var maximum_mana := 0
var learned_levels: Dictionary = {}
var training_points: Dictionary = {}
var materials: Dictionary = {}
var cooldowns: Dictionary = {}


func _init(source_path: String) -> void:
	package_path = source_path
	var file := FileAccess.open(package_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	manifest = parsed if parsed is Dictionary else {}
	profession_id = str(manifest.get("profession_id", ""))
	package_id = str(manifest.get("package_id", ""))
	display_name = str(manifest.get("display_name", ""))
	reset_character(1)


func is_valid() -> bool:
	return (
		not manifest.is_empty()
		and package_id == "profession.package.%s.v1" % profession_id
		and str(manifest.get("gender_policy", "")) == "male_only"
		and str(manifest.get("runtime", {}).get("package_contract", "")) == "caster_profession_package.v1"
	)


func identity() -> Dictionary:
	return {
		"package_id": package_id,
		"profession_id": profession_id,
		"display_name": display_name,
		"gender": gender,
		"gender_policy": str(manifest.get("gender_policy", "")),
		"package_contract": "caster_profession_package.v1",
		"state_contract": "caster_profession_state.v1",
	}


func supports_gender(value: String) -> bool:
	return value.to_lower() in ["male", "man", "男"]


func reset_character(level_value: int, mana_value := -1) -> void:
	character_level = maxi(1, level_value)
	var stats := stats_for_level(character_level)
	maximum_mana = int(stats.get("max_mp", 1))
	current_mana = maximum_mana if mana_value < 0 else clampi(mana_value, 0, maximum_mana)
	learned_levels.clear()
	training_points.clear()
	materials.clear()
	cooldowns.clear()


func stats_for_level(level_value: int) -> Dictionary:
	var level := maxi(1, level_value)
	var formula: Dictionary = manifest.get("growth", {}).get("runtime_formula", {})
	var hp_divisor := maxf(1.0, float(formula.get("hp_divisor", 1.0)))
	var hp_rate := float(formula.get("hp_rate", 0.0))
	var max_hp := 14 + int(round((float(level) / hp_divisor + hp_rate) * float(level)))
	var max_mp := 1
	if profession_id == "wizard":
		max_mp = 13 + int(round((float(level) / 5.0 + 2.0) * 2.2 * float(level)))
	else:
		var mp_divisor := maxf(1.0, float(formula.get("mp_divisor", 1.0)))
		max_mp = 13 + int(round(float(level) / mp_divisor * 2.2 * float(level)))
	return {
		"profession_id": profession_id,
		"level": level,
		"max_hp": max_hp,
		"max_mp": max_mp,
		"attack_min": int(formula.get("attack_min", 1)),
		"attack_max": int(formula.get("attack_max", 1)),
		"formula_id": str(formula.get("formula_id", "")),
		"formula_source": str(formula.get("source", "")),
	}


func skill_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for skill_id: String in manifest.get("skills", {}):
		result.append(skill_id)
	result.sort()
	return result


func skill_definition(skill_name_or_id: String) -> Dictionary:
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
	return manifest.get("skills", {}).get(skill_id, {}).duplicate(true)


func skill_level_record(skill_name_or_id: String, level_value := -1) -> Dictionary:
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
	var level := int(learned_levels.get(skill_id, 0)) if level_value < 0 else clampi(level_value, 0, 3)
	var definition := skill_definition(skill_id)
	var levels: Array = definition.get("levels", [])
	return levels[level].duplicate(true) if level >= 0 and level < levels.size() else {}


func learning_status(skill_name_or_id: String) -> Dictionary:
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
	var definition := skill_definition(skill_id)
	if definition.is_empty():
		return {"allowed": false, "reason": "wrong_profession_or_unknown_skill", "skill_id": skill_id}
	var current_level := int(learned_levels.get(skill_id, -1))
	var next_level := current_level + 1
	if next_level > 3:
		return {"allowed": false, "reason": "maximum_skill_level", "skill_id": skill_id, "current_level": current_level}
	var record := skill_level_record(skill_id, next_level)
	var required_character_level := int(record.get("requiredCharacterLevel", 1))
	var required_training_points := 0 if next_level == 0 else int(record.get("trainingPoints", 0))
	var current_training_points := int(training_points.get(skill_id, 0))
	var allowed := character_level >= required_character_level and current_training_points >= required_training_points
	return {
		"allowed": allowed,
		"reason": "" if allowed else ("character_level" if character_level < required_character_level else "training_points"),
		"skill_id": skill_id,
		"current_level": current_level,
		"next_level": next_level,
		"required_character_level": required_character_level,
		"required_training_points": required_training_points,
		"current_training_points": current_training_points,
		"source_trace": record.get("source_trace", {}).duplicate(true),
	}


func learn_skill(skill_name_or_id: String, skill_book_available := true) -> Dictionary:
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
	if learned_levels.has(skill_id):
		return {"learned": false, "reason": "already_learned", "skill_id": skill_id}
	if not skill_book_available:
		return {"learned": false, "reason": "skill_book_required", "skill_id": skill_id}
	var status := learning_status(skill_id)
	if not bool(status.get("allowed", false)):
		status["learned"] = false
		return status
	learned_levels[skill_id] = 0
	training_points[skill_id] = 0
	return {"learned": true, "reason": "", "skill_id": skill_id, "skill_level": 0}


func add_training_points(skill_name_or_id: String, amount: int) -> Dictionary:
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
	if not learned_levels.has(skill_id):
		return {"accepted": false, "reason": "skill_not_learned", "skill_id": skill_id}
	training_points[skill_id] = int(training_points.get(skill_id, 0)) + maxi(0, amount)
	var previous_level := int(learned_levels[skill_id])
	while int(learned_levels[skill_id]) < 3:
		var status := learning_status(skill_id)
		if not bool(status.get("allowed", false)):
			break
		learned_levels[skill_id] = int(learned_levels[skill_id]) + 1
	return {
		"accepted": true,
		"skill_id": skill_id,
		"previous_level": previous_level,
		"skill_level": int(learned_levels[skill_id]),
		"training_points": int(training_points[skill_id]),
	}


func load_skill_state(levels: Dictionary, points := {}) -> Dictionary:
	learned_levels.clear()
	training_points.clear()
	var rejected := PackedStringArray()
	for skill_name_or_id: Variant in levels:
		var skill_id := ProfessionRules.skill_id(str(skill_name_or_id))
		if skill_definition(skill_id).is_empty():
			rejected.append(str(skill_name_or_id))
			continue
		learned_levels[skill_id] = clampi(int(levels[skill_name_or_id]), 0, 3)
		training_points[skill_id] = maxi(0, int(points.get(skill_name_or_id, points.get(skill_id, 0))))
	return {"loaded_count": learned_levels.size(), "rejected": rejected}


func grant_material(material_id: String, amount: int) -> int:
	materials[material_id] = maxi(0, int(materials.get(material_id, 0)) + amount)
	return int(materials[material_id])


func restore_mana(amount: int) -> int:
	current_mana = mini(maximum_mana, current_mana + maxi(0, amount))
	return current_mana


func tick(delta: float) -> void:
	for skill_id: String in cooldowns.keys():
		var remaining := maxf(0.0, float(cooldowns[skill_id]) - maxf(0.0, delta))
		if remaining <= 0.0:
			cooldowns.erase(skill_id)
		else:
			cooldowns[skill_id] = remaining


func cooldown_remaining(skill_name_or_id: String) -> float:
	return float(cooldowns.get(ProfessionRules.skill_id(skill_name_or_id), 0.0))


func cast(skill_name_or_id: String, plan_context: Dictionary, execution_context: Dictionary) -> Dictionary:
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
	var validation := _cast_validation(skill_id)
	if not bool(validation.get("accepted", false)):
		return validation
	var skill_level := int(learned_levels[skill_id])
	var record := skill_level_record(skill_id, skill_level)
	var context := plan_context.duplicate(true)
	context["skill_level"] = skill_level
	context["caster_level"] = int(context.get("caster_level", character_level))
	context["owner_level"] = int(context.get("owner_level", character_level))
	var plan := CasterSkillRuntime.resolve(skill_id, context)
	plan["profession_package_id"] = package_id
	plan["mana_cost"] = int(record.get("manaCost", 0))
	plan["material_costs"] = _material_costs(skill_id)
	plan["level_source_trace"] = record.get("source_trace", {}).duplicate(true)
	var runtime_context := execution_context.duplicate(true)
	runtime_context["owner_level"] = int(runtime_context.get("owner_level", character_level))
	runtime_context["spiritual_power"] = int(runtime_context.get("spiritual_power", context.get("spiritual_stat_roll", 1)))
	var execution := CasterSkillRuntime.execute_cast(plan, runtime_context)
	if not str(execution.get("adapter_required", "")).is_empty():
		return {
			"accepted": false,
			"reason": "integration_adapter_required",
			"adapter_required": execution.adapter_required,
			"skill_id": skill_id,
			"plan": plan,
			"execution": execution,
		}
	current_mana -= int(plan.mana_cost)
	for material_id: String in plan.material_costs:
		materials[material_id] = int(materials.get(material_id, 0)) - int(plan.material_costs[material_id])
	var training_gain := int(manifest.get("runtime", {}).get("training_policy", {}).get("points_per_accepted_cast", 0))
	var training_result := add_training_points(skill_id, training_gain)
	var cooldown := float(plan.get("cooldown_seconds", 0.0))
	if cooldown > 0.0:
		cooldowns[skill_id] = cooldown
	return {
		"accepted": true,
		"reason": "",
		"skill_id": skill_id,
		"skill_level": skill_level,
		"mana_spent": int(plan.mana_cost),
		"mana_remaining": current_mana,
		"cooldown_seconds": cooldown,
		"training_gain": training_gain,
		"training_result": training_result,
		"effect_success": bool(plan.get("success", false)),
		"plan": plan,
		"execution": execution,
		"package_contract": "caster_profession_package.v1",
	}


func snapshot() -> Dictionary:
	return {
		"package_id": package_id,
		"profession_id": profession_id,
		"gender": gender,
		"character_level": character_level,
		"current_mana": current_mana,
		"maximum_mana": maximum_mana,
		"learned_levels": learned_levels.duplicate(true),
		"training_points": training_points.duplicate(true),
		"materials": materials.duplicate(true),
		"cooldowns": cooldowns.duplicate(true),
		"state_contract": "caster_profession_state.v1",
	}


func _cast_validation(skill_id: String) -> Dictionary:
	var definition := skill_definition(skill_id)
	if definition.is_empty():
		return {"accepted": false, "reason": "wrong_profession_or_unknown_skill", "skill_id": skill_id}
	if not learned_levels.has(skill_id):
		return {"accepted": false, "reason": "skill_not_learned", "skill_id": skill_id}
	if str(definition.get("combat_profile", {}).get("cast_type", "")) == "passive":
		return {"accepted": false, "reason": "passive_skill", "skill_id": skill_id}
	if cooldown_remaining(skill_id) > 0.0:
		return {
			"accepted": false,
			"reason": "cooldown",
			"skill_id": skill_id,
			"cooldown_remaining": cooldown_remaining(skill_id),
		}
	var record := skill_level_record(skill_id)
	var mana_cost := int(record.get("manaCost", 0))
	if current_mana < mana_cost:
		return {
			"accepted": false,
			"reason": "insufficient_mana",
			"skill_id": skill_id,
			"mana_required": mana_cost,
			"mana_available": current_mana,
		}
	for material_id: String in _material_costs(skill_id):
		var required := int(_material_costs(skill_id)[material_id])
		if int(materials.get(material_id, 0)) < required:
			return {
				"accepted": false,
				"reason": "insufficient_material",
				"skill_id": skill_id,
				"material_id": material_id,
				"material_required": required,
				"material_available": int(materials.get(material_id, 0)),
			}
	return {"accepted": true, "reason": "", "skill_id": skill_id}


func _material_costs(skill_id: String) -> Dictionary:
	var definition := skill_definition(skill_id)
	var rule: Dictionary = definition.get("combat_rule", {})
	var result := {}
	var amulet_cost := int(rule.get("amulet_cost", 0))
	if amulet_cost > 0:
		result["amulet"] = amulet_cost
	if skill_id == "taoist.poison":
		result["poison_powder"] = 1
	return result
