extends Node

const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")
const CONTRACT_ID := "equipment.skill_level_affix.v1"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_canonical_stacking()
	_test_duplicate_aggregation()
	_test_legacy_array_compat()
	_test_legacy_dict_compat()
	_test_invalid_scopes()
	_test_value_validation()
	_test_malformed_containers()
	_test_overflow_guard()
	_test_immutability_and_determinism()
	_test_aggregate_records()
	_test_empty_records()
	print("EQUIPMENT_SKILL_LEVEL_AFFIX_PASS：稳定合同、legacy兼容、畸形拒绝、不可变性与确定性均通过")
	get_tree().quit(0)


func _test_canonical_stacking() -> void:
	var item := {
		"name": "测试项链",
		"modifiers": [
			{"stat": "skill_level", "scope": "all", "value": 1},
			{"stat": "skill_level", "scope": "profession:taoist", "value": 2},
			{"stat": "skill_level", "scope": "skill:taoist.healing", "value": 3},
			{"stat": "skill_level", "scope": "skill:wizard.hellfire", "value": 1},
			{"stat": "skill_level", "op": "add", "scope": "profession:warrior", "value": 1},
		],
	}
	var result := EquipmentRulesScript.skill_level_affix_contributions(item)
	assert(
		result.get("contractId", "") == CONTRACT_ID
		and result.get("contractId", "") == EquipmentRulesScript.SKILL_LEVEL_AFFIX_CONTRACT_ID,
		"稳定合同ID不符"
	)
	_assert_result(result, {
		"all": 1,
		"profession:taoist": 2,
		"profession:warrior": 1,
		"skill:taoist.healing": 3,
		"skill:wizard.hellfire": 1,
	})
	assert(result.get("legacy", {}) == {}, "canonical词条不应进入legacy")
	assert(int(result.get("accepted", -1)) == 5, "accepted计数不符")
	assert(int(result.get("rejected", -1)) == 0, "canonical词条不应被拒绝")
	assert(result.get("diagnostics", []) == [], "canonical词条不应产生诊断")


func _test_duplicate_aggregation() -> void:
	var item := {
		"modifiers": [
			{"stat": "skill_level", "scope": "all", "value": 1},
			{"stat": "skill_level", "scope": "all", "value": 2},
			{"stat": "skill_level", "scope": "profession:taoist", "value": 1},
			{"stat": "skill_level", "scope": "profession:taoist", "value": 2},
			{"stat": "skill_level", "scope": "skill:taoist.healing", "value": 1},
			{"stat": "skill_level", "scope": "skill:taoist.healing", "value": 2},
		],
	}
	var result := EquipmentRulesScript.skill_level_affix_contributions(item)
	_assert_result(result, {
		"all": 3,
		"profession:taoist": 3,
		"skill:taoist.healing": 3,
	})
	assert(int(result.get("accepted", -1)) == 6 and int(result.get("rejected", -1)) == 0, "重复词条聚合计数不符")


func _test_legacy_array_compat() -> void:
	var item := {
		"modifiers": [
			{"stat": "skill_level", "op": "add", "value": 2, "skill": "烈火剑法"},
			{"stat": "skill_level", "op": "add", "value": 1, "target": "治愈术"},
			{"stat": "skill_level", "op": "add", "value": 1},
			{"stat": "skill_level", "value": 1, "skill": "all"},
		],
	}
	var result := EquipmentRulesScript.skill_level_affix_contributions(item)
	_assert_result(result, {"all": 2}, {"烈火剑法": 2, "治愈术": 1})
	assert(int(result.get("accepted", -1)) == 4 and int(result.get("rejected", -1)) == 0, "legacy数组兼容计数不符")
	var legacy_diag := 0
	for diagnostic: Variant in result.get("diagnostics", []):
		if diagnostic is Dictionary:
			var diag: Dictionary = diagnostic
			if str(diag.get("code", "")) == "legacy_display_name_scope":
				legacy_diag += 1
	assert(legacy_diag == 2, "legacy中文名应输出转换提示")


