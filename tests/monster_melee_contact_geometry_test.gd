extends Node2D

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const START_DISTANCE_GU := 3.0


func _test_ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


func _configure_enemy_map(enemy: EnemyActor) -> void:
	enemy.configure_runtime_map_projection(
		1,
		Callable(self, "_test_ground_to_screen")
	, GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	_verify_projected_speed_is_equal_in_32_directions()

	var player := PlayerCharacter.new()
	player.name = "StaticContactPlayer"
	player.global_position = Vector2.ZERO
	add_child(player)
	player.set_physics_process(false)
	player.visual.set_process(false)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	player.set_touch_vector(Vector2.ZERO)

	var ranged_probe := EnemyActor.new()
	# The old test used flame wooma as a generic ranged stand-in. Its exact
	# Race=91 contract is now adjacent magic melee, so exercise the same swept
	# projectile geometry with the authoritative archer profile instead.
	ranged_probe.setup(GameData.get_monster_by_id(150), player, false)
	assert(is_equal_approx(ranged_probe.attack_range_gu, 205.0 / 32.0), "弓箭手旧PX范围未在adapter边界转换为GU")
	assert(not ranged_probe._uses_player_melee_contact_contract(player))
	ranged_probe.global_position = Vector2.ZERO
	ranged_probe.set_physics_process(false)
	add_child(ranged_probe)
	player.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		Vector2(4.0, 0.0)
	)
	var ranged_hp_before := player.current_hp
	_configure_enemy_map(ranged_probe)
	ranged_probe._deal_melee_hit(player, 5)
	assert(player.current_hp < ranged_hp_before, "ranged release sweep did not deal damage")
	assert(
		str(ranged_probe._last_attack_footprint_snapshot.shape_type)
		== SkillFootprintSnapshotScript.SHAPE_SWEPT_CAPSULE_PATH,
		"ranged release is not represented by a swept GU path",
	)
	assert(
		str(ranged_probe._last_attack_footprint_snapshot.projection_relationship_id)
		== EnemyActor.PROJECTION_RELATIONSHIP_PROJECTILE_SWEEP,
		"ranged release does not declare projectile_sweep",
	)
	assert(
		Vector2(ranged_probe._last_attack_footprint_snapshot.segment_start_ground_gu)
		.is_equal_approx(
			ranged_probe._screen_position_px_to_ground_position_gu(
				ranged_probe.global_position
			)
		),
		"ranged sweep does not start at the attacker release footpoint",
	)
	assert(
		Vector2(ranged_probe._last_attack_footprint_snapshot.segment_end_ground_gu)
		.is_equal_approx(
			ranged_probe._screen_position_px_to_ground_position_gu(player.global_position)
		),
		"ranged sweep does not end at the selected target footpoint",
	)
	player.global_position = Vector2.ZERO
	ranged_probe.free()

	var final_distances_gu: Array[float] = []
	var enemies: Array[EnemyActor] = []
	for direction_index in range(8):
		var angle := TAU * float(direction_index) / 8.0
		var direction_ground := Vector2.from_angle(angle)
		var enemy := EnemyActor.new()
		enemy.name = "ContactProbe_%d" % direction_index
		# Runtime setup is fail-closed for unknown monster IDs. Use the canonical
		# ordinary-melee 沃玛战士 fixture so the eight-direction collision probe
		# exercises the production actor instead of a rejected placeholder.
		enemy.setup(GameData.get_monster_by_id(64), player, false)
		enemy.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			direction_ground * START_DISTANCE_GU
		)
		enemy.set_meta("spawn_position", enemy.global_position)
		enemy.set_meta("safe_zones", [])
		enemy._attack_timer = 999.0
		enemy.set_physics_process(false)
		add_child(enemy)
		enemies.append(enemy)

	# Run every direction in the same physics frames. This keeps the formal
	# 8-direction equivalence test below the repository's default 8s budget.
	# M01B cadence replaces continuous movement with discrete steps. The melee
	# contact geometry is independent of movement cadence, so position each
	# monster at the exact contact distance directly.
	for direction_index in range(enemies.size()):
		var enemy := enemies[direction_index]
		await get_tree().physics_frame
		_configure_enemy_map(enemy)
		var angle := TAU * float(direction_index) / 8.0
		var direction_ground := Vector2.from_angle(angle)
		var contact_distance_gu := enemy._contact_distance_gu_to_target(player)
		# Place the monster at exactly the contact distance from the player
		var contact_screen_offset := GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			direction_ground * contact_distance_gu
		)
		enemy.global_position = player.global_position + contact_screen_offset
		# Advance physics to let collision settle
		await get_tree().physics_frame
		await get_tree().physics_frame
		await get_tree().physics_frame
		await get_tree().physics_frame
		await get_tree().physics_frame

	for direction_index in range(enemies.size()):
		var enemy := enemies[direction_index]
		var final_delta_ground_gu := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			player.global_position - enemy.global_position
		)
		final_distances_gu.append(final_delta_ground_gu.length())
		var hp_before := player.current_hp
		enemy._deal_melee_hit(player, 5)
		assert(player.current_hp < hp_before, "direction %d footprint contact did not deal damage" % direction_index)
		assert(
			SkillFootprintSnapshotScript.has_legacy_base_contract(
				enemy._last_attack_footprint_snapshot
			),
			"direction %d attack did not publish a GU footprint snapshot" % direction_index,
		)
		assert(
			str(enemy._last_attack_footprint_snapshot.shape_type)
			== SkillFootprintSnapshotScript.SHAPE_CIRCLE,
			"direction %d ordinary attack is not target-footprint geometry" % direction_index,
		)
		assert(
			str(enemy._last_attack_footprint_snapshot.projection_relationship_id)
			== EnemyActor.PROJECTION_RELATIONSHIP_RELEASE_CONTACT,
			"direction %d melee release does not declare release_contact" % direction_index,
		)
		assert(
			Vector2(enemy._last_attack_footprint_snapshot.origin_ground_gu).is_equal_approx(
				enemy._screen_position_px_to_ground_position_gu(enemy.global_position)
			),
			"direction %d melee footprint origin is not the release footpoint" % direction_index,
		)
		enemy.queue_free()
	await get_tree().physics_frame

	var minimum: float = float(final_distances_gu.min())
	var maximum: float = float(final_distances_gu.max())
	assert(maximum - minimum <= 0.025, "GU melee contact remains direction dependent: %s" % final_distances_gu)

	player.queue_free()
	print(
		"MONSTER_MELEE_CONTACT_GEOMETRY_PASS contract=%s distances_gu=%s" % [
			EnemyActor.PLAYER_MELEE_CONTACT_CONTRACT_ID,
			final_distances_gu,
		]
	)
	get_tree().quit(0)


func _verify_projected_speed_is_equal_in_32_directions() -> void:
	const SPEED_GU_PER_SEC := 1.8125
	for direction_index in range(32):
		var direction_ground := Vector2.from_angle(TAU * float(direction_index) / 32.0)
		var velocity_px_per_sec := GroundUnitSpaceScript.desired_screen_velocity_px_per_sec(
			direction_ground,
			SPEED_GU_PER_SEC,
		)
		var recovered_velocity_ground_gu_per_sec := (
			GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(velocity_px_per_sec)
		)
		assert(
			absf(recovered_velocity_ground_gu_per_sec.length() - SPEED_GU_PER_SEC) <= 0.00001,
			"direction %d projected monster speed is not GU/s" % direction_index,
		)
