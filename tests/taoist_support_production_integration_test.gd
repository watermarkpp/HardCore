extends Node

const Policy := preload("res://scripts/skills/taoist_support_policy.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

var game: Node
var player: PlayerCharacter


func _ready() -> void:
	_run.call_deferred()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession(
		ProfessionRules.profession_display_name("taoist")
	)
	PlayerState.level = 40
	PlayerState.inventory = []
	PlayerState.learned_skills = {
		_display("taoist.healing"): 3,
		_display("taoist.mass_healing"): 3,
		_display("taoist.mass_invisibility"): 3,
		_display("taoist.magic_defense"): 3,
		_display("taoist.defense"): 3,
	}
	PlayerState.recalculate_stats()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	player = game.player
	game.current_map_id = -1
	player.set_physics_process(false)
	player.global_position = Vector2(200, 200)
	player.velocity = Vector2.ZERO
	player.max_hp = 200
	player.current_hp = 100
	player.current_mp = 999
	player.defense_min = 0
	player.defense_max = 0
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor:
			(node as EnemyActor).global_position = (
				player.global_position + Vector2(5000, 5000)
			)

	_verify_input_rejection_and_selection()
	await _verify_heal_release_timing_and_summon_redraw()
	await _verify_release_footpoint_and_reselect()
	await _verify_area_effects_and_defence()
	await _verify_dual_defence_production()
	await _verify_rank_zero_dual_defence()
	_verify_fractional_center_geometry()
	_verify_player_defence_separation()
	print(
		"TAOIST_SUPPORT_PRODUCTION_INTEGRATION_PASS: preflight rejection, "
		+ "600/800 ms heal release and summon redraw, release live footpoint/"
		+ "one-time reselect, 3x3/7x7 area, dual "
		+ "defence shared cooldown/MP, full-HP ongoing heal, stealth break, "
		+ "player AC/MAC separation"
	)
	get_tree().quit(0)


func _verify_input_rejection_and_selection() -> void:
	var summon := _make_summon(Vector2(2, 0), player)
	summon.max_hp = 100
	summon.current_hp = 30
	player.max_hp = 200
	player.current_hp = 100
	player.facing = Vector2.RIGHT
	var facing_before := player.facing
	var result: StringName = game._try_release_skill(_display("taoist.healing"))
	assert(result == &"accepted")
	assert(game._selected_friendly_instance_id == summon.get_instance_id())
	assert(player._attack_timer > 0.0)
	assert(player.skill_cooldown_remaining_ms("taoist.healing") > 0)
	assert(player.facing == facing_before, "healing must not auto-turn")
	assert(player.current_mp == 999, "input must not spend MP")
	player._finish_combat_action(player._pending_combat_action_id)
	_reset_cast_state()

	player.current_hp = player.max_hp
	summon.current_hp = summon.max_hp
	var mp_before := player.current_mp
	## Full-HP friendlies are valid heal targets (user override 2026-08-09):
	## input is accepted, self is preferred, MP still commits only at release.
	var full_result: StringName = game._try_release_skill(
		_display("taoist.healing")
	)
	assert(full_result == &"accepted")
	assert(game._selected_friendly_instance_id == player.get_instance_id())
	assert(player._attack_timer > 0.0)
	assert(player.skill_cooldown_remaining_ms("taoist.healing") > 0)
	assert(player.current_mp == mp_before)
	player._finish_combat_action(player._pending_combat_action_id)
	_reset_cast_state()

	## Mana-insufficient rejection must also clear the selected identity.
	summon.current_hp = 30
	player.current_hp = 100
	player.current_mp = 0
	var mana_rejected: StringName = game._try_release_skill(
		_display("taoist.healing")
	)
	assert(mana_rejected == &"rejected")
	assert(game._selected_friendly_instance_id == 0)
	player.current_mp = 999
	summon.free()


func _verify_heal_release_timing_and_summon_redraw() -> void:
	## Single healing resolves at the explicit 800 ms override, not at the
	## 600 ms body release used by the other Taoist support skills.
	_reset_cast_state()
	player.current_hp = player.max_hp
	var single_target := _make_summon(Vector2(2, 0), player)
	single_target.max_hp = 100
	single_target.current_hp = 20
	single_target.reset_performance_diagnostics_for_tests()
	var single_mp_before: int = player.current_mp
	assert(game._try_release_skill(_display("taoist.healing")) == &"accepted")
	await get_tree().create_timer(0.70).timeout
	assert(single_target.current_hp == 20, "single heal resolved before 800 ms")
	assert(player.current_mp == single_mp_before, "single heal spent MP before release")
	await get_tree().create_timer(0.20).timeout
	assert(single_target.current_hp > 20, "single heal did not resolve after 800 ms")
	assert(player.current_mp < single_mp_before, "single heal did not spend MP at release")
	single_target.free()

	## Mass healing keeps the ordinary 600 ms release. Its selected summon must
	## remain unchanged before that frame, then update immediately.
	_reset_cast_state()
	player.current_hp = player.max_hp
	var mass_target := _make_summon(Vector2(2, 0), player)
	mass_target.max_hp = 100
	mass_target.current_hp = 25
	mass_target.reset_performance_diagnostics_for_tests()
	var mass_mp_before: int = player.current_mp
	assert(game._try_release_skill(_display("taoist.mass_healing")) == &"accepted")
	await get_tree().create_timer(0.50).timeout
	assert(mass_target.current_hp == 25, "mass heal resolved before 600 ms")
	assert(player.current_mp == mass_mp_before, "mass heal spent MP before release")
	await get_tree().create_timer(0.20).timeout
	assert(mass_target.current_hp > 25, "mass heal did not resolve after 600 ms")
	assert(player.current_mp < mass_mp_before, "mass heal did not spend MP at release")
	await _wait_for_summon_visual_request_to_settle(mass_target)

	## The GameRoot helper returns the actual capped restoration and the ongoing
	## scheduler reaches the exact same redraw-aware summon API.
	mass_target.current_hp = 95
	mass_target.reset_performance_diagnostics_for_tests()
	assert(game._apply_canonical_friendly_heal(mass_target, 10) == 5)
	assert(mass_target.current_hp == 100)
	assert(
		int(mass_target.performance_diagnostics().custom_draw_request_count) == 1
	)
	mass_target.reset_performance_diagnostics_for_tests()
	assert(game._apply_canonical_friendly_heal(mass_target, 10) == 0)
	assert(
		int(mass_target.performance_diagnostics().custom_draw_request_count) == 0
	)
	game._ongoing_heals.clear()
	mass_target.current_hp = 50
	mass_target.reset_performance_diagnostics_for_tests()
	game._register_ongoing_heal(mass_target.get_instance_id(), 7, 1, 0.8)
	game._tick_ongoing_heals(0.79)
	assert(mass_target.current_hp == 50)
	assert(
		int(mass_target.performance_diagnostics().custom_draw_request_count) == 0
	)
	game._tick_ongoing_heals(0.02)
	assert(mass_target.current_hp == 57)
	assert(
		int(mass_target.performance_diagnostics().custom_draw_request_count) == 1
	)

	## Dead summons are never revived by either direct or scheduled healing.
	# The summon fixture has canonical AC absorption enabled.  Use the explicit
	# minimum-roll override plus AC headroom so this assertion exercises the
	# real lethal/dead transition instead of depending on a random roll.
	mass_target.take_damage(mass_target.current_hp + mass_target.ac_max, 0)
	assert(mass_target.state == SummonActor.SummonState.DEAD)
	mass_target.reset_performance_diagnostics_for_tests()
	assert(game._apply_canonical_friendly_heal(mass_target, 50) == 0)
	assert(mass_target.current_hp == 0)
	assert(
		int(mass_target.performance_diagnostics().custom_draw_request_count) == 0
	)
	game._ongoing_heals.clear()
	game._register_ongoing_heal(mass_target.get_instance_id(), 9, 1, 0.8)
	game._tick_ongoing_heals(0.81)
	assert(mass_target.current_hp == 0)
	assert(game._ongoing_heals.is_empty())
	assert(
		int(mass_target.performance_diagnostics().custom_draw_request_count) == 0
	)
	mass_target.free()
	_reset_cast_state()


func _wait_for_summon_visual_request_to_settle(summon: SummonActor) -> void:
	for _frame_index: int in range(300):
		if not bool(summon.performance_diagnostics().visual_request_active):
			return
		await get_tree().process_frame
	assert(false, "summon visual request did not settle before redraw assertions")


func _verify_release_footpoint_and_reselect() -> void:
	## Live footpoint: the selected friendly moves during windup; mass heal
	## must center its 3x3 on the release-frame position.
	var summon_a := _make_summon(Vector2(2, 0), player)
	summon_a.max_hp = 100
	summon_a.current_hp = 40
	player.current_hp = player.max_hp
	_reset_cast_state()
	assert(game._try_release_skill(_display("taoist.mass_healing")) == &"accepted")
	summon_a.global_position = _screen_at(Vector2(4, 0))
	await get_tree().create_timer(1.0).timeout
	assert(summon_a.current_hp > 40, "selected summon must be healed")
	assert(
		player.current_hp == player.max_hp,
		"mass heal must center on the selected live footpoint, not the caster"
	)
	_reset_cast_state()

	## One-time reselect: input target becomes full during windup; the release
	## must reselect the current lowest-HP% friendly exactly once.
	var summon_b := _make_summon(Vector2(3, 0), player)
	summon_b.max_hp = 100
	summon_b.current_hp = 50
	summon_a.current_hp = 20
	summon_a.max_hp = 100
	player.current_hp = player.max_hp
	_reset_cast_state()
	assert(game._try_release_skill(_display("taoist.mass_healing")) == &"accepted")
	assert(game._selected_friendly_instance_id == summon_a.get_instance_id())
	summon_a.current_hp = summon_a.max_hp
	await get_tree().create_timer(1.0).timeout
	assert(summon_b.current_hp > 50, "release must reselect the injured summon")
	assert(summon_a.current_hp == summon_a.max_hp)
	assert(game._selected_friendly_instance_id == summon_b.get_instance_id())
	_reset_cast_state()

	## All friendlies full at release: the cast still commits once, reselects
	## self, and attaches the ongoing recovery (user override 2026-08-09).
	player.current_hp = player.max_hp
	summon_a.current_hp = 10
	summon_b.current_hp = 10
	summon_b.max_hp = 100
	_reset_cast_state()
	assert(game._try_release_skill(_display("taoist.mass_healing")) == &"accepted")
	summon_a.current_hp = summon_a.max_hp
	summon_b.current_hp = summon_b.max_hp
	var mp_before := player.current_mp
	var ongoing_before: int = (game.get("_ongoing_heals") as Array).size()
	await get_tree().create_timer(1.0).timeout
	assert(player.current_mp < mp_before, "all-full release must commit MP once")
	assert(
		game._selected_friendly_instance_id == player.get_instance_id(),
		"all-full release must reselect self"
	)
	assert(
		game._ongoing_heals.size() > ongoing_before,
		"all-full release must attach the ongoing recovery"
	)
	summon_a.free()
	summon_b.free()


func _verify_area_effects_and_defence() -> void:
	_reset_cast_state()
	var own_summon := _make_summon(Vector2(1, 0), player, 21, 7)
	own_summon.current_hp = own_summon.max_hp
	var own_beast := _make_summon(
		Vector2(-1, 0),
		player,
		21,
		7,
		"taoist.summon_divine_beast"
	)
	own_beast.current_hp = own_beast.max_hp
	var other_owner := PlayerCharacter.new()
	var other_summon := _make_summon(Vector2(0, 1), other_owner)
	other_summon.current_hp = other_summon.max_hp
	var far_summon := _make_summon(Vector2(10, 0), player)
	far_summon.current_hp = far_summon.max_hp
	player.current_hp = player.max_hp
	await _wait_for_summon_visual_request_to_settle(own_summon)
	await _wait_for_summon_visual_request_to_settle(own_beast)

	## Mass invisibility: self-centered exact 3x3, only own friendly actors.
	assert(game._try_release_skill(_display("taoist.mass_invisibility")) == &"accepted")
	await get_tree().create_timer(1.0).timeout
	assert(player.is_stealthed())
	assert(own_summon.is_stealthed())
	assert(own_beast.is_stealthed())
	assert(not other_summon.is_stealthed(), "non-owned summon must not be affected")
	assert(not far_summon.is_stealthed(), "out-of-range summon must not be affected")
	## Stealth renders as alpha transparency (no light-blue ground circle).
	## Simulate a stale cache/parent alpha left by builds that faded the whole
	## summon; the current integration must heal it on the next presentation tick.
	own_summon.modulate.a = 0.4
	game._stealth_alpha_restore[own_summon.get_instance_id()] = 0.4
	game._process(0.016)
	assert(
		is_equal_approx(player.modulate.a, 0.60),
		"stealthed player must render at the canonical 0.60 alpha"
	)
	assert(
		is_equal_approx(own_summon.modulate.a, 1.0),
		"summon parent must remain opaque so its hint layer stays readable"
	)
	assert(
		not game._stealth_alpha_restore.has(own_summon.get_instance_id()),
		"summon parent must discard stale whole-actor alpha restore state"
	)
	assert(
		is_equal_approx(own_summon._sprite.self_modulate.a, 0.60),
		"summon body must own the 0.60 stealth fade"
	)
	assert(is_equal_approx(own_beast.modulate.a, 1.0))
	assert(
		own_beast._sprite != null
		and is_equal_approx(own_beast._sprite.self_modulate.a, 0.60)
	)
	assert(
		own_beast._fire_sprite != null
		and is_equal_approx(own_beast._fire_sprite.self_modulate.a, 0.60),
		"divine-beast fire must fade without dimming the parent hint layer"
	)
	## Any skill submission breaks stealth uniformly; after the break enemies
	## can reselect the player (is_stealthed false). Summon-side break/visual
	## hooks are a recorded integration need (summon_actor.gd is exclusive).
	_reset_cast_state()
	assert(player.request_skill(_display("taoist.healing")))
	assert(not player.is_stealthed(), "skill submission must break stealth")
	game._process(0.016)
	assert(
		is_equal_approx(player.modulate.a, 1.0),
		"broken stealth must restore full alpha"
	)
	assert(
		not game._stealth_alpha_restore.has(player.get_instance_id()),
		"breaking stealth must clear the player alpha restore cache"
	)
	assert(own_summon.is_stealthed())
	## Physical attack submission also breaks stealth uniformly.
	_reset_cast_state()
	assert(
		game._try_release_skill(
			_display("taoist.mass_invisibility")
		) == &"accepted"
	)
	await get_tree().create_timer(1.0).timeout
	assert(player.is_stealthed())
	## Equipment-derived stealth is a second state source. Combat submission
	## must suppress visibility without deleting that effect or other effects.
	var had_equipment_stealth := PlayerState.computed_special_effects.has("stealth")
	var previous_equipment_stealth: Variant = PlayerState.computed_special_effects.get("stealth")
	PlayerState.computed_special_effects["stealth"] = {"slot": "左戒指", "item": "隐身戒指"}
	player.stealth_time = 5.0
	assert(player.is_stealthed())
	## The test freezes the player physics process, so the accepted cast's
	## action-lock timers never decay; clear them like every other
	## release-wait block before the next combat action can start.
	_reset_cast_state()
	assert(player.request_attack(false))
	assert(not player.is_stealthed(), "attack submission must break stealth")
	assert(PlayerState.has_special_effect("stealth"), "stealth equipment effect must remain registered")
	game._process(0.016)
	assert(is_equal_approx(player.modulate.a, 1.0))
	if had_equipment_stealth:
		PlayerState.computed_special_effects["stealth"] = previous_equipment_stealth
	else:
		PlayerState.computed_special_effects.erase("stealth")
	own_summon.stealth_remaining_seconds = 0.0
	own_beast.stealth_remaining_seconds = 0.0
	own_summon._update_stealth_visual()
	own_beast._update_stealth_visual()
	game._process(0.016)
	assert(is_equal_approx(own_summon.modulate.a, 1.0))
	assert(is_equal_approx(own_summon._sprite.self_modulate.a, 1.0))
	assert(is_equal_approx(own_beast.modulate.a, 1.0))
	assert(is_equal_approx(own_beast._sprite.self_modulate.a, 1.0))
	assert(is_equal_approx(own_beast._fire_sprite.self_modulate.a, 1.0))
	assert(not game._stealth_alpha_restore.has(own_summon.get_instance_id()))
	assert(not game._stealth_alpha_restore.has(own_beast.get_instance_id()))
	_reset_cast_state()

	## Single defence: only AC applies, player and own summon, 7x7 self center.
	PlayerState.learned_skills.erase(_display("taoist.magic_defense"))
	PlayerState.recalculate_stats()
	PlayerState._skill_progression.load_snapshot(PlayerState.learned_skills)
	assert(own_summon.owner_level == 21)
	assert(
		own_summon.summon_exp_level != own_summon.owner_level,
		"pet level must stay independent of the frozen owner level"
	)
	player.defense_buff = 0
	player.defense_buff_time = 0.0
	player.mac_buff = 0
	player.mac_buff_time = 0.0
	own_summon.clear_ac_buff()
	own_summon.clear_mac_buff()
	assert(game._try_release_skill(_display("taoist.defense")) == &"accepted")
	await get_tree().create_timer(1.0).timeout
	assert(player.defense_buff > 0 and player.defense_buff_time > 0.0)
	assert(own_summon.physical_defence_bonus() > 0)
	assert(
		own_summon.physical_defence_bonus() == 3,
		"defence value must use the summon owner level (21/7=3), not pet level"
	)
	assert(player.mac_buff == 0, "single AC defence must not grant MAC")
	assert(own_summon.magic_defence_bonus() == 0)
	other_owner.free()
	other_summon.free()
	far_summon.free()
	own_beast.free()
	own_summon.free()


func _verify_dual_defence_production() -> void:
	PlayerState.learned_skills[_display("taoist.magic_defense")] = 3
	PlayerState.recalculate_stats()
	## magic_defense base 3 + equipment 2 -> effective 5; defense stays 3.
	PlayerState.computed_stats["skill_level_affix"] = {
		"contributions": {"skill:taoist.magic_defense": 2},
	}
	player.defense_buff = 0
	player.defense_buff_time = 0.0
	player.mac_buff = 0
	player.mac_buff_time = 0.0
	_reset_cast_state()
	var pre_mp := player.current_mp
	assert(game._try_release_skill(_display("taoist.defense")) == &"accepted")
	assert(player.skill_cooldown_remaining_ms("taoist.defense") > 0)
	assert(player.skill_cooldown_remaining_ms("taoist.magic_defense") > 0)
	assert(
		player.skill_cooldown_remaining_ms("taoist.defense")
		== player.skill_cooldown_remaining_ms("taoist.magic_defense")
	)
	assert(player.current_mp == pre_mp, "MP commits at release, not at input")
	await get_tree().create_timer(1.0).timeout
	## defense rank 3 MP 8 + magic_defense rank 5 MP 12 = 20 once.
	assert(player.current_mp == pre_mp - 20)
	assert(player.defense_buff > 0 and player.mac_buff > 0)

	## Production-observable combined plan metadata through the real executor.
	var execution: Dictionary = game._execute_canonical_skill(
		_display("taoist.defense"),
		player.global_position,
		Vector2.RIGHT,
		0,
		{"release_id": "test:dual:plan"}
	)
	assert(bool(execution.get("accepted", false)))
	var plan: Dictionary = execution.get("canonical_plan", {})
	assert(plan.combined_skill_ids == ["taoist.magic_defense", "taoist.defense"])
	var resource_cost: Dictionary = plan.get("resource_cost", {})
	assert(int(resource_cost.get("mp_cost", 0)) == 20)
	var components: Array = resource_cost.get("mp_components", [])
	assert(components.size() == 2)
	assert(int(components[0].get("rank", 0)) == 5)
	assert(int(components[0].get("mp_cost", 0)) == 12)
	assert(int(components[1].get("rank", 0)) == 3)
	assert(int(components[1].get("mp_cost", 0)) == 8)

	## Same combination from the other button: one action, same sum, shared
	## cooldown, MP committed once.
	player.defense_buff = 0
	player.defense_buff_time = 0.0
	player.mac_buff = 0
	player.mac_buff_time = 0.0
	_reset_cast_state()
	pre_mp = player.current_mp
	assert(game._try_release_skill(_display("taoist.magic_defense")) == &"accepted")
	assert(
		player.skill_cooldown_remaining_ms("taoist.defense")
		== player.skill_cooldown_remaining_ms("taoist.magic_defense")
	)
	await get_tree().create_timer(1.0).timeout
	assert(player.current_mp == pre_mp - 20)
	assert(player.defense_buff > 0 and player.mac_buff > 0)

	## Only one skill learned: normal single-price defence, no combined fields.
	PlayerState.learned_skills.erase(_display("taoist.magic_defense"))
	PlayerState.recalculate_stats()
	PlayerState._skill_progression.load_snapshot(PlayerState.learned_skills)
	PlayerState.computed_stats["skill_level_affix"] = {"contributions": {}}
	player.defense_buff = 0
	player.defense_buff_time = 0.0
	player.mac_buff = 0
	player.mac_buff_time = 0.0
	var single_execution: Dictionary = game._execute_canonical_skill(
		_display("taoist.defense"),
		player.global_position,
		Vector2.RIGHT,
		0,
		{"release_id": "test:single:plan"}
	)
	assert(bool(single_execution.get("accepted", false)))
	var single_plan: Dictionary = single_execution.get("canonical_plan", {})
	assert(not single_plan.has("combined_skill_ids"))
	assert(
		int(single_plan.get("resource_cost", {}).get("mp_cost", 0)) == 8
	)
	assert(player.mac_buff == 0)


func _verify_rank_zero_dual_defence() -> void:
	## HardCore v2: base rank 0 is still learned; both rank-0 skills must form
	## the dual combination with rank-0 MP and a shared cooldown.
	PlayerState.learned_skills = {
		_display("taoist.magic_defense"): 0,
		_display("taoist.defense"): 0,
	}
	PlayerState.recalculate_stats()
	PlayerState._skill_progression.load_snapshot(PlayerState.learned_skills)
	PlayerState.computed_stats["skill_level_affix"] = {"contributions": {}}
	player.defense_buff = 0
	player.defense_buff_time = 0.0
	player.mac_buff = 0
	player.mac_buff_time = 0.0
	_reset_cast_state()
	var pre_mp := player.current_mp
	var result: StringName = game._try_release_skill(
		_display("taoist.magic_defense")
	)
	assert(result == &"accepted")
	assert(player.skill_cooldown_remaining_ms("taoist.magic_defense") > 0)
	assert(player.skill_cooldown_remaining_ms("taoist.defense") > 0)
	assert(
		player.skill_cooldown_remaining_ms("taoist.magic_defense")
		== player.skill_cooldown_remaining_ms("taoist.defense")
	)
	await get_tree().create_timer(1.0).timeout
	## rank 0 costs: magic_defense 2 + defense 2 = 4.
	assert(player.current_mp == pre_mp - 4)

	_reset_cast_state()
	var execution: Dictionary = game._execute_canonical_skill(
		_display("taoist.defense"),
		player.global_position,
		Vector2.RIGHT,
		0,
		{"release_id": "test:dual:rank0"}
	)
	assert(bool(execution.get("accepted", false)))
	var plan: Dictionary = execution.get("canonical_plan", {})
	assert(plan.combined_skill_ids == ["taoist.magic_defense", "taoist.defense"])
	var resource_cost: Dictionary = plan.get("resource_cost", {})
	assert(int(resource_cost.get("mp_cost", 0)) == 4)
	var components: Array = resource_cost.get("mp_components", [])
	assert(components.size() == 2)
	assert(int(components[0].get("rank", -1)) == 0)
	assert(int(components[1].get("rank", -1)) == 0)

	## Only one rank-0 skill learned: no combination, single rank-0 MP.
	PlayerState.learned_skills.erase(_display("taoist.magic_defense"))
	PlayerState._skill_progression.load_snapshot(PlayerState.learned_skills)
	PlayerState.recalculate_stats()
	var single_execution: Dictionary = game._execute_canonical_skill(
		_display("taoist.defense"),
		player.global_position,
		Vector2.RIGHT,
		0,
		{"release_id": "test:single:rank0"}
	)
	assert(bool(single_execution.get("accepted", false)))
	var single_plan: Dictionary = single_execution.get("canonical_plan", {})
	assert(not single_plan.has("combined_skill_ids"))
	assert(
		int(single_plan.get("resource_cost", {}).get("mp_cost", 0)) == 2
	)


func _verify_fractional_center_geometry() -> void:
	## Fractional caster ground position (0.6 GU): floor-based grid_tile gives
	## center tile (0,0). GameRoot target_tile must match the professional
	## contract so plan geometry, support_area_geometry and affected IDs agree.
	player.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		Vector2(0.6, 0.0)
	)
	_reset_cast_state()
	var inside_three := _make_summon(Vector2.ZERO, player)
	inside_three.global_position = (
		GroundUnit.ground_delta_gu_to_screen_delta_px(Vector2(1.6, 0.0))
	)
	inside_three.current_hp = inside_three.max_hp
	var outside_three := _make_summon(Vector2.ZERO, player)
	outside_three.global_position = (
		GroundUnit.ground_delta_gu_to_screen_delta_px(Vector2(2.2, 0.0))
	)
	outside_three.current_hp = outside_three.max_hp

	var invis_execution: Dictionary = game._execute_canonical_skill(
		_display("taoist.mass_invisibility"),
		player.global_position,
		Vector2.RIGHT,
		0,
		{"release_id": "test:fractional:invis"}
	)
	assert(bool(invis_execution.get("accepted", false)))
	var invis_plan: Dictionary = invis_execution.get("canonical_plan", {})
	var invis_geometry: Dictionary = invis_plan.get("support_area_geometry", {})
	assert(invis_geometry.center_tile == Vector2i(0, 0))
	assert(int(invis_geometry.get("cell_count", 0)) == 9)
	var invis_cells: Array = invis_plan.get("geometry_cells", [])
	assert(invis_cells.has(Vector2i(0, 0)))
	assert(not invis_cells.has(Vector2i(2, 0)))
	var invis_effects: Array = invis_execution.get("effects", [])
	var invis_target_ids: Array = invis_effects[0].get("target_instance_ids", [])
	assert(invis_target_ids.has(inside_three.get_instance_id()))
	assert(not invis_target_ids.has(outside_three.get_instance_id()))
	assert(player.is_stealthed())
	assert(inside_three.is_stealthed())
	assert(not outside_three.is_stealthed())
	player.stealth_time = 0.0
	inside_three.stealth_remaining_seconds = 0.0

	## 7x7 defence at the same fractional center: floor tile (0,0), radius 3.
	var inside_seven := _make_summon(Vector2.ZERO, player)
	inside_seven.global_position = (
		GroundUnit.ground_delta_gu_to_screen_delta_px(Vector2(3.6, 0.0))
	)
	inside_seven.current_hp = inside_seven.max_hp
	var outside_seven := _make_summon(Vector2.ZERO, player)
	outside_seven.global_position = (
		GroundUnit.ground_delta_gu_to_screen_delta_px(Vector2(4.2, 0.0))
	)
	outside_seven.current_hp = outside_seven.max_hp
	var defence_execution: Dictionary = game._execute_canonical_skill(
		_display("taoist.magic_defense"),
		player.global_position,
		Vector2.RIGHT,
		0,
		{"release_id": "test:fractional:defence"}
	)
	assert(bool(defence_execution.get("accepted", false)))
	var defence_plan: Dictionary = defence_execution.get("canonical_plan", {})
	var defence_geometry: Dictionary = defence_plan.get(
		"support_area_geometry",
		{}
	)
	assert(defence_geometry.center_tile == Vector2i(0, 0))
	assert(int(defence_geometry.get("cell_count", 0)) == 49)
	var defence_cells: Array = defence_plan.get("geometry_cells", [])
	assert(defence_cells.has(Vector2i(0, 0)))
	assert(not defence_cells.has(Vector2i(4, 0)))
	var defence_effects: Array = defence_execution.get("effects", [])
	var defence_target_ids: Array = []
	for raw_effect: Variant in defence_effects:
		if raw_effect is Dictionary:
			var effect: Dictionary = raw_effect
			if not effect.get("targets", []).is_empty():
				for raw_entry: Variant in effect.get("targets", []):
					if raw_entry is Dictionary:
						defence_target_ids.append(
							int((raw_entry as Dictionary).get(
								"target_instance_id",
								0
							))
						)
			else:
				defence_target_ids.append(
					int(effect.get("target_instance_id", 0))
				)
	assert(defence_target_ids.has(inside_seven.get_instance_id()))
	assert(not defence_target_ids.has(outside_seven.get_instance_id()))
	inside_three.free()
	outside_three.free()
	inside_seven.free()
	outside_seven.free()


