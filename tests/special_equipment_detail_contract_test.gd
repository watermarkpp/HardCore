extends Node

const Formatter := preload("res://scripts/item_detail_presenter.gd")


func _ready() -> void:
	_run.call_deferred()


func _equipment(name: String, description := "") -> Dictionary:
	return {
		"itemId": 910000 + name.length(),
		"name": name,
		"kind": "equipment",
		"category": "戒指",
		"weight": 1,
		"maxDurability": 5,
		"description": description,
	}


func _assert_contains(body: String, snippets: Array[String], label: String) -> void:
	for snippet: String in snippets:
		assert(body.contains(snippet), "%s detail missing: %s\n%s" % [label, snippet, body])


func _run() -> void:
	var stealth := Formatter.format_item(_equipment("隐身戒指"))
	_assert_contains(
		stealth,
		["穿戴后立即隐身", "攻击时解除", "脱离真实战斗后恢复", "零耐久或卸下立即失效"],
		"隐身戒指",
	)

	var paralysis := Formatter.format_item(_equipment("麻痹戒指"))
	_assert_contains(
		paralysis,
		["Boss/精英麻痹 2.5秒", "普通怪麻痹 5秒", "1/(5+目标毒物躲避)"],
		"麻痹戒指",
	)

	var revival := Formatter.format_item(_equipment("复活戒指"))
	_assert_contains(
		revival,
		["300秒", "自动复活", "自动复活不扣经验", "正常死亡经验规则照旧"],
		"复活戒指",
	)

	var teleport := Formatter.format_item(_equipment("传送戒指"))
	_assert_contains(teleport, ["传送技能", "消耗0点魔法值"], "传送戒指")

	var flame := Formatter.format_item(_equipment("火焰戒指"))
	_assert_contains(flame, ["火球技能", "消耗5点魔法值"], "火焰戒指")

	var recovery := Formatter.format_item(_equipment("防御戒指"))
	_assert_contains(
		recovery,
		["治愈技能", "消耗5点魔法值", "max(12, 等级/2+道术×2)"],
		"防御戒指",
	)

	var shield := Formatter.format_item(_equipment("护身戒指"))
	_assert_contains(shield, ["每1点伤害消耗1.5点魔法值"], "护身戒指")

	var overload := Formatter.format_item(_equipment("超负载戒指"))
	_assert_contains(overload, ["负重上限2倍"], "超负载戒指")

	var magic_blood := Formatter.format_item(_equipment("魔血戒指"))
	_assert_contains(magic_blood, ["魔血套装", "25点最大魔法转为最大生命", "三件套额外转换50点", "至少保留1点"], "魔血戒指")

	var rainbow := Formatter.format_item(_equipment("虹魔戒指"))
	_assert_contains(rainbow, ["虹魔套装", "近战吸血 +2%", "按传入伤害计算", "三件套准确 +2"], "虹魔戒指")

	# Source-only registrations are not player-facing enabled effects.
	var source_only := Formatter.format_item(
		_equipment("延期戒指", "specialEffectId=memory; source-only")
	)
	assert(not source_only.contains("已启用"), "source-only special effects must not be advertised as enabled")

	print("SPECIAL_EQUIPMENT_DETAIL_CONTRACT_PASS")
	get_tree().quit(0)
