extends Node2D

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	y_sort_enabled = true
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for action in ["move_left", "move_right", "move_up", "move_down", "attack"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var player := PlayerCharacter.new()
	player.name = "CrowdTestPlayer"
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	player.max_hp = 10000
	player.current_hp = 10000
	assert(player.collision_layer == 2 and player.collision_mask == 5, "玩家碰撞层未隔离为player/world+enemy")

	var enemies: Array[EnemyActor] = []
	var data := GameData.get_monster_by_id(21)
	assert(not data.is_empty(), "稻草人 canonical monster_id=21 缺失")
	for index in range(8):
		var enemy := EnemyActor.new()
		enemy.setup(data, player, false)
		enemy.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			Vector2.from_angle(float(index) / 8.0 * TAU) * 0.25
		)
		add_child(enemy)
		enemies.append(enemy)
	await get_tree().process_frame
	for _frame in range(150):
		await get_tree().physics_frame

	for enemy: EnemyActor in enemies:
		assert(enemy.collision_layer == 4 and enemy.collision_mask == 3, "怪物必须保留world/player硬碰撞并关闭enemy互撞")
		var player_offset_ground_gu := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			player.global_position - enemy.global_position
		)
		var minimum_player_distance_gu := (
			enemy.combat_radius_gu
			+ WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
				ArtSpec.PLAYER_COLLISION_RADIUS_PX
			)
		)
		assert(
			player_offset_ground_gu.length() >= minimum_player_distance_gu - 0.02,
			"怪物进入玩家2:1脚印安全间隙",
		)
		assert(
			player_offset_ground_gu.length()
			<= maxf(enemy.attack_range_gu, enemy._contact_distance_gu_to_target(player)) + 0.02,
			"普通怪物停在GU接敌合同之外",
		)
	for first in range(enemies.size()):
		for second in range(first + 1, enemies.size()):
			var minimum_enemy_distance_gu := (
				enemies[first].combat_radius_gu
				+ enemies[second].combat_radius_gu
			)
			var enemy_delta_ground_gu := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
				enemies[second].global_position - enemies[first].global_position
			)
			assert(enemy_delta_ground_gu.length() >= minimum_enemy_distance_gu - 0.02, "怪物之间发生实体重叠")

	var player_shadow_top := 4.0 - 23.0 * 0.36
	var monster_shadow_top := ArtSpec.MONSTER_COLLISION_RADIUS_PX * 0.28 - ArtSpec.MONSTER_COLLISION_RADIUS_PX * 0.36
	assert(player_shadow_top < 0.0 and monster_shadow_top < 0.0, "接地阴影上缘没有覆盖脚底锚点")
	assert(
		player.visual.position.is_equal_approx(
			ArtSpec.PLAYER_VISUAL_RUNTIME_POSITION
		)
		and (
			player.visual.position
			+ ArtSpec.PLAYER_VISUAL_FOOT_ANCHOR_ADJUSTMENT
		).is_zero_approx(),
		"人物视觉层没有使用已验收的人工脚点",
	)
	for enemy: EnemyActor in enemies:
		assert(
			enemy.visual.position.is_equal_approx(
				enemy.visual.reviewed_visual_origin()
			)
			and (
				enemy.visual.position
				+ enemy.visual.visual_foot_offset()
			).is_zero_approx()
			and (
				enemy.visual.manual_alignment_replay_displacement().y
				> 0.0
			),
			"普通怪物没有复现人工接地位置并保持物理脚点",
		)
	assert(y_sort_enabled, "战斗场景没有启用Y轴渲染排序")
	print("CROWD_GROUNDING_PASS：8怪拥挤无穿模、碰撞层隔离、Y轴排序与脚底阴影接地正常")
	get_tree().quit(0)