func _verify_player_defence_separation() -> void:
	player.defense_min = 0
	player.defense_max = 0
	player.defense_buff = 0
	player.defense_buff_time = 0.0
	player.mac_buff = 0
	player.mac_buff_time = 0.0
	player.current_hp = 100
	player.apply_ac_buff(10.0, 10)
	player.take_damage(15)
	assert(player.current_hp == 95, "AC buff must reduce physical damage")

	player.current_hp = 100
	player.apply_mac_buff(10.0, 50)
	player.defense_buff = 0
	player.defense_buff_time = 0.0
	player.take_damage(15)
	assert(player.current_hp == 85, "MAC buff must not reduce physical damage")

	player.mac_buff = 0
	player.mac_buff_time = 0.0
	PlayerState.computed_stats["magic_defense_min"] = 2
	PlayerState.computed_stats["magic_defense_max"] = 2
	player.current_hp = 100
	player.apply_mac_buff(10.0, 6)
	var resolution := player.take_direct_spell_damage(
		"wizard.fireball",
		20,
		1,
		2
	)
	assert(int(resolution.get("mac_buff_applied", 0)) == 6)
	assert(int(resolution.get("magic_defense_min", 0)) == 8)
	assert(int(resolution.get("magic_defense_roll", -1)) == 8)
	assert(int(resolution.get("applied_damage", 0)) == 12)
	assert(player.current_hp == 88)
	assert(
		int(PlayerState.computed_stats.get("magic_defense_min", 0)) == 2,
		"MAC buff must not mutate computed_stats"
	)

	## Non-zero base range: 3..7 + 5 -> exactly 8..12 (no double-add).
	player.mac_buff = 0
	player.mac_buff_time = 0.0
	PlayerState.computed_stats["magic_defense_min"] = 3
	PlayerState.computed_stats["magic_defense_max"] = 7
	player.current_hp = 100
	player.apply_mac_buff(10.0, 5)
	var range_resolution := player.take_direct_spell_damage(
		"wizard.fireball",
		20,
		1,
		9
	)
	assert(int(range_resolution.get("mac_buff_applied", 0)) == 5)
	assert(int(range_resolution.get("magic_defense_min", 0)) == 8)
	assert(int(range_resolution.get("magic_defense_max", 0)) == 12)
	assert(int(range_resolution.get("magic_defense_roll", -1)) == 9)
	assert(int(range_resolution.get("final_damage", 0)) == 11)
	assert(int(range_resolution.get("applied_damage", 0)) == 11)
	assert(player.current_hp == 89)
	assert(
		int(PlayerState.computed_stats.get("magic_defense_min", 0)) == 3
		and int(PlayerState.computed_stats.get("magic_defense_max", 0)) == 7
	)

	## Fixed base 5..5 + 5 -> exactly 10..10.
	PlayerState.computed_stats["magic_defense_min"] = 5
	PlayerState.computed_stats["magic_defense_max"] = 5
	player.current_hp = 100
	var fixed_resolution := player.take_direct_spell_damage(
		"wizard.fireball",
		20,
		1,
		10
	)
	assert(int(fixed_resolution.get("magic_defense_min", 0)) == 10)
	assert(int(fixed_resolution.get("magic_defense_max", 0)) == 10)
	assert(int(fixed_resolution.get("magic_defense_roll", -1)) == 10)
	assert(int(fixed_resolution.get("final_damage", 0)) == 10)
	assert(int(fixed_resolution.get("applied_damage", 0)) == 10)
	assert(player.current_hp == 90)
	assert(
		int(PlayerState.computed_stats.get("magic_defense_min", 0)) == 5
		and int(PlayerState.computed_stats.get("magic_defense_max", 0)) == 5
	)

	## Reliable refresh: weaker/shorter refreshes never downgrade.
	player.defense_buff = 0
	player.defense_buff_time = 0.0
	player.mac_buff = 0
	player.mac_buff_time = 0.0
	player.apply_ac_buff(10.0, 10)
	player.apply_ac_buff(5.0, 5)
	assert(player.defense_buff == 10)
	assert(is_equal_approx(player.defense_buff_time, 10.0))
	player.apply_mac_buff(8.0, 8)
	player.apply_mac_buff(3.0, 3)
	assert(player.mac_buff == 8)
	assert(is_equal_approx(player.mac_buff_time, 8.0))
	var snapshot := player.defence_buff_snapshot()
	assert(int(snapshot.get("ac_bonus", 0)) == 10)
	assert(int(snapshot.get("mac_bonus", 0)) == 8)


