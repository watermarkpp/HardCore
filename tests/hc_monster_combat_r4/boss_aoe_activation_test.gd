extends Node

## Capability-seam integration fixture for generic boss circle/cone AOE.
## The seam is intentionally explicit: production rules remain disabled unless
## an exact test capability enables the authored specialSkill dictionary.
const Ground := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://tests/helpers/monster_open_terrain_test_fixture.gd")

const MAP_ID := 9204
const CENTER := Terrain.CENTER_GROUND_GU

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _ground_to_screen(value: Vector2) -> Vector2:
	return Ground.ground_delta_gu_to_screen_delta_px(value)

func _screen_to_ground(value: Vector2) -> Vector2:
	return Ground.screen_delta_px_to_ground_delta_gu(value)

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	await _run_circle_case()
	await _run_cone_case()
	await _run_boss_struck_continuation_case()
	print("R4_BOSS_AOE_ACTIVATION_PASS" if failures.is_empty() else "R4_BOSS_AOE_ACTIVATION_FAIL %s" % [failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _run_circle_case() -> void:
	var player := await _new_player()
	var boss := await _new_boss(player)
	_prepare_case(boss, player, "circle", Vector2(2.0, 0.0))
	var hp_before := player.current_hp
	boss._update_boss_skill(0.01, 2.0)
	var hp_after_activation := player.current_hp
	_check(hp_after_activation < hp_before, "circle must settle HP at activation")
	_check(player.control_time > 0.0, "circle status must apply at activation")
	_check(boss._boss_warning > 0.0, "circle warning must remain presentation state")
	player.global_position = _ground_to_screen(CENTER + Vector2(8.0, 8.0))
	boss._update_boss_skill(1.0, 12.0)
	_check(player.current_hp == hp_after_activation, "circle warning cleanup must not replay or revoke HP")
	_check(boss._boss_skill_cooldown > 0.0, "circle cooldown must start after warning cleanup")
	boss.queue_free()
	player.queue_free()
	await get_tree().process_frame

func _run_cone_case() -> void:
	var player := await _new_player()
	var boss := await _new_boss(player)
	_prepare_case(boss, player, "cone", Vector2(2.0, 0.0))
	var control_before := player.control_time
	var hp_before := player.current_hp
	boss._update_boss_skill(0.01, 2.0)
	var hp_after_activation := player.current_hp
	_check(hp_after_activation < hp_before, "cone must settle HP at activation")
	_check(player.control_time <= control_before, "cone must preserve circle-only status distinction")
	_check(boss._boss_warning > 0.0, "cone warning must remain presentation state")
	player.global_position = _ground_to_screen(CENTER + Vector2(-8.0, -8.0))
	boss._update_boss_skill(1.0, 12.0)
	_check(player.current_hp == hp_after_activation, "cone warning cleanup must not replay or revoke HP")
	_check(boss._boss_skill_cooldown > 0.0, "cone cooldown must start after warning cleanup")
	boss.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _run_boss_struck_continuation_case() -> void:
	# This is a real EnemyActor physics path, not a direct warning helper call.
	# The capability seam deliberately makes the authored body action (200 ms)
	# shorter than the already-committed 850 ms warning. A positive hit arrives
	# during that body action; once the body closes, the hit animation must pause
	# movement/cooldown while the committed warning continues exactly once per
	# owner tick. Activation damage must remain settled exactly once.
	var player := await _new_player()
	var boss := await _new_boss(player)
	_prepare_case(boss, player, "circle", Vector2(2.0, 0.0))
	var hp_before := player.current_hp
	boss._update_boss_skill(0.01, 2.0)
	var hp_after_activation := player.current_hp
	_check(hp_after_activation < hp_before, "physics continuation activation must settle HP")
	var warning_before_physics := boss._boss_warning
	_check(is_instance_valid(boss.visual), "boss physics continuation requires production visual")
	if is_instance_valid(boss.visual):
		var boss_hp_before := boss.current_hp
		boss.take_damage(1, player, {"damage_channel": "physical"})
		_check(boss.current_hp == boss_hp_before - 1, "boss continuation hit must enter the real HP/struck chain")
	# First tick remains inside the committed 200 ms body action. The warning
	# is advanced by the committed-window owner and the hit cannot start yet.
	boss._physics_process(0.1)
	# Second tick closes the logical body action; the warning is still active.
	boss._physics_process(0.1)
	var warning_before_hit := boss._boss_warning
	var cooldown_before_hit := boss._boss_skill_cooldown
	var hp_before_hit := player.current_hp
	# Third tick starts the queued hit after the body action. The production
	# continuation contract advances the already-committed warning once while
	# the struck pause is active, without re-admitting or re-settling the skill.
	boss._physics_process(0.1)
	_check(
		boss._boss_warning < warning_before_hit,
		"committed boss warning must continue during struck pause"
	)
	_check(
		boss._boss_warning <= warning_before_hit - 0.099,
		"committed boss warning must consume one real physics tick during struck"
	)
	_check(player.current_hp == hp_before_hit, "boss struck continuation must not settle HP twice")
	_check(
		boss._boss_skill_cooldown == cooldown_before_hit,
		"boss struck continuation must not restart skill cooldown early"
	)
	_check(
		boss._boss_warning < warning_before_physics,
		"boss warning must advance on the real owner physics path"
	)
	boss.queue_free()
	player.queue_free()
	await get_tree().process_frame

func _new_player() -> PlayerCharacter:
	var player := PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	add_child(player)
	await get_tree().process_frame
	# Player ready may rebuild computed stats, so pin the formal fixture inputs
	# only after it has entered the tree.
	player.max_hp = 100000
	player.current_hp = player.max_hp
	player.max_mp = 0
	player.current_mp = 0
	player.damage_reduction = 0.0
	PlayerState.computed_stats["anti_magic_points"] = 0
	PlayerState.computed_stats["magic_defense_min"] = 0
	PlayerState.computed_stats["magic_defense_max"] = 0
	player.global_position = _ground_to_screen(CENTER + Vector2(2.0, 0.0))
	player.set_physics_process(false)
	return player

func _new_boss(player: PlayerCharacter) -> EnemyActor:
	var boss := EnemyActor.new()
	boss.setup(GameData.get_monster_by_id(76).duplicate(true), player, true)
	boss.set_meta("runtime_map_id", MAP_ID)
	boss.set_meta("zone_generation", 1)
	boss.configure_runtime_map_projection(MAP_ID, _ground_to_screen, _screen_to_ground)
	boss.configure_terrain_navigation_context(Terrain.build(MAP_ID))
	boss.global_position = _ground_to_screen(CENTER)
	boss.attack_min = 11
	boss.attack_max = 11
	boss.set_physics_process(false)
	add_child(boss)
	await get_tree().process_frame
	return boss

func _prepare_case(boss: EnemyActor, player: PlayerCharacter, shape: String, target_offset: Vector2) -> void:
	player.global_position = _ground_to_screen(CENTER + target_offset)
	player.current_hp = player.max_hp
	boss.target = player
	boss.primary_target = player
	boss.boss_rule = {
		"specialSkill": {
			"enabled": true,
			"shape": shape,
			"targetMode": "current_target",
			"radius_gu": 5.0,
			"trigger_range_gu": 8.0,
			"warningSeconds": 0.85,
			"animationSeconds": 0.2,
			"cooldownSeconds": 4.6,
			"damageMultiplier": 1,
			"statusChance": 1.0 if shape == "circle" else 0.0,
			"controlWeight": 1 if shape == "circle" else 0,
			"controlSeconds": 2.5,
			"coneHalfAngleRadians": 0.4,
		},
	}
	# Exact capability seam: generic boss rules are disabled by default and are
	# enabled here only for this integration contract test.
	boss._boss_skill_enabled = true
	boss._boss_phase_two = false
	boss._boss_skill_cooldown = 0.0
	boss._boss_warning = 0.0
