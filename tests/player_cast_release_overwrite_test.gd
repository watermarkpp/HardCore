extends Node

## R2-W5 red-green regression (multi-release contract): a superseding action
## may replace the presentation/action slot, but a begun action's delayed
## release must still resolve — the cast already charged its cooldown, so
## silently voiding the release converts a paid cast into a no-op.
##
## Mechanism (production data, vanilla_176 skills_source_of_truth):
## 治愈术 effect_resolve=800ms, action lock/cooldown default 1500ms. With
## equipment cast speed C=3.0 (production clamp is 6.0) the action-lock and
## cooldown gates expire at 500ms while the pending release fires at 800ms.
## The regression proves the 300ms window no longer destroys the first cast.

var failures: Array[String] = []
var checks := 0
var released_skills: Array[String] = []

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("道士")
	PlayerState.learned_skills = {"治愈术": 0, "施毒术": 0}
	var player := PlayerCharacter.new()
	add_child(player)
	player.current_mp = 100
	player._cast_speed_multiplier = 3.0
	player.skill_requested.connect(
		func(skill_name: String, _origin: Vector2, _direction: Vector2, _damage: int) -> void:
			released_skills.append(str(skill_name))
	)

	# t=0: begin 治愈术 (release at 800ms real time, gates expire at 500ms).
	expect(player.request_skill("治愈术"), "施放治愈术应被接受")
	expect(player._pending_combat_action_active, "施法提交后动作应处于 pending")
	expect(
		is_equal_approx(player._attack_timer, 0.5),
		"动作锁应按施法倍速 3.0 缩短为 500ms"
	)

	# t=650ms: lock/cooldown gates expired (500ms), healing release still
	# pending (800ms). The superseding cast is admitted (multi-release).
	await get_tree().create_timer(0.65).timeout
	expect(
		player._pending_combat_action_active and not player._pending_combat_action_committed,
		"650ms 时治愈术延迟释放必须仍未提交"
	)
	var admitted := player.request_skill("施毒术")
	expect(admitted, "门重新打开后的新施法动作必须被准入（多 release 方案）")

	# t=1350ms: 治愈术 release point (800ms) and 施毒术 release point
	# (650ms + 600ms body resolve = 1250ms) have both passed.
	await get_tree().create_timer(0.7).timeout
	expect(
		released_skills.has("治愈术"),
		"治愈术延迟释放不得被后续动作提交覆盖静默丢弃（实际释放=%s）" % [",".join(released_skills)]
	)
	expect(
		released_skills.has("施毒术"),
		"被准入的施毒术其自身释放链必须完整（实际释放=%s）" % [",".join(released_skills)]
	)

	player.free()
	for failure: String in failures:
		push_error("CAST_RELEASE_OVERWRITE: " + failure)
	print(
		"CAST_RELEASE_OVERWRITE_%s checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()]
	)
	get_tree().quit(0 if failures.is_empty() else 1)
