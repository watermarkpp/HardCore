extends Node

const MANIFEST_PATH := "res://assets/data/complete_monster_client_art_sources.json"
const CATALOG_PATH := "res://assets/data/runtime/monster_animation_catalog.json"
const REQUIRED_ACTIONS := ["idle", "walk", "attack", "hit", "death"]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var manifest := _load_json(MANIFEST_PATH)
	var catalog := _load_json(CATALOG_PATH)
	var mappings: Dictionary = manifest.get("runtimeMappingsByMonsterId", {})
	var summary: Dictionary = manifest.get("summary", {})

	assert(manifest.get("identityKey", "") == "monsterId", "完整怪物动画清单未使用稳定 monsterId")
	assert(int(summary.get("newFormalMonsterCount", -1)) == 143, "新增正式五动作绑定数量不是143")
	assert(int(summary.get("rejectedCount", -1)) == 0, "完整客户端动画仍有被拒绝映射")
	assert(mappings.size() == 143, "完整客户端动画 stable ID 映射数量错误")

	for monster_key: String in mappings:
		var profile: Dictionary = mappings[monster_key]
		assert(int(profile.get("directions", 0)) == 8, "monsterId=%s 不是八方向" % monster_key)
		assert(int(profile.get("serviceRace", -1)) >= 0, "monsterId=%s 缺少服务 Race 证据" % monster_key)
		var frame_size_values: Array = profile.get("frameSize", [])
		assert(frame_size_values.size() == 2, "monsterId=%s 缺少帧尺寸" % monster_key)
		var frame_size := Vector2i(int(frame_size_values[0]), int(frame_size_values[1]))
		for action_name: String in REQUIRED_ACTIONS:
			var action: Dictionary = profile.get("actions", {}).get(action_name, {})
			var frame_count := int(action.get("framesPerDirection", 0))
			var path := str(action.get("path", ""))
			assert(frame_count > 0, "monsterId=%s %s 没有正式帧" % [monster_key, action_name])
			assert(action.get("missingFrames", []).is_empty(), "monsterId=%s %s 仍有缺帧" % [monster_key, action_name])
			assert(FileAccess.file_exists(path), "monsterId=%s %s 图集不存在" % [monster_key, action_name])
			var image := Image.load_from_file(ProjectSettings.globalize_path(path))
			assert(
				image != null and not image.is_empty()
				and image.get_size() == Vector2i(frame_size.x * frame_count, frame_size.y * 8),
				"monsterId=%s %s 图集尺寸不符合五动作八方向清单" % [monster_key, action_name]
			)

	var catalog_summary: Dictionary = catalog.get("summary", {})
	assert(int(catalog_summary.get("total", -1)) == 214, "动画总目录未覆盖214个怪物")
	assert(int(catalog_summary.get("formal", -1)) == 214, "正式五动作绑定未达到214")
	assert(int(catalog_summary.get("missing", -1)) == 0, "动画总目录仍登记缺失")

	var player := PlayerCharacter.new()
	player.global_position = Vector2(900, 0)
	add_child(player)
	player.set_physics_process(false)
	for monster_id: int in [180, 195, 241]:
		var data: Dictionary = GameData.get_monster_by_id(monster_id).duplicate(true)
		data["name"] = "稳定ID运行时改名"
		var enemy := EnemyActor.new()
		enemy.setup(data, player, monster_id in [180, 195])
		add_child(enemy)
		enemy.set_physics_process(false)
		await get_tree().process_frame
		assert(enemy.visual.uses_final_art(), "monsterId=%d 未在运行时启用完整客户端动画" % monster_id)
		assert(enemy.visual.active_resources.get("animation_source", "") == "classic_client_wil", "monsterId=%d 动画来源错误" % monster_id)
		enemy.queue_free()

	player.queue_free()
	print("COMPLETE_MONSTER_CLIENT_ART_PASS：143个缺失绑定均有正式五动作八方向图集，214个怪物目录无缺失")
	get_tree().quit(0)


func _load_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "缺少测试数据文件: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	assert(parsed is Dictionary, "JSON解析失败: %s" % path)
	return parsed
