extends Node


class MockHUD:
	extends RefCounted
	var opened_shop := ""
	var opened_stock: Array = []
	var opened_context: Dictionary = {}

	func open_shop(shop_name: String, stock: Array, merchant_context: Dictionary = {}) -> void:
		opened_shop = shop_name
		opened_stock = stock
		opened_context = merchant_context.duplicate(true)


class MockGame:
	extends Node
	var player: Node2D
	var hud := MockHUD.new()

	func _build_skill_book_stock(_profession: String) -> Array:
		return []


func _primary_alpha_bbox_median_x(appearance_value: int) -> float:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/classic_npc_art_sources.json"))
	var config: Dictionary = manifest["appearances"][str(appearance_value)]
	var frame_size_values: Array = config["frameSize"]
	var foot_anchor_values: Array = config["footAnchor"]
	var frame_width := int(frame_size_values[0])
	var frame_height := int(frame_size_values[1])
	var foot_anchor_x := float(foot_anchor_values[0])
	var frame_count := int(config.get("framesPerDirection", 4))
	var image := Image.load_from_file(ProjectSettings.globalize_path(str(config["path"])))
	var samples: Array = []
	for logical_row in range(8):
		for frame in range(frame_count):
			var min_x := frame_width
			var max_x := -1
			for y in range(frame_height):
				for x in range(frame_width):
					if image.get_pixel(frame * frame_width + x, logical_row * frame_height + y).a > 0.0:
						min_x = mini(min_x, x)
						max_x = maxi(max_x, x)
			assert(max_x >= min_x, "primary NPC atlas contains an empty idle cell")
			samples.append((float(min_x) + float(max_x)) * 0.5 - foot_anchor_x)
	samples.sort()
	var midpoint := samples.size() / 2
	return (float(samples[midpoint - 1]) + float(samples[midpoint])) * 0.5 if samples.size() % 2 == 0 else float(samples[midpoint])


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/classic_npc_art_sources.json"))
	assert(manifest.get("sourceTier") == "primary")
	var source_group_map: Array = manifest.get("logicalToSourceGroup", [])
	assert(source_group_map.size() == 8)
	for index in range(8):
		assert(int(source_group_map[index]) == [1, 0, 0, 5, 4, 3, 2, 2][index])
	assert(manifest.get("appearances", {}).size() == 23)

	var expectations := [
		[Vector2(100, 0), Vector2.LEFT],
		[Vector2(-100, 0), Vector2.RIGHT],
		[Vector2(0, 100), Vector2.UP],
		[Vector2(0, -100), Vector2.DOWN],
	]
	var actors: Array[NPCActor] = []
	for index in range(expectations.size()):
		var npc := NPCActor.new()
		npc.setup("方向测试%d" % index, "shop", [], "", index, Vector2.ZERO)
		npc.global_position = expectations[index][0]
		add_child(npc)
		actors.append(npc)
		assert(npc.facing.is_equal_approx(expectations[index][1]), "NPC默认朝向没有指向地图中心")
	await get_tree().process_frame
	for npc in actors:
		assert(npc.uses_final_art(), "NPC没有加载主客户端Npc.wil运行图集")

	var expected_visible_centers := {
		0: 35.0,
		1: 36.25,
		2: 35.75,
		3: 38.0,
		8: 37.0,
		10: 34.25,
		11: 34.0,
		14: 23.5,
		15: 34.5,
	}
	for appearance_value in expected_visible_centers:
		assert(is_equal_approx(_primary_alpha_bbox_median_x(int(appearance_value)), float(expected_visible_centers[appearance_value])), "frozen NPC visible-center table diverged from primary atlas alpha audit")
	for npc in actors:
		var expected_visual_center_x := float(expected_visible_centers[npc.appearance])
		var label_center_x := npc.name_label.position.x + npc.name_label.size.x * 0.5
		assert(is_equal_approx(label_center_x, expected_visual_center_x), "NPC name center is not aligned with the visible source center")
	for appearance_value in [8, 10, 11, 14, 15]:
		var npc := NPCActor.new()
		npc.setup("alignment-%d" % appearance_value, "shop", [], "", appearance_value, Vector2.ZERO)
		add_child(npc)
		await get_tree().process_frame
		assert(npc.uses_final_art(), "formal Bich NPC appearance did not load")
		var expected_center_x := float(expected_visible_centers[appearance_value])
		var actual_center_x := npc.name_label.position.x + npc.name_label.size.x * 0.5
		assert(is_equal_approx(actual_center_x, expected_center_x), "formal Bich NPC name center is not alpha aligned")
		npc.queue_free()
	var first_label_center_x := actors[0].name_label.position.x + actors[0].name_label.size.x * 0.5
	for _frame in range(3):
		await get_tree().process_frame
	var stable_label_center_x := actors[0].name_label.position.x + actors[0].name_label.size.x * 0.5
	assert(is_equal_approx(stable_label_center_x, first_label_center_x), "NPC name center moved with animation frames")

	var game := MockGame.new()
	game.player = Node2D.new()
	game.player.global_position = actors[0].global_position + Vector2(120, -120)
	game.add_child(game.player)
	add_child(game)
	actors[0].interact(game)
	assert(actors[0].facing.is_equal_approx(Vector2(0.70710678, -0.70710678)), "交互时NPC没有转向玩家")
	assert(game.hud.opened_shop == "方向测试0", "转向后NPC服务入口未继续执行")
	await get_tree().process_frame
	assert(actors[0].visual.current_direction == 5, "交互转向没有同步到NE图集行")
	print("NPC_FACING_INTERACTION_PASS: primary Npc.wil 6-view source, 8 logical directions, map-center default and player-facing interaction")
	get_tree().quit(0)