func _make_summon(
	ground_offset_gu: Vector2,
	owner: PlayerCharacter,
	owner_level_value := 19,
	maximum_pet_level := 1,
	stable_skill_id := "taoist.summon_skeleton"
) -> SummonActor:
	var summon := SummonActor.new()
	summon.setup(
		owner,
		ProfessionRules.skill_display_name(stable_skill_id),
		1,
		0,
		stable_skill_id,
		owner_level_value,
		maximum_pet_level
	)
	summon.configure_runtime_map_projection(
		-1,
		Callable(self, "_ground_to_screen"),
		GroundUnit.screen_delta_px_to_ground_delta_gu
	)
	summon.set_physics_process(false)
	summon.global_position = _screen_at(ground_offset_gu)
	game.add_child(summon)
	summon.current_hp = summon.max_hp
	return summon


func _screen_at(ground_offset_gu: Vector2) -> Vector2:
	return player.global_position + (
		GroundUnit.ground_delta_gu_to_screen_delta_px(ground_offset_gu)
	)


func _reset_cast_state() -> void:
	player._skill_cooldown_remaining.clear()
	player._attack_timer = 0.0
	player._attack_action_timer = 0.0
	player.current_mp = 999


func _display(stable_skill_id: String) -> String:
	return ProfessionRules.skill_display_name(stable_skill_id)
