extends Node2D

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

var _blocked_ground_gu := Vector2.INF
var _projectile_descriptors: Array[Dictionary] = []
var _magic_descriptors: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	await _run_map_query_gate()
	await _run_physics_gate_without_environment_provider()
	await _run_delayed_melee_gate()
	print(
		"MONSTER_ATTACK_COLLISION_GATE_PASS "
		+ "map_query=melee,physical_projectile,target_magic "
		+ "physics_world_ray=melee,physical_projectile,target_magic "
		+ "clear_release=melee,physical_projectile,target_magic "
		+ "delayed_melee_wall_recheck=1"
	)
	get_tree().quit(0)


func _run_map_query_gate() -> void:
	var melee_player := _make_player(Vector2(1.0, 0.0))
	var melee := await _make_attacker(64, melee_player)
	_blocked_ground_gu = Vector2(0.5, 0.0)
	var melee_hp_before := melee_player.current_hp
	assert(
		not melee._attack_engagement_ready(
			melee_player,
			Vector2(1.0, 0.0),
			1.0,
			melee._contact_distance_gu_to_target(melee_player),
			melee.attack_range_gu,
		),
		"map query wall must close ordinary melee engagement",
	)
	melee._deal_melee_hit(melee_player, 7)
	assert(melee_player.current_hp == melee_hp_before, "map wall leaked melee damage")
	_blocked_ground_gu = Vector2.INF
	melee._deal_melee_hit(melee_player, 7)
	assert(melee_player.current_hp < melee_hp_before, "clear map path did not allow melee damage")

	var projectile_player := _make_player(Vector2(4.0, 0.0))
	var projectile := await _make_attacker(150, projectile_player)
	projectile.ranged_projectile_requested.connect(_capture_projectile_descriptor)
	_blocked_ground_gu = Vector2(2.0, 0.0)
	var projectile_hp_before := projectile_player.current_hp
	assert(
		not projectile._attack_engagement_ready(
			projectile_player,
			Vector2(4.0, 0.0),
			4.0,
			projectile._contact_distance_gu_to_target(projectile_player),
			projectile.attack_range_gu,
		),
		"map query wall must close physical projectile engagement",
	)
	assert(not projectile._launch_physical_projectile(projectile_player, 7))
	assert(projectile._pending_attack_release_record.is_empty())
	assert(projectile_player.current_hp == projectile_hp_before)
	_blocked_ground_gu = Vector2.INF
	assert(projectile._launch_physical_projectile(projectile_player, 7))
	assert(_projectile_descriptors.size() == 1, "clear physical path did not emit descriptor")
	projectile._update_pending_attack(2.0)
	assert(projectile_player.current_hp < projectile_hp_before, "clear physical path did not settle damage")

	var magic_player := _make_player(Vector2(2.0, 0.0))
	var mage := await _make_attacker(220, magic_player)
	mage.target_magic_requested.connect(_capture_magic_descriptor)
	_blocked_ground_gu = Vector2(1.0, 0.0)
	var magic_hp_before := magic_player.current_hp
	assert(
		not mage._attack_engagement_ready(
			magic_player,
			Vector2(2.0, 0.0),
			2.0,
			mage._contact_distance_gu_to_target(magic_player),
			mage.attack_range_gu,
		),
		"map query wall must close target magic engagement",
	)
	assert(not mage._launch_target_magic(magic_player, 7))
	assert(mage._pending_attack_release_record.is_empty())
	_blocked_ground_gu = Vector2.INF
	assert(mage._launch_target_magic(magic_player, 7))
	assert(_magic_descriptors.size() == 1, "clear magic path did not emit descriptor")
	mage._update_pending_attack(1.0)
	assert(magic_player.current_hp < magic_hp_before, "clear magic path did not settle magic damage")

	melee.queue_free()
	melee_player.queue_free()
	projectile.queue_free()
	projectile_player.queue_free()
	mage.queue_free()
	magic_player.queue_free()
	await get_tree().process_frame


