extends "res://tests/hc_monster_ai/test_support.gd"

const GU := preload("res://scripts/ground_unit_space.gd")

class RootProbe:
	extends "res://scripts/game_root.gd"
	var projection_calls := 0
	func _ready() -> void:
		pass
	func _canonical_screen_px_to_ground_gu(point: Vector2) -> Vector2:
		projection_calls += 1
		return GU.screen_delta_px_to_ground_delta_gu(point)
	func _canonical_ground_gu_to_screen_px(point: Vector2) -> Vector2:
		return GU.ground_delta_gu_to_screen_delta_px(point)

class HintHUD:
	extends GameHUD
	var last_error := ""
	func _ready() -> void:
		pass
	func show_error_message(message: String, _duration := 2.0) -> void:
		last_error = message

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "法师"
	PlayerState.level = 50
	PlayerState.learned_skills = {"火球术": 3, "雷电术": 3, "火墙": 3, "魔法盾": 3}
	PlayerState.recalculate_stats()
	var game := RootProbe.new()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(game)
	game.current_map_id = 1
	game._zone_generation = 1
	game.hud = HintHUD.new()
	game._compile_active_safe_zones([{"shape": "circle", "center_ground_gu": Vector2(20, 20), "radius_gu": 0.5, "blocks_monster_damage": true, "blocks_monster_entry": true}])
	var caster := PlayerCharacter.new()
	add_child(caster)
	caster.set_physics_process(false)
	caster.global_position = GU.ground_delta_gu_to_screen_delta_px(Vector2(20, 20))
	caster.current_mp = 1000
	game.player = caster
	caster.hc_world_skill_preflight = Callable(game, "_hc_skill_preflight")
	var mp := caster.current_mp
	var timer := caster._attack_timer
	for skill_name in ["火球术", "火墙", "雷电术"]:
		check(game._try_release_skill(skill_name) == &"rejected", "request-" + skill_name, "Safe-zone submission rejects before target selection and cost")
		check(game.hud.last_error.contains("安全区"), "hint-" + skill_name, "Explicit safe-zone rejection hint")
		check(not caster._request_active_skill(skill_name), "player-entry-" + skill_name, "Direct player cast entry honors the world safe-zone gate")
		var result: Dictionary = game._execute_canonical_skill(skill_name, caster.global_position, Vector2.RIGHT, 100)
		check(result.get("reason") == "caster_in_safe_zone", "release-" + skill_name, "Authoritative release rechecks the caster's live zone")
	check(caster.current_mp == mp and caster._attack_timer == timer and not caster._pending_combat_action_active, "no-commit", "Rejected skills spend no MP/cooldown/action")
	check(caster._request_active_skill("魔法盾"), "self-buff", "Self shield is usable in a safe zone")
	for skill_id in ["taoist.summon_skeleton", "taoist.healing", "wizard.teleport"]:
		check(game._hc_skill_preflight(skill_id, 0), "untargeted-" + skill_id, "Non-hostile-lock skill remains allowed")
	# Dungeon maps have valid empty authored zones: even moving the player does
	# not project/cache/scan safe-zone geometry. Then restore the live town data.
	game._compile_active_safe_zones([])
	game.projection_calls = 0
	for index in range(1000):
		caster.global_position += Vector2.ONE
		check(not game._player_inside_active_safe_zone(), "dungeon-%d" % index, "Empty map has no protected position")
	check(game.projection_calls == 0, "dungeon-no-projection", "Empty maps bypass safe-zone projection and point cache entirely")
	game._compile_active_safe_zones([{"shape": "circle", "center_ground_gu": GU.screen_delta_px_to_ground_delta_gu(caster.global_position), "radius_gu": 0.5}])
	check(game._player_inside_active_safe_zone(), "town-reentry", "Town safe zone works after an empty-map transition")
	game._safe_zone_context.valid = false
	check(game._player_inside_active_safe_zone(), "invalid-fail-closed", "Malformed map context never becomes the empty-map fast path")
	game.hud.free()
	game._combat_runtime.free()
	game.free()
	caster.queue_free()
	await get_tree().process_frame
	finish("safe_zone_skill_gate")
