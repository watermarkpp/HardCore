extends Node

const MANIFEST_PATH := "res://assets/data/vanilla_176/divine_beast_animation.json"
const ACTIONS: Array[String] = ["idle", "walk", "attack", "hit", "death"]
const SummonVisualRegistryScript := preload("res://scripts/summon_visual_registry.gd")


func _ready() -> void:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var manifest: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	assert(manifest is Dictionary, "神兽动作清单无法读取")
	assert(manifest.contract_id == SummonVisualRegistryScript.DIVINE_BEAST_CONTRACT_ID)
	assert(manifest.appearance == 171 and manifest.race == 55 and manifest.actionTable == "MA29")
	assert(manifest.directionMode == "mir2_north_first" and manifest.blockBase == 350)
	var expected_counts := {"idle": 4, "walk": 6, "attack": 6, "hit": 2, "death": 10}
	for action_name: String in ACTIONS:
		var action: Dictionary = manifest.actions[action_name]
		assert(action.framesPerDirection == expected_counts[action_name], "%s帧数不符合MA29" % action_name)
		assert(action.validatedSourceFrameCount == expected_counts[action_name] * 8, "%s没有完整覆盖8方向" % action_name)
		assert(action.missingFrames.is_empty(), "%s含空白或缺失正式帧" % action_name)
		assert(ResourceLoader.exists(action.path), "%s动作图集未导入" % action_name)

	SummonVisualRegistryScript.clear_cache_for_tests()
	var cold_profile: Dictionary = SummonVisualRegistryScript.profile("divine_beast")
	assert(cold_profile.contract_id == SummonVisualRegistryScript.DIVINE_BEAST_CONTRACT_ID, "冷启动不能激活神兽动作资源")
	assert(cold_profile.direction_mode == "mir2_north_first")
	for action_name: String in ACTIONS:
		assert(cold_profile[action_name] is Texture2D, "%s没有正式动作纹理" % action_name)

	var owner := PlayerCharacter.new()
	owner.current_hp = 100
	owner.facing = Vector2.DOWN
	var beast := SummonActor.new()
	beast.setup(owner, "神兽", 30, 3, "taoist.summon_divine_beast", 40)
	add_child(beast)
	await get_tree().process_frame
	assert(beast._sprite != null and beast._sprite.name == "DivineBeastAnimatedBody")
	assert(beast._animation_resources.contract_id == SummonVisualRegistryScript.DIVINE_BEAST_CONTRACT_ID)
	assert(beast._sprite.scale == Vector2.ONE, "神兽错误使用单帧缩放贴图")
	assert(beast._sprite.texture == cold_profile.idle, "神兽初始动作不是正式idle图集")

	var frame_size: Vector2i = cold_profile.frame_size
	for direction_vector: Vector2 in [
		Vector2.UP,
		Vector2(1, -1),
		Vector2.RIGHT,
		Vector2(1, 1),
		Vector2.DOWN,
		Vector2(-1, 1),
		Vector2.LEFT,
		Vector2(-1, -1),
	]:
		beast._visual_facing = direction_vector.normalized()
		beast._visual_direction = ArtSpec.mir2_client_direction_row(beast._visual_facing)
		assert(beast._visual_direction in range(8), "神兽方向换算越界")
		beast._apply_visual_frame()
		assert(beast._sprite.region_rect.position.y == beast._visual_direction * frame_size.y)

	for action_name: String in ACTIONS:
		beast._visual_state = action_name
		beast._visual_frame = int(cold_profile.frame_counts[action_name]) - 1
		beast._apply_visual_frame()
		assert(beast._sprite.texture == cold_profile[action_name], "%s状态没有切换到对应图集" % action_name)
		assert(beast._sprite.region_rect.position.x == beast._visual_frame * frame_size.x, "%s末帧区域不稳定" % action_name)

	SummonVisualRegistryScript.clear_cache_for_tests()
	beast._animation_resources = {}
	beast._sprite.texture = null
	assert(beast.activate_visual_resources(), "冷缓存重激活失败")
	assert(beast._sprite.texture == beast._animation_resources.idle, "资源激活后没有刷新当前显示")

	beast.velocity = Vector2.RIGHT * beast.move_speed
	beast._process(0.17)
	assert(beast._visual_state == "walk", "移动没有进入walk循环")
	beast.velocity = Vector2.ZERO
	beast._attack_visual_remaining = beast._visual_action_duration("attack")
	beast._process(0.01)
	assert(beast._visual_state == "attack", "攻击没有进入attack单次动作")
	beast._attack_visual_remaining = 0.0
	beast.take_damage(1)
	beast._process(0.01)
	assert(beast._visual_state == "hit", "受击没有进入hit动作")
	beast.take_damage(beast.current_hp)
	beast._process(0.01)
	assert(beast.state == SummonActor.SummonState.DEAD and beast._visual_state == "death", "死亡没有保留death动作")
	assert(not beast.is_queued_for_deletion(), "死亡首帧尚未播放就被移除")

	owner.free()
	print("DIVINE_BEAST_ANIMATION_PASS: MA29 idle/walk/attack/hit/death, 8 directions, foot anchor and cold activation")
	get_tree().quit(0)
