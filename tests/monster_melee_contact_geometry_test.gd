extends Node2D


const START_DISTANCE_PIXELS := 70.0
const SETTLED_POSITION_EPSILON := 0.05
const SOURCE_RADIUS := 16.0
const PLAYER_RADIUS := 18.0
const DIAGONAL_COMPONENT := 0.7071067811865476

const SCREEN_DIRECTIONS := {
	"S": Vector2.DOWN,
	"SW": Vector2(-DIAGONAL_COMPONENT, DIAGONAL_COMPONENT),
	"W": Vector2.LEFT,
	"NW": Vector2(-DIAGONAL_COMPONENT, -DIAGONAL_COMPONENT),
	"N": Vector2.UP,
	"NE": Vector2(DIAGONAL_COMPONENT, -DIAGONAL_COMPONENT),
	"E": Vector2.RIGHT,
	"SE": Vector2(DIAGONAL_COMPONENT, DIAGONAL_COMPONENT),
}

const LEGACY_48PX_LOGICAL_DISTANCE := {
	"S": 1.5,
	"SW": 1.590990,
	"W": 0.75,
	"NW": 1.590990,
	"N": 1.5,
	"NE": 1.590990,
	"E": 0.75,
	"SE": 1.590990,
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	_verify_legacy_directional_error_and_new_contact_geometry()

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
	ranged_probe.setup(GameData.get_monster("火焰沃玛"), player, false)
	assert(is_equal_approx(ranged_probe.attack_range, 155.0), "远程基线攻击距离变化")
	assert(
		not ranged_probe._uses_player_melee_contact_contract(player),
		"远程怪错误进入1.5格接敌合同",
	)
	ranged_probe.free()

	var final_distances := {}
	for direction_name: String in SCREEN_DIRECTIONS:
		var screen_direction: Vector2 = SCREEN_DIRECTIONS[direction_name]
		var enemy := EnemyActor.new()
		enemy.name = "ContactProbe_%s" % direction_name
		enemy.setup({"monsterId": -9001, "name": "接敌测试怪"}, player, false)
		enemy.global_position = screen_direction * START_DISTANCE_PIXELS
		enemy.set_meta("spawn_position", enemy.global_position)
		enemy.set_meta("safe_zones", [])
		enemy._attack_timer = 999.0
		add_child(enemy)

		var start_position := enemy.global_position
		var consecutive_settled_frames := 0
		for _frame in range(90):
			await get_tree().physics_frame
			var offset := player.global_position - enemy.global_position
			var logical_distance := EnemyActor.logical_tile_distance_for_world_offset(offset)
			var moved := enemy.global_position.distance_to(start_position) > 1.0
			if moved and enemy.velocity.length_squared() <= 0.01 and logical_distance <= 1.5001:
				consecutive_settled_frames += 1
			else:
				consecutive_settled_frames = 0
			if consecutive_settled_frames >= 5:
				break

		assert(consecutive_settled_frames >= 5, "%s方向怪物没有稳定进入接敌状态" % direction_name)
		var final_offset := player.global_position - enemy.global_position
		var final_distance := final_offset.length()
		var final_logical_distance := EnemyActor.logical_tile_distance_for_world_offset(final_offset)
		assert(
			final_logical_distance <= EnemyActor.PLAYER_MELEE_CONTACT_REACH_TILES + 0.0001,
			"%s方向仍停在1.5格外：%.6f" % [direction_name, final_logical_distance],
		)
		var physical_support := EnemyActor.directional_footprint_contact_distance(
			enemy.collision_radius,
			ArtSpec.PLAYER_COLLISION_RADIUS,
			final_offset,
			0.0,
		)
		assert(
			final_distance >= physical_support + 10.0,
			"%s方向接敌穿入2:1脚印：distance=%.3f support=%.3f" % [
				direction_name, final_distance, physical_support,
			],
		)

		var settled_position := enemy.global_position
		for _frame in range(8):
			await get_tree().physics_frame
			assert(
				enemy.global_position.distance_to(settled_position) <= SETTLED_POSITION_EPSILON,
				"%s方向接敌后发生抖动" % direction_name,
			)
		final_distances[direction_name] = final_logical_distance
		enemy.queue_free()
		await get_tree().physics_frame

	player.queue_free()
	print(
		"MONSTER_MELEE_CONTACT_GEOMETRY_PASS contract=%s logical=%s" % [
			EnemyActor.PLAYER_MELEE_CONTACT_CONTRACT_ID,
			final_distances,
		]
	)
	get_tree().quit(0)


func _verify_legacy_directional_error_and_new_contact_geometry() -> void:
	# Primary source evidence:
	# - original_gameofmir/MirClient/ClFunc.pas:351-355 GetDistance uses
	#   MAX(abs(dx), abs(dy)) in logical cells.
	# - original_gameofmir/MirClient/ClMain.pas:2698-2699 resolves direction in
	#   logical cells and admits melee only when both axes are <= 1.
	# The project-authorized reach is 1.5 cells, but the coordinate family stays
	# identical. The previous 48px Euclidean circle violates that family.
	var legacy_distance := SOURCE_RADIUS + PLAYER_RADIUS + 14.0
	for direction_name: String in SCREEN_DIRECTIONS:
		var direction: Vector2 = SCREEN_DIRECTIONS[direction_name]
		var observed_legacy := EnemyActor.logical_tile_distance_for_world_offset(
			direction * legacy_distance
		)
		assert(
			absf(observed_legacy - float(LEGACY_48PX_LOGICAL_DISTANCE[direction_name])) < 0.0001,
			"%s方向旧48px量化结果变化：%.6f" % [direction_name, observed_legacy],
		)

		var contact_distance := EnemyActor.directional_footprint_contact_distance(
			SOURCE_RADIUS,
			PLAYER_RADIUS,
			direction,
		)
		var corrected_logical := EnemyActor.logical_tile_distance_for_world_offset(
			direction * contact_distance
		)
		assert(
			corrected_logical <= EnemyActor.PLAYER_MELEE_CONTACT_REACH_TILES + 0.0001,
			"%s方向的2:1脚印接敌仍超出1.5格：%.6f" % [direction_name, corrected_logical],
		)

	assert(
		is_equal_approx(
			EnemyActor.directional_footprint_contact_distance(
				SOURCE_RADIUS, PLAYER_RADIUS, Vector2.RIGHT
			),
			48.0,
		),
		"东西方向没有保留横向脚印支持距离",
	)
	assert(
		is_equal_approx(
			EnemyActor.directional_footprint_contact_distance(
				SOURCE_RADIUS, PLAYER_RADIUS, Vector2.DOWN
			),
			31.0,
		),
		"南北方向仍错误使用两倍高度的横向碰撞半径",
	)
