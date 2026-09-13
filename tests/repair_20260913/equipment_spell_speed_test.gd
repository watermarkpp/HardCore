extends Node
const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const Visibility := preload("res://scripts/skills/skill_visibility_policy.gd")
var _rows: Array = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded())
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	for profession: String in ["法师","道士"]:
		var skill := "火球术" if profession == "法师" else "灵魂火符"
		await _cast_pair(profession, skill)
	# All actual active caster entries consume the same adapter, including
	# delayed effects, explicit movement locks and shared dual-defence cooldowns.
	for profession: String in ["法师","道士"]:
		PlayerState.reset_progress(false)
		PlayerState.profession = profession
		PlayerState.level = 60
		PlayerState.equipment["左戒指"] = {"item_id":222,"name":"狂风戒指","count":1}
		PlayerState.recalculate_stats(false)
		for id: String in ProfessionRules.SKILL_CATALOG:
			var profile := ProfessionRules.skill_combat_profile(id,0)
			if str(profile.get("profession_id","")) != ("wizard" if profession == "法师" else "taoist") or str(profile.get("cast_type","")) == "passive": continue
			var definition := Loader.skill(id)
			var name := Loader.display_name(id)
			assert(not name.is_empty(),id)
			PlayerState.learned_skills = {name:0}
			var player := PlayerCharacter.new()
			add_child(player)
			player.hc_world_skill_preflight = func(_id: String,_target: int) -> bool: return true
			player.current_mp = 9999
			if not Visibility.is_skill_castable(id):
				assert(not player.request_skill(name),"hidden skill remains unavailable")
				player.free()
				continue
			var timing: Dictionary = definition.timing
			assert(player.request_skill(name), id)
			assert(is_equal_approx(player._attack_action_timer,float(timing.body_cast_ms)/1000.0*840.0/900.0),id)
			assert(is_equal_approx(player.visual._action_duration,player._attack_action_timer),id)
			assert(is_equal_approx(player._attack_timer,float(timing.total_action_lock_ms)/1000.0*840.0/900.0),id)
			assert(player.skill_cooldown_remaining_ms(id) >= 0)
			player.free()
	# Existing warrior-only skill cooldown and legacy percent-speed policy stay
	# unchanged; equipment ratio is selected solely for caster professions.
	PlayerState.profession = "战士"
	PlayerState.recalculate_stats(false)
	var warrior := PlayerCharacter.new()
	add_child(warrior)
	assert(warrior.attack_cooldown == 0.84 and warrior._equipment_spell_time_scale == 1.0)
	warrior.free()
	assert(CombatResolutionRules.equipment_spell_time_scale(-1) > 1.0)
	assert(CombatResolutionRules.equipment_spell_time_scale(2) < CombatResolutionRules.equipment_spell_time_scale(1))
	print("EQUIPMENT_SPELL_SPEED_PASS ",JSON.stringify(_rows))
	get_tree().quit()


func _cast_pair(profession: String, skill: String) -> void:
	var players: Array[PlayerCharacter] = []
	PlayerState.test_mode = true
	for equipped: bool in [false, true]:
		PlayerState.reset_progress(false)
		PlayerState.profession = profession
		PlayerState.level = 60
		PlayerState.learned_skills = {skill:0}
		if equipped:
			var ring := GameData.get_item_rules_record({"item_id":222})
			PlayerState.equipment["左戒指"] = PlayerState._make_item_instance(str(ring.name),ring,88212)
		PlayerState.recalculate_stats(false)
		assert(int(PlayerState.computed_stats.attack_speed_tier) == (1 if equipped else 0))
		var player := PlayerCharacter.new()
		add_child(player)
		player.current_mp = 9999
		players.append(player)
	# Compare concurrent timers in the SAME simulation frames. Separate cold
	# character setup frames make a sequential wall-clock comparison invalid.
	await get_tree().process_frame
	await get_tree().process_frame
	var releases: Array = [[], []]
	var starts: Array = [0, 0]
	for i in range(2):
		var player := players[i]
		player.skill_requested.connect(func(_name: String,_origin: Vector2,_direction: Vector2,_damage: int) -> void:
			releases[i].append((Time.get_ticks_usec()-int(starts[i]))/1000.0)
		)
		starts[i] = Time.get_ticks_usec()
		assert(player.request_skill(skill))
		assert(not player.request_skill(skill),"no double submission")
		_rows.append({"profession":profession,"speed":i,"body_seconds":player._attack_action_timer,"recast_seconds":player._attack_timer})
	var last := _rows.size()-1
	assert(is_equal_approx(float(_rows[last].body_seconds)/float(_rows[last-1].body_seconds),840.0/900.0))
	assert(float(_rows[last].recast_seconds)<float(_rows[last-1].recast_seconds))
	while (releases[0].is_empty() or releases[1].is_empty()) and Time.get_ticks_usec()-int(starts[0]) < 2000000:
		await get_tree().process_frame
	assert(releases[0].size()==1 and releases[1].size()==1)
	_rows[last-1]["release_ms"] = releases[0][0]
	_rows[last]["release_ms"] = releases[1][0]
	assert(float(releases[1][0]) < float(releases[0][0])-12.0, JSON.stringify(_rows))
	await get_tree().create_timer(0.08).timeout
	for i in range(2):
		assert(releases[i].size()==1)
		assert(not players[i].request_skill(skill),"body finish must not bypass recast cooldown")
		players[i].free()