func _test_legacy_dict_compat() -> void:
	var item := {
		"modifiers": {
			"skillLevels": {"all": 1, "烈火剑法": 2, "taoist.healing": 3},
		},
	}
	var result := EquipmentRulesScript.skill_level_affix_contributions(item)
	_assert_result(result, {"all": 1, "skill:taoist.healing": 3}, {"烈火剑法": 2})
	assert(int(result.get("accepted", -1)) == 3 and int(result.get("rejected", -1)) == 0, "skillLevels兼容计数不符")


func _test_invalid_scopes() -> void:
	var item := {
		"modifiers": [
			{"stat": "skill_level", "scope": "profession:assassin", "value": 1},
			{"stat": "skill_level", "scope": "skill:治愈术", "value": 1},
			{"stat": "skill_level", "scope": "banana", "value": 1},
			{"stat": "skill_level", "scope": 123, "value": 1},
			{"stat": "skill_level", "scope": "skill:", "value": 1},
			{"stat": "skill_level", "scope": "profession:", "value": 1},
			{"stat": "skill_level", "scope": "PROFESSION:taoist", "value": 1},
		],
	}
	var result := EquipmentRulesScript.skill_level_affix_contributions(item)
	assert(int(result.get("rejected", -1)) == 7, "畸形scope应全部拒绝")
	assert(result.get("contributions", {}) == {}, "畸形scope不得产生贡献")
	_expect_diagnostic(result, "invalid_profession_scope")
	_expect_diagnostic(result, "invalid_skill_scope")
	_expect_diagnostic(result, "invalid_scope")


func _test_value_validation() -> void:
	var item := {
		"modifiers": [
			{"stat": "skill_level", "scope": "all", "value": -1},
			{"stat": "skill_level", "scope": "all", "value": 0},
			{"stat": "skill_level", "scope": "all", "value": 1.5},
			{"stat": "skill_level", "scope": "all", "value": INF},
			{"stat": "skill_level", "scope": "all", "value": NAN},
			{"stat": "skill_level", "scope": "all", "value": "2"},
			{"stat": "skill_level", "scope": "all"},
			{"stat": "skill_level", "scope": "all", "value": null},
			{"stat": "skill_level", "scope": "all", "value": true},
			{"stat": "skill_level", "scope": "all", "value": 2.0},
		],
	}
	var result := EquipmentRulesScript.skill_level_affix_contributions(item)
	assert(int(result.get("rejected", -1)) == 9, "畸形value应全部拒绝")
	assert(int(result.get("accepted", -1)) == 1, "整数语义浮点应接受")
	_assert_result(result, {"all": 2})
	_expect_diagnostic(result, "non_positive_value")
	_expect_diagnostic(result, "non_integer_value")
	_expect_diagnostic(result, "non_finite_value")
	_expect_diagnostic(result, "invalid_value_type")
	_expect_diagnostic(result, "missing_value")


func _test_malformed_containers() -> void:
	var mixed := {
		"modifiers": [
			"oops",
			{"stat": "skill_level", "op": "percent", "scope": "all", "value": 1},
			{"stat": "skill_level", "scope": "all", "skill": "烈火剑法", "value": 1},
			{"value": 1},
			{"stat": "attack_speed", "op": "add", "value": 0.2},
		],
	}
	var result := EquipmentRulesScript.skill_level_affix_contributions(mixed)
	assert(int(result.get("rejected", -1)) == 4, "畸形记录应全部拒绝")
	assert(int(result.get("accepted", -1)) == 0, "畸形记录不得接受")
	_expect_diagnostic(result, "malformed_record")
	_expect_diagnostic(result, "unsupported_op")
	_expect_diagnostic(result, "conflicting_scope_fields")
	_expect_diagnostic(result, "missing_stat")
	assert(result.get("diagnostics", []).size() == 4, "其他stat词条应静默跳过")

	var bad_container := EquipmentRulesScript.skill_level_affix_contributions({"modifiers": 42})
	assert(int(bad_container.get("rejected", -1)) == 1, "非数组/对象modifiers应拒绝")
	_expect_diagnostic(bad_container, "unsupported_modifiers_container")

	var bad_levels := EquipmentRulesScript.skill_level_affix_contributions({"modifiers": {"skillLevels": [1, 2]}})
	assert(int(bad_levels.get("rejected", -1)) == 1, "非对象skillLevels应拒绝")
	_expect_diagnostic(bad_levels, "malformed_skill_levels")


