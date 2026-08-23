extends Node

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SnapshotScript := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const ProjectileEffectScript := preload(
	"res://scripts/monster_ranged_projectile_effect.gd"
)

var _descriptors: Array[Dictionary] = []
var _blocked_world_px := Vector2.INF


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_assert_authoritative_archer_profiles()

	var player := PlayerCharacter.new()
	player.global_position = _ground_to_screen(Vector2(4.0, 0.0))
	player.set_physics_process(false)
	add_child(player)
	player.max_hp = 1000
	player.current_hp = 1000
	player.defense_min = 0
	player.defense_max = 0

	var attacker := EnemyActor.new()
	attacker.global_position = Vector2.ZERO
	attacker.setup(GameData.get_monster_by_id(150), player, false)
	attacker.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground"),
	)
	attacker.environment_blocker = self
	attacker.ranged_projectile_requested.connect(_capture_descriptor)
	add_child(attacker)
	attacker.set_physics_process(false)
	await get_tree().process_frame
	attacker.attack_min = 7
	attacker.attack_max = 7
	attacker._attack_timer = 0.0

	var hp_before := player.current_hp
	attacker._physics_process(0.01)
	assert(_descriptors.size() == 1, "archer release must emit exactly one projectile")
	assert(player.current_hp == hp_before, "projectile must not deal instant melee damage")
	assert(attacker._pending_attack_release_record.get("kind", "") == "physical_projectile")
	var descriptor := _descriptors[0]
	assert(str(descriptor.get("effect_id", "")) == ProjectileEffectScript.EFFECT_ID)
	assert(str(descriptor.get("damage_owner", "")) == "enemy.physical_projectile_release")
	var snapshot: Dictionary = descriptor.get("footprint_snapshot", {})
	assert(str(snapshot.get("shape_type", "")) == SnapshotScript.SHAPE_SWEPT_CAPSULE_PATH)
	assert(str(snapshot.get("projection_relationship_id", "")) == "projectile_sweep")
	assert(is_equal_approx(float(descriptor.get("duration_seconds", 0.0)), 0.8))
	var effect: Node2D = _find_projectile_effect()
	assert(effect != null, "accepted projectile release did not create its visual")
	effect.call("_process", 0.4)
	assert(is_equal_approx(float(effect.call("progress_ratio")), 0.5))

	var pending_before := attacker._pending_attack_time
	attacker._physics_process(0.75)
	assert(
		player.current_hp == hp_before,
		"projectile settled early: pending_before=%s pending_after=%s hp=%d"
		% [str(pending_before), str(attacker._pending_attack_time), player.current_hp],
	)
	attacker._physics_process(0.06)
	assert(player.current_hp == hp_before - 7, "bound projectile impact did not settle")

	# A target changing maps during flight keeps the visual but cancels damage.
	player.current_hp = hp_before
	attacker._attack_timer = 0.0
	attacker._physics_process(0.01)
	assert(_descriptors.size() == 2)
	player.set_meta("runtime_map_id", 2)
	attacker._physics_process(0.81)
	assert(player.current_hp == hp_before)
	player.set_meta("runtime_map_id", 1)

	# CanFly parity: one blocked intermediate sample rejects the whole release,
	# so there is no visual and no delayed damage transaction.
	_blocked_world_px = _ground_to_screen(Vector2(2.0, 0.0))
	attacker._attack_timer = 0.0
	attacker._physics_process(0.01)
	assert(_descriptors.size() == 2)
	assert(attacker._pending_attack_release_record.is_empty())
	attacker._physics_process(1.0)
	assert(player.current_hp == hp_before)

	attacker.queue_free()
	player.queue_free()
	await get_tree().process_frame
	print(
		"MONSTER_PHYSICAL_PROJECTILE_ATTACK_PASS "
		+ "profiles=150,152,206 immediate_damage=0 chebyshev_delay=0.8 "
		+ "visual=1 cross_map_cancel=1 can_fly_block=1"
	)
	get_tree().quit(0)


func _assert_authoritative_archer_profiles() -> void:
	for monster_id: int in [150, 152, 206]:
		var profile := MonsterIdentity.behavior_profile(
			GameData.get_monster_by_id(monster_id)
		)
		var delivery: Dictionary = profile.get("attackDelivery", {})
		assert(str(delivery.get("kind", "")) == "physical_projectile")
		assert(str(delivery.get("effectId", "")) == ProjectileEffectScript.EFFECT_ID)
		assert(str(delivery.get("obstaclePolicy", "")) == "environment_can_fly_line")
		assert(str(delivery.get("confidence", "")) == "A")


func is_environment_point_blocked(world_px: Vector2) -> bool:
	return (
		_blocked_world_px != Vector2.INF
		and world_px.distance_to(_blocked_world_px) <= 2.0
	)


func _capture_descriptor(descriptor: Dictionary) -> void:
	_descriptors.append(descriptor)


func _find_projectile_effect() -> Node2D:
	for child: Node in get_children():
		if child is Node2D and child.get_script() == ProjectileEffectScript:
			return child as Node2D
	return null


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(value)
