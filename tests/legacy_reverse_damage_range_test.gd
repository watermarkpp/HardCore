extends Node

const SkillCastRequestScript := preload("res://scripts/skills/skill_cast_request.gd")
const SkillRuntimeRouterScript := preload("res://scripts/skills/skill_runtime_router.gd")

func _ready() -> void:
	_run.call_deferred()


func _assert_roll_contract(attack_min: int, attack_max: int, expected_min: int, expected_max: int) -> void:
	var span := maxi(0, attack_max - attack_min)
	assert(
		WarriorCombatMath.attack_power_for_roll(attack_min, attack_max, -100) == expected_min,
		"区间 %d-%d 的负掷骰结果错误" % [attack_min, attack_max]
	)
	assert(
		WarriorCombatMath.attack_power_for_roll(attack_min, attack_max, span + 100) == expected_max,
		"区间 %d-%d 的上界掷骰结果错误" % [attack_min, attack_max]
	)


func _run() -> void:
	assert(
		WarriorCombatMath.DAMAGE_RANGE_ROLL_POLICY == "legacy_clamp_negative_span",
		"反向伤害区间稳定策略 ID 错误"
	)
	_assert_roll_contract(0, 30, 0, 30)
	_assert_roll_contract(12, 16, 12, 16)
	_assert_roll_contract(30, 0, 30, 30)
	_assert_roll_contract(15, 0, 15, 15)
	_assert_roll_contract(15, 10, 15, 15)
	_assert_roll_contract(35, 10, 35, 35)
	_assert_roll_contract(35, 35, 35, 35)
	_assert_roll_contract(35, 40, 35, 40)
	_assert_roll_contract(4, 3, 4, 4)
	_assert_roll_contract(4, 2, 4, 4)

	var rng := RandomNumberGenerator.new()
	rng.seed = 176
	for luck in [-9, 0, 9]:
		for index in range(64):
			assert(
				WarriorCombatMath.roll_attack_power(30, 0, luck, rng) == 30,
				"幸运/诅咒不得解除反向区间固定最小值"
			)

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("战士")
	PlayerState.computed_stats.merge({
		"attack_min": 30,
		"attack_max": 0,
		"luck": 9,
	}, true)
	var warrior := PlayerCharacter.new()
	add_child(warrior)
	assert(warrior.attack_min == 30 and warrior.attack_max == 0, "玩家属性接线交换了普通攻击端点")
	warrior.attack_hit_windup = 0.0
	var normal_damage := [-1]
	warrior.attack_requested.connect(func(_origin: Vector2, _direction: Vector2, damage: int) -> void:
		normal_damage[0] = damage
	)
	assert(warrior.request_attack(), "反向区间普通攻击未能发起")
	assert(normal_damage[0] == 30, "玩家普通攻击未采用 legacy_clamp_negative_span")
	warrior.queue_free()
	await get_tree().process_frame

	PlayerState.reset_progress()
	PlayerState.select_profession("法师")
	PlayerState.learned_skills = {"火球术": 0}
	PlayerState.computed_stats.merge({
		"magic_min": 4,
		"magic_max": 3,
		"luck": -9,
		"max_mp": 100,
	}, true)
	var wizard := PlayerCharacter.new()
	add_child(wizard)
	var skill_damage := [-1]
	wizard.skill_requested.connect(func(_skill_name: String, _origin: Vector2, _direction: Vector2, damage: int) -> void:
		skill_damage[0] = damage
	)
	assert(wizard.request_skill("火球术"), "反向 MC 区间技能未能发起")
	await get_tree().create_timer(1.0).timeout
	# The player signal is now a damage-free release. The canonical skill plan
	# owns the stat roll and formula, so a second roll here would diverge from it.
	assert(skill_damage[0] == 0, "人物释放信号不应在正式技能计划外重复掷骰")
	var fireball_power: Array[int] = []
	for mc_roll in [4, 5]:
		var request := SkillCastRequestScript.create(
			"wizard.fireball", 0, 40, Vector2i.ZERO, Vector2i.RIGHT,
			{"has_target": true, "line_of_sight": true, "primary_stat_roll": mc_roll},
			{"mana": 999, "materials": {}}, 17
		)
		var plan: Dictionary = SkillRuntimeRouterScript._plan(request)
		assert(plan.accepted and plan.effects.size() == 1)
		fireball_power.append(int(plan.effects[0].raw_power))
	assert(fireball_power[1] == fireball_power[0] + 1,
		"正式技能计划未按反向 MC 区间夹定后的主属性计算伤害")

	print("LEGACY_REVERSE_DAMAGE_RANGE_PASS：DC/MC/SC反向端点、玩家普通攻击、正式技能单一掷骰入口及幸运诅咒规则一致")
	get_tree().quit(0)