func _test_overflow_guard() -> void:
	var big := 9223372036854775806
	var item := {
		"modifiers": [
			{"stat": "skill_level", "scope": "all", "value": big},
			{"stat": "skill_level", "scope": "all", "value": big},
		],
	}
	var result := EquipmentRulesScript.skill_level_affix_contributions(item)
	assert(int(result.get("contributions", {}).get("all", 0)) == 9223372036854775807, "溢出应钳制到int64最大值")
	assert(int(result.get("accepted", -1)) == 2 and int(result.get("rejected", -1)) == 0, "溢出保护不应改变接受计数")
	_expect_diagnostic(result, "overflow_guard_clamped")


func _test_immutability_and_determinism() -> void:
	var item := {
		"name": "测试",
		"modifiers": [
			{"stat": "skill_level", "scope": "all", "value": 1},
			{"stat": "skill_level", "scope": "skill:taoist.healing", "value": 2},
			{"stat": "skill_level", "op": "add", "value": 3, "skill": "烈火剑法"},
			{"stat": "skill_level", "scope": "profession:assassin", "value": 1},
		],
	}
	var original := item.duplicate(true)
	var snapshot := JSON.stringify(item)
	var first := EquipmentRulesScript.skill_level_affix_contributions(item)
	assert(item == original, "输入对象被修改")
	assert(JSON.stringify(item) == snapshot, "输入JSON被修改")
	var second := EquipmentRulesScript.skill_level_affix_contributions(item)
	assert(JSON.stringify(first) == JSON.stringify(second), "相同输入解析结果不确定")


func _test_aggregate_records() -> void:
	var records := [
		{
			"modifiers": [
				{"stat": "skill_level", "scope": "all", "value": 1},
				{"stat": "skill_level", "scope": "skill:taoist.healing", "value": 2},
			],
		},
		{"modifiers": {"skillLevels": {"烈火剑法": 3, "all": 1}}},
		42,
	]
	var total := EquipmentRulesScript.aggregate_skill_level_affix_records(records)
	_assert_result(total, {"all": 2, "skill:taoist.healing": 2}, {"烈火剑法": 3})
	assert(int(total.get("accepted", -1)) == 4 and int(total.get("rejected", -1)) == 1, "多装备聚合计数不符")
	_expect_diagnostic(total, "malformed_record")
	_expect_diagnostic(total, "legacy_display_name_scope")


func _test_empty_records() -> void:
	var empty := EquipmentRulesScript.skill_level_affix_contributions({})
	assert(empty == {
		"contractId": CONTRACT_ID,
		"contributions": {},
		"legacy": {},
		"diagnostics": [],
		"accepted": 0,
		"rejected": 0,
	}, "无词条记录应返回空结果")


func _assert_result(result: Dictionary, expected_contributions: Dictionary, expected_legacy: Dictionary = {}) -> void:
	assert(
		result.get("contributions", {}) == expected_contributions,
		"canonical贡献不符: %s" % JSON.stringify(result.get("contributions", {}))
	)
	assert(result.get("legacy", {}) == expected_legacy, "legacy贡献不符: %s" % JSON.stringify(result.get("legacy", {})))


func _expect_diagnostic(result: Dictionary, code: String) -> void:
	var found := false
	for diagnostic: Variant in result.get("diagnostics", []):
		if diagnostic is Dictionary:
			var diag: Dictionary = diagnostic
			if str(diag.get("code", "")) == code:
				found = true
				break
	assert(found, "缺少诊断%s" % code)
