extends Node2D
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.computed_stats["anti_magic_points"] = 0
	PlayerState.computed_stats["magic_defense_min"] = 0
	PlayerState.computed_stats["magic_defense_max"] = 0
	var near := _make_player(Vector2(11.5, 10.5))
	var spider := _make_actor(183, near, Vector2(10.5, 10.5))
	await get_tree().process_frame
	var near_hp := near.current_hp
	spider.target = near
	spider.attack_min = 30
	spider.attack_max = 30
	spider._attack_timer = 0.0
	spider._physics_process(0.01)
	assert(near.current_hp < near_hp, "ID183 adjacent target did not receive damage")
	assert(spider.current_hp == 0 and spider._death_pending, "ID183 did not enter normal self-death")
	var settled_hp := near.current_hp
	spider._physics_process(0.5)
	assert(near.current_hp == settled_hp, "ID183 settled its self-detonation twice")
	spider.queue_free(); near.queue_free()
	await get_tree().process_frame

	var remote := _make_player(Vector2(20.0, 20.0))
	var remote_spider := _make_actor(183, remote, Vector2(10.5, 10.5))
	remote_spider.target = remote
	remote_spider.attack_min = 30
	remote_spider.attack_max = 30
	remote_spider._attack_timer = 0.0
	var remote_hp := remote.current_hp
	remote_spider._physics_process(0.01)
	assert(remote.current_hp == remote_hp, "ID183 damaged a non-adjacent target")
	remote_spider.queue_free(); remote.queue_free()
	await get_tree().process_frame
	print("SPECIAL_EXPLOSION_GAP_PASS")
	get_tree().quit(0)

func _make_player(ground: Vector2) -> PlayerCharacter:
	var p := PlayerCharacter.new()
	p.global_position = _ground_to_screen(ground)
	p.set_meta("runtime_map_id", 1)
	p.set_meta("safe_zones", [])
	p.max_hp = 1000; p.current_hp = 1000
	p.defense_min = 0; p.defense_max = 0
	add_child(p); p.set_physics_process(false)
	return p

func _make_actor(id: int, target: PlayerCharacter, ground: Vector2) -> EnemyActor:
	var actor := EnemyActor.new()
	actor.setup(GameData.get_monster_by_id(id), target, false)
	actor.configure_runtime_map_projection(1, Callable(self, "_ground_to_screen"), Callable(self, "_screen_to_ground"))
	actor.configure_terrain_navigation_context({})
	actor.global_position = _ground_to_screen(ground)
	add_child(actor); actor.set_physics_process(false)
	return actor

func _ground_to_screen(v: Vector2) -> Vector2: return GroundUnit.ground_delta_gu_to_screen_delta_px(v)
func _screen_to_ground(v: Vector2) -> Vector2: return GroundUnit.screen_delta_px_to_ground_delta_gu(v)
