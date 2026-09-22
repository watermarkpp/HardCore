extends Node
# This is an explicit public-signal reentry counterexample, not a claim that
# a current production observer already performs a map transition here.
var errors: Array[String] = []
var releases: Array[String] = []
var attack_releases: Array[Dictionary] = []
var checked := 0

func expect(value: bool, label: String) -> void:
	checked += 1
	if not value:
		errors.append(label)

func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("道士")
	PlayerState.learned_skills = {"治愈术": 0, "施毒术": 0}
	_run.call_deferred()

func make_player() -> PlayerCharacter:
	var p := PlayerCharacter.new()
	add_child(p)
	p.current_mp = 100
	p.skill_requested.connect(func(name: String, _o: Vector2, _d: Vector2, _v: int) -> void:
		releases.append(name))
	p.attack_requested.connect(func(_o: Vector2, _d: Vector2, _damage: int) -> void:
		attack_releases.append({"t": Time.get_ticks_msec()}))
	return p

func transition_in_cast_signal(_id: String, p: PlayerCharacter) -> void:
	expect(p.begin_combat_transition("rv14-synchronous-transition"), "signal transition accepted")
	expect(p.finish_combat_transition("rv14-synchronous-transition"), "signal transition completed")

func clear_attack_cooldowns(p: PlayerCharacter) -> void:
	p._attack_timer = 0.0
	p._attack_action_timer = 0.0

func _run() -> void:
	var p := make_player()
	var initial_epoch := p.combat_epoch
	p.skill_cast_started.connect(Callable(self, "transition_in_cast_signal").bind(p), CONNECT_ONE_SHOT)
	expect(p.request_skill("治愈术"), "action accepted before observer")
	expect(p.combat_epoch != initial_epoch, "observer ended original lifecycle")
	await get_tree().create_timer(1.2).timeout
	expect(releases.is_empty(), "old action must not inherit observer's new epoch")
	p.free()

	# No fallback admission branch: both spells must actually be accepted and
	# each signal must occur exactly once. Explicitly learn BOTH spells above.
	releases.clear()
	var healthy := make_player()
	healthy._cast_speed_multiplier = 3.0
	expect(healthy.request_skill("治愈术"), "first spell admitted")
	await get_tree().create_timer(0.65).timeout
	expect(healthy.request_skill("施毒术"), "second spell admitted")
	await get_tree().create_timer(0.9).timeout
	expect(releases.count("治愈术") == 1, "first spell exactly once")
	expect(releases.count("施毒术") == 1, "second spell exactly once")
	healthy.free()

	# --- Scenario 3: plain attack releases exactly once (no de-rating) ---
	attack_releases.clear()
	var attacker := make_player()
	clear_attack_cooldowns(attacker)
	expect(attacker.request_attack(false), "plain attack admitted")
	await get_tree().create_timer(1.2).timeout
	expect(attack_releases.size() == 1, "plain attack exactly once (actual=%d)" % attack_releases.size())
	attacker.free()

	# --- Scenario 4: synchronous transition after plain attack acceptance
	# must invalidate the pending release through the accepted epoch ---
	attack_releases.clear()
	var attacker_b := make_player()
	clear_attack_cooldowns(attacker_b)
	var epoch_before := attacker_b.combat_epoch
	expect(attacker_b.request_attack(false), "attack accepted before observer")
	expect(attacker_b.begin_combat_transition("rv14-attack-observer"), "attack observer begin")
	expect(attacker_b.finish_combat_transition("rv14-attack-observer"), "attack observer finish")
	expect(attacker_b.combat_epoch != epoch_before, "attack observer bumped epoch")
	await get_tree().create_timer(1.2).timeout
	expect(attack_releases.is_empty(), "attack must not inherit observer's new epoch")
	attacker_b.free()

	# --- Scenario 5: death during the windup cancels the plain attack;
	# after revival a fresh plain attack releases normally again ---
	attack_releases.clear()
	var attacker_c := make_player()
	clear_attack_cooldowns(attacker_c)
	expect(attacker_c.request_attack(false), "attack accepted before death")
	attacker_c.take_damage(attacker_c.current_hp + 100, false)
	expect(attacker_c._dead, "formal death took effect")
	await get_tree().create_timer(1.2).timeout
	expect(attack_releases.is_empty(), "dead fighter must not release the pending attack")
	attacker_c.complete_death_revival()
	clear_attack_cooldowns(attacker_c)
	expect(attacker_c.request_attack(false), "revived fighter can attack again")
	await get_tree().create_timer(1.2).timeout
	expect(attack_releases.size() == 1, "revived attack exactly once (actual=%d)" % attack_releases.size())
	attacker_c.free()

	# --- Scenario 6: exit tree then re-enter before the attack release ---
	attack_releases.clear()
	var attacker_d := make_player()
	clear_attack_cooldowns(attacker_d)
	expect(attacker_d.request_attack(false), "attack accepted before exit")
	remove_child(attacker_d)
	await get_tree().create_timer(1.2).timeout
	expect(attack_releases.is_empty(), "out-of-tree attack must not release")
	add_child(attacker_d)
	clear_attack_cooldowns(attacker_d)
	expect(attacker_d.request_attack(false), "re-entered fighter can attack again")
	await get_tree().create_timer(1.2).timeout
	expect(attack_releases.size() == 1, "re-entered attack exactly once (actual=%d)" % attack_releases.size())
	attacker_d.free()

	for message: String in errors:
		push_error("RV14_RELEASE_REENTRY: " + message)
	print("RV14_RELEASE_REENTRY_%s checks=%d failures=%d" % ["PASS" if errors.is_empty() else "FAIL", checked, errors.size()])
	get_tree().quit(0 if errors.is_empty() else 1)
