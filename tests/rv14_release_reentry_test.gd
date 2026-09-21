extends Node
# This is an explicit public-signal reentry counterexample, not a claim that
# a current production observer already performs a map transition here.
var errors: Array[String] = []
var releases: Array[String] = []
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
	return p

func transition_in_cast_signal(_id: String, p: PlayerCharacter) -> void:
	expect(p.begin_combat_transition("rv14-synchronous-transition"), "signal transition accepted")
	expect(p.finish_combat_transition("rv14-synchronous-transition"), "signal transition completed")

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
	for message: String in errors:
		push_error("RV14_RELEASE_REENTRY: " + message)
	print("RV14_RELEASE_REENTRY_%s checks=%d failures=%d" % ["PASS" if errors.is_empty() else "FAIL", checked, errors.size()])
	get_tree().quit(0 if errors.is_empty() else 1)
