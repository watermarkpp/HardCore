extends Node

const SPELL_ACTION_DURATION := 0.36


func _ready() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var fire_wall_profile := ProfessionRules.skill_combat_profile("火墙", 0)
	assert(is_equal_approx(float(fire_wall_profile.get("action_duration", 0.0)), SPELL_ACTION_DURATION), "火墙特效时序错误拉长施法身体动作")
	assert(float(fire_wall_profile.get("cooldown", 0.0)) > SPELL_ACTION_DURATION, "火墙冷却没有与施法身体动作独立")
	_verify_all_active_caster_cooldowns()
	_verify_caster("法师", "火球术")
	_verify_caster("道士", "灵魂火符")
	_verify_cast_speed_does_not_shorten_body_action()
	print("CASTER_SPELL_ACTION_TIMING_PASS：法师/道士使用360ms施法动作锁，释放点与冷却独立")
	get_tree().quit(0)


func _verify_all_active_caster_cooldowns() -> void:
	for stable_id: String in ProfessionRules.SKILL_CATALOG:
		var profile := ProfessionRules.skill_combat_profile(stable_id, 0)
		if str(profile.get("profession_id", "")) not in ["wizard", "taoist"] or str(profile.get("cast_type", "")) == "passive":
			continue
		assert(float(profile.get("cooldown", 0.0)) > SPELL_ACTION_DURATION, "%s主动技能冷却不得与360ms身体动作混用" % stable_id)


func _verify_caster(profession: String, skill_name: String) -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession(profession)
	PlayerState.learned_skills = {skill_name: 0}
	var player := PlayerCharacter.new()
	add_child(player)
	player.current_mp = 100
	var profile := ProfessionRules.skill_combat_profile(skill_name, 0)
	var cooldown := float(profile.get("cooldown", 0.0))
	var windup := float(profile.get("windup", 0.0))
	assert(is_equal_approx(float(profile.get("action_duration", 0.0)), SPELL_ACTION_DURATION), "%s施法身体动作不是主源6帧×60ms" % profession)
	assert(int(profile.get("action_frame_count", 0)) == 6 and int(profile.get("action_frame_time_ms", 0)) == 60, "%s施法帧契约不完整" % profession)
	assert(not is_equal_approx(cooldown, SPELL_ACTION_DURATION), "%s技能冷却仍与身体动作混用" % profession)
	assert(windup > 0.0 and not is_equal_approx(windup, cooldown), "%s技能释放点仍与冷却混用" % profession)
	assert(player.request_skill(skill_name), "%s无法开始施放%s" % [profession, skill_name])
	assert(is_equal_approx(player._attack_action_timer, SPELL_ACTION_DURATION), "%s没有启用完整施法动作锁" % profession)
	assert(is_equal_approx(player.visual._action_duration, SPELL_ACTION_DURATION), "%s身体动画没有使用360ms动作时长" % profession)
	assert(is_equal_approx(player._attack_timer, cooldown), "%s技能冷却被身体动作时长覆盖" % profession)
	var caster_profession := PlayerState.profession
	PlayerState.profession = "战士"
	player.visual._action_remaining = SPELL_ACTION_DURATION
	player.visual._action_duration = SPELL_ACTION_DURATION
	player.visual._elapsed = 0.0
	player.visual._last_state = "action"
	player.visual._process(0.35)
	assert(player.visual.current_frame == 5, "%s施法表现没有推进到主源6帧动作的末帧：%d" % [profession, player.visual.current_frame])
	PlayerState.profession = caster_profession
	player.set_touch_vector(Vector2.RIGHT)
	player._physics_process(0.35)
	assert(not player.movement_input_active and player.velocity.is_zero_approx(), "%s在施法动作锁期间仍可移动" % profession)
	player._physics_process(0.02)
	assert(player._attack_action_timer <= 0.0, "%s施法动作锁没有在360ms后结束" % profession)
	assert(player.movement_input_active and player.velocity.x > 0.0, "%s施法动作锁结束后没有恢复移动" % profession)
	assert(player._attack_timer > 0.0, "%s技能冷却错误地随身体动作锁同时结束" % profession)
	assert(not player.request_skill(skill_name), "%s在身体动作结束但技能冷却未结束时错误允许再次施法" % profession)
	player.free()


func _verify_cast_speed_does_not_shorten_body_action() -> void:
	PlayerState.reset_progress()
	PlayerState.select_profession("法师")
	PlayerState.learned_skills = {"火球术": 0}
	var player := PlayerCharacter.new()
	add_child(player)
	player.current_mp = 100
	player._cast_speed_multiplier = 1.25
	var profile := ProfessionRules.skill_combat_profile("火球术", 0)
	assert(player.request_skill("火球术"), "施法速度隔离测试无法施放火球术")
	assert(is_equal_approx(player._attack_action_timer, SPELL_ACTION_DURATION), "施法速度错误缩短主源360ms身体动作")
	assert(is_equal_approx(player._attack_timer, float(profile.get("cooldown", 0.0)) / 1.25), "施法速度不再沿用既有技能冷却规则")
	player.free()
