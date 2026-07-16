extends Node

const Catalog := preload("res://scripts/environment_catalog.gd")
const Validator := preload("res://scripts/environment_validator.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var errors := Validator.validate_all()
	assert(errors.is_empty(), "环境模板校验失败：%s" % "；".join(errors))
	assert(Catalog.theme_ids().size() == 5, "未建立地表、洞穴、寺庙、矿区、沙地五类主题")
	var background_source := FileAccess.get_file_as_string("res://scripts/world_background.gd")
	assert(not background_source.contains("248:") and not background_source.contains("249:"), "天然洞穴仍依赖地图ID定制渲染代码")

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var background: WorldBackground = game.background
	var stable_counts := {}
	# 先完成专用纹理的首次导入/驻留；内存断言只衡量重复切换增量，避免把正常加载误报为泄漏。
	for warmup_map_id in [248, 249]:
		game.travel_to_map(warmup_map_id)
		await get_tree().process_frame
		await get_tree().process_frame
	var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	for pass_index in range(8):
		for map_id in [248, 249]:
			game.travel_to_map(map_id)
			await get_tree().process_frame
			await get_tree().process_frame
			var profile := Catalog.get_map_profile(map_id)
			assert(background.uses_environment_template() and background.environment_theme_id() == "cave", "天然洞穴%d没有走洞穴环境模板" % map_id)
			assert(background.environment_collision_count() == int(profile.expected_collisions), "天然洞穴%d碰撞数量错误" % map_id)
			assert(background.environment_light_count() == int(profile.expected_lights), "天然洞穴%d灯光数量错误" % map_id)
			for portal: Dictionary in RegionContent.get_map_content(map_id).get("portals", []):
				assert(not background.is_environment_point_blocked(portal.position), "天然洞穴%d门点被环境阻挡" % map_id)
			var node_count := background.environment_node_count()
			if stable_counts.has(map_id):
				assert(node_count == int(stable_counts[map_id]), "天然洞穴%d重复切换产生环境节点残留" % map_id)
			else:
				stable_counts[map_id] = node_count
	var memory_after := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	assert(memory_after - memory_before < 12 * 1024 * 1024, "环境模板往返测试静态内存异常增长")
	print("ENVIRONMENT_TEMPLATE_PASS：5主题、23地图配置、248/249无定制代码接入、门点畅通、节点稳定，静态内存变化%dKB" % int((memory_after - memory_before) / 1024))
	get_tree().quit(0)
