extends Node

## Real mage cast + ordinary struck chain (reviewer close-out item 1):
## K: a threshold hit during an active pre-commit cast queues exactly one
##    pending struck reaction and never cancels the cast;
## L: the cast commits at its real windup, skill_requested fires exactly once,
##    and the queued reaction plays only after the cast action finishes;
## M: the 240ms reaction window ends and control returns.

const ProfessionRules := preload("res://scripts/profession_rules.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("法师")
	# Level 40 keeps the fixture on the V4 unified 240ms reaction window.
	PlayerState.level = 40
	PlayerState.learned_skills = {"火球术": 0}
	var player := PlayerCharacter.new()
	add_child(player)
	player.current_mp = 100
	player.max_hp = 500
	player.current_hp = 500
	player.defense_min = 0
	player.defense_max = 0
	var threshold := ProfessionRules.player_struck_damage_threshold(500)
	assert(threshold == 15, "500 最大生命的 3% 硬直阈值必须保持 15")

	var skill_requests: Array[String] = []
	player.skill_requested.connect(func(skill_name: String, _origin: Vector2, _direction: Vector2, _damage: int) -> void:
		skill_requests.append(skill_name)
	)

	# ---- K: threshold hit during an active pre-commit cast queues one pending ----
	assert(player.request_skill("火球术"), "法师必须能施放火球术")
	var cast_snapshot := player.combat_action_snapshot()
	assert(
		bool(cast_snapshot.active) and str(cast_snapshot.kind) == "skill:火球术",
		"施法必须进入combat action事务"
	)
	assert(not bool(cast_snapshot.committed), "windup 前施法事务不得提前提交")
	assert(player._attack_action_timer > 0.0, "施法动作锁必须生效")
	assert(str(player.visual._action_name) == "cast", "施法必须播放cast动作")
	player.take_damage(threshold)
	assert(player.current_hp == 500 - threshold, "施法期间阈值伤害必须正常扣血")
	assert(bool(player.struck_reaction_snapshot().queued), "施法期间阈值命中必须只排队pending硬直")
	assert(str(player.visual._action_name) == "cast", "普通受击不得取消已开始的施法动作")
	assert(player._struck_reaction_lock_remaining <= 0.0, "排队期间不得提前播放受击锁")

	# ---- L: real windup commit fires skill_requested exactly once ----
	var windup := float(ProfessionRules.skill_combat_profile("火球术", 0)["windup"])
	assert(windup > 0.0, "火球术必须有真实释放点")
	var guard := 0
	while (
		not bool(player.combat_action_snapshot().committed) and guard < 600
	):
		await get_tree().process_frame
		guard += 1
	assert(bool(player.combat_action_snapshot().committed), "windup 后施法事务必须已提交")
	assert(skill_requests.size() == 1, "施法释放必须恰好发出一次skill_requested")
	assert(bool(player.combat_action_snapshot().active), "动作锁结束前施法事务必须保持active")
	while player._attack_action_timer > 0.0:
		await get_tree().process_frame
	assert(not bool(player.combat_action_snapshot().active), "施法动作锁结束后事务必须结束")
	assert(not bool(player.struck_reaction_snapshot().queued), "施法结束后排队硬直必须被消费且只消费一次")
	assert(str(player.visual._action_name) == "hit", "施法结束后必须播放排队的受击表现")
	var reaction := float(player.struck_reaction_snapshot().reaction_lock_remaining)
	assert(
		reaction > 0.2 and reaction <= 0.24,
		"消费后的受击表现必须落在240ms窗口内：%f" % reaction
	)
	assert(skill_requests.size() == 1, "硬直消费不得重复释放技能")

	# ---- M: reaction window ends and the mage regains control ----
	await get_tree().create_timer(reaction + 0.05).timeout
	assert(player._struck_reaction_lock_remaining <= 0.0, "240ms受击表现必须正常结束")
	assert(not bool(player.struck_reaction_snapshot().queued), "受击结束后不得残留第二次pending")
	print("PLAYER_SKILL_STRUCK_CHAIN_PASS: cast survives struck, commits once, queued reaction plays after cast")
	get_tree().quit(0)
