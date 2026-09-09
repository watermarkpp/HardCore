extends "res://tests/hc_monster_ai/test_support.gd"
const GU := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")

class RootProbe:
	extends "res://scripts/game_root.gd"
	func _ready() -> void:
		pass
	func _canonical_screen_px_to_ground_gu(point: Vector2) -> Vector2:
		return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(point)
	func _canonical_ground_gu_to_screen_px(point: Vector2) -> Vector2:
		return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(point)

class WorldProbe:
	extends Node
	var blocked := false
	func is_environment_segment_blocked_ground(_a: Vector2,_b: Vector2,_step: float) -> bool:
		return blocked
	func environment_collision_revision() -> int:
		return 2 if blocked else 1

func ground_to_screen(point: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(point)

func screen_to_ground(point: Vector2) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(point)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode=true
	var root:=RootProbe.new()
	root.set_process(false)
	root.set_physics_process(false)
	# Do not add GameRoot: booting a full map is a separate integration test.
	root.current_map_id=1
	root._zone_generation=1
	root.background=WorldBackground.new()
	var player:=PlayerCharacter.new()
	player.global_position=ground_to_screen(Vector2(20,20))
	player.set_meta("runtime_map_id",1)
	add_child(player)
	player.set_physics_process(false)
	root.player=player
	var world:=WorldProbe.new()
	add_child(world)
	var victim:=EnemyActor.new()
	victim.setup(GameData.get_monster_by_id(64),player,false)
	victim.global_position=ground_to_screen(Vector2(24,20))
	victim.configure_runtime_map_projection(1,Callable(self,"ground_to_screen"),Callable(self,"screen_to_ground"))
	victim.set_meta("zone_generation",1)
	victim.set_meta("safe_zones",[])
	victim.environment_blocker=world
	add_child(victim)
	victim.set_physics_process(false)
	player.hc_world_skill_preflight=Callable(root,"_hc_skill_preflight")
	world.blocked=true
	var mp:=player.current_mp
	var timer:=player._attack_timer
	check(not player._request_active_skill("雷电术",victim.get_instance_id()),"A30","World LOS rejects before action/cooldown/MP commitment")
	check(player.current_mp==mp and player._attack_timer==timer,"A30-resource","Blocked preflight leaves resources and action timer unchanged")
	world.blocked=false
	check(root._hc_lightning_clear(victim,player.global_position),"A33","Lightning does not require or use the melee front-body index")
	world.blocked=true
	check(not root._hc_lightning_clear(victim,player.global_position),"A31-helper","World change is not hidden by stale LOS cache")
	world.blocked=false
	victim.set_meta("zone_generation",2)
	check(not root._hc_lightning_clear(victim,player.global_position),"A22-lightning","Old map generation cannot receive lightning")
	# Source wiring checks supplement the runtime helper/preflight checks; they
	# are explicitly not an end-to-end canonical-plan/animation assertion.
	var source:=FileAccess.get_file_as_string("res://scripts/game_root.gd")
	check(source.contains('context["line_of_sight"] = usable_target and _hc_lightning_clear(target, origin)'),"A34-source","Authoritative LOS follows context overrides")
	check(source.contains('if stable_skill_id == "wizard.lightning" and not _hc_lightning_clear(cast_target, origin):'),"A31-source","Canonical execution gates actual target")
	check(source.contains('if stable_skill_id == "wizard.lightning" and not _hc_lightning_clear(enemy, origin):'),"A32-source","Damage owner checks world LOS without a second timer")
	root.background.free()
	root._combat_runtime.free()
	root.free()
	finish("lightning")