func _run_physics_gate_without_environment_provider() -> void:
	var wall := StaticBody2D.new()
	wall.name = "WorldAttackRayWall"
	wall.collision_layer = WorldSpatialRulesScript.WORLD_LAYER
	wall.collision_mask = 0
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(18.0, 18.0)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	add_child(wall)

	var melee_player := _make_player(Vector2(1.0, 0.0))
	var melee := await _make_attacker(64, melee_player)
	melee.environment_blocker = null
	wall.position = _ground_to_screen(Vector2(0.5, 0.0))
	await get_tree().physics_frame
	var melee_hp_before := melee_player.current_hp
	assert(not melee._attack_world_path_is_clear_for_target(melee_player))
	melee._deal_melee_hit(melee_player, 7)
	assert(melee_player.current_hp == melee_hp_before, "WORLD ray leaked melee damage")

	var projectile_player := _make_player(Vector2(4.0, 0.0))
	var projectile := await _make_attacker(150, projectile_player)
	projectile.environment_blocker = null
	wall.position = _ground_to_screen(Vector2(2.0, 0.0))
	await get_tree().physics_frame
	assert(not projectile._launch_physical_projectile(projectile_player, 7))
	assert(projectile._pending_attack_release_record.is_empty())

	var magic_player := _make_player(Vector2(2.0, 0.0))
	var mage := await _make_attacker(220, magic_player)
	mage.environment_blocker = null
	wall.position = _ground_to_screen(Vector2(1.0, 0.0))
	await get_tree().physics_frame
	assert(not mage._launch_target_magic(magic_player, 7))
	assert(mage._pending_attack_release_record.is_empty())

	wall.queue_free()
	await get_tree().physics_frame
	melee_player.current_hp = melee_player.max_hp
	melee._deal_melee_hit(melee_player, 7)
	assert(melee_player.current_hp < melee_player.max_hp, "clear WORLD ray did not allow melee")

	var projectile_hp_before := projectile_player.current_hp
	assert(projectile._launch_physical_projectile(projectile_player, 7))
	projectile._update_pending_attack(2.0)
	assert(projectile_player.current_hp < projectile_hp_before, "clear WORLD ray did not settle projectile")

	var magic_hp_before := magic_player.current_hp
	assert(mage._launch_target_magic(magic_player, 7))
	mage._update_pending_attack(1.0)
	assert(magic_player.current_hp < magic_hp_before, "clear WORLD ray did not settle magic")

	melee.queue_free()
	melee_player.queue_free()
	projectile.queue_free()
	projectile_player.queue_free()
	mage.queue_free()
	magic_player.queue_free()
	await get_tree().process_frame


func _run_delayed_melee_gate() -> void:
	var player := _make_player(Vector2(1.0, 0.0))
	var boss := await _make_attacker(56, player)
	boss.environment_blocker = self
	_blocked_ground_gu = Vector2.INF
	var hp_before := player.current_hp
	boss._pending_attack_time = 0.1
	boss._pending_attack_target = player
	boss._pending_attack_damage = 7
	boss._pending_attack_release_record = {}
	_blocked_ground_gu = Vector2(0.5, 0.0)
	boss._update_pending_attack(0.1)
	assert(player.current_hp == hp_before, "delayed melee ignored a wall added before settlement")

	boss.queue_free()
	player.queue_free()
	await get_tree().process_frame
	_blocked_ground_gu = Vector2.INF


func _make_player(ground_gu: Vector2) -> PlayerCharacter:
	var player := PlayerCharacter.new()
	player.global_position = _ground_to_screen(ground_gu)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_physics_process(false)
	add_child(player)
	player.max_hp = 1000
	player.current_hp = 1000
	player.defense_min = 0
	player.defense_max = 0
	return player


func _make_attacker(monster_id: int, player: PlayerCharacter) -> EnemyActor:
	var attacker := EnemyActor.new()
	attacker.global_position = Vector2.ZERO
	attacker.setup(GameData.get_monster_by_id(monster_id), player, false)
	attacker.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground"),
	)
	attacker.environment_blocker = self
	attacker.process_mode = Node.PROCESS_MODE_DISABLED
	attacker.set_physics_process(false)
	add_child(attacker)
	await get_tree().process_frame
	# setup() resolves an overlap against close players. These tests exercise
	# the attack release gate directly, so keep the source footpoint canonical
	# at the origin after the actor has entered the tree.
	attacker.global_position = Vector2.ZERO
	attacker._attack_timer = 999.0
	attacker._pending_attack_time = -1.0
	attacker._pending_attack_target = null
	attacker._pending_attack_damage = 0
	attacker._pending_attack_release_record = {}
	return attacker


func is_environment_point_blocked(world_px: Vector2) -> bool:
	return (
		_blocked_ground_gu != Vector2.INF
		and world_px.distance_to(_ground_to_screen(_blocked_ground_gu)) <= 2.0
	)


func _capture_projectile_descriptor(descriptor: Dictionary) -> void:
	_projectile_descriptors.append(descriptor)


func _capture_magic_descriptor(descriptor: Dictionary) -> void:
	_magic_descriptors.append(descriptor)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(value)
