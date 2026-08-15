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


const BODY_LUMINANCE_THRESHOLD := 10.0 / 255.0


func _is_body_confidence_pixel(pixel: Color) -> bool:
	var luminance := 0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b
	return pixel.a > 0.0 and luminance > BODY_LUMINANCE_THRESHOLD


func _primary_body_bbox_medians_x(appearance_value: int) -> Array:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/classic_npc_art_sources.json"))
	var config: Dictionary = manifest["appearances"][str(appearance_value)]
	var frame_size_values: Array = config["frameSize"]
	var foot_anchor_values: Array = config["footAnchor"]
	var frame_width := int(frame_size_values[0])
	var frame_height := int(frame_size_values[1])
	var foot_anchor_x := float(foot_anchor_values[0])
	var frame_count := int(config.get("framesPerDirection", 4))
	var image := Image.load_from_file(ProjectSettings.globalize_path(str(config["path"])))
	var direction_medians: Array = []
	for logical_row in range(8):
		var samples: Array = []
		for frame in range(frame_count):
			var min_x := frame_width
			var max_x := -1
			for y in range(frame_height):
				for x in range(frame_width):
					if _is_body_confidence_pixel(image.get_pixel(frame * frame_width + x, logical_row * frame_height + y)):
						min_x = mini(min_x, x)
						max_x = maxi(max_x, x)
			assert(max_x >= min_x, "primary NPC atlas contains an empty body-confidence idle cell")
			samples.append((float(min_x) + float(max_x)) * 0.5 - foot_anchor_x)
		samples.sort()
		var midpoint := samples.size() / 2
		direction_medians.append((float(samples[midpoint - 1]) + float(samples[midpoint])) * 0.5 if samples.size() % 2 == 0 else float(samples[midpoint]))
	return direction_medians


func _primary_frame_bbox_center_x(appearance_value: int, direction_index: int, frame_index: int, body_only: bool) -> float:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/classic_npc_art_sources.json"))
	var config: Dictionary = manifest["appearances"][str(appearance_value)]
	var frame_size_values: Array = config["frameSize"]
	var foot_anchor_values: Array = config["footAnchor"]
	var frame_width := int(frame_size_values[0])
	var frame_height := int(frame_size_values[1])
	var foot_anchor_x := float(foot_anchor_values[0])
	var image := Image.load_from_file(ProjectSettings.globalize_path(str(config["path"])))
	var min_x := frame_width
	var max_x := -1
	for y in range(frame_height):
		for x in range(frame_width):
			var pixel := image.get_pixel(frame_index * frame_width + x, direction_index * frame_height + y)
			if pixel.a <= 0.0 or (body_only and not _is_body_confidence_pixel(pixel)):
				continue
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
	assert(max_x >= min_x, "primary NPC atlas contains an empty audited cell")
	return (float(min_x) + float(max_x)) * 0.5 - foot_anchor_x


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
		0: [20.75, 25.75, 25.75, 14.75, 19.25, 22.5, 16.25, 16.25],
		1: [23.75, 26.0, 26.0, 19.5, 23.25, 27.75, 20.5, 20.5],
		2: [23.5, 30.5, 30.5, 14.75, 26.0, 32.75, 17.5, 17.5],
		3: [23.0, 21.0, 21.0, 22.0, 23.0, 23.75, 25.0, 25.0],
		8: [23.25, 23.0, 23.0, 18.75, 20.75, 22.25, 20.0, 20.0],
		10: [23.0, 25.25, 25.25, 21.0, 23.0, 24.75, 21.25, 21.25],
		11: [23.75, 24.5, 24.5, 21.25, 24.5, 24.5, 15.0, 15.0],
		14: [23.5, 15.5, 15.5, 30.5, 23.5, 15.5, 30.5, 30.5],
		15: [22.5, 30.0, 30.0, 18.25, 12.5, 26.0, 16.5, 16.5],
	}
	for appearance_value in expected_visible_centers:
		var audited_centers := _primary_body_bbox_medians_x(int(appearance_value))
		var expected_centers: Array = expected_visible_centers[appearance_value]
		assert(audited_centers.size() == 8, "primary NPC atlas direction audit is incomplete")
		for direction_index in range(8):
			assert(is_equal_approx(float(audited_centers[direction_index]), float(expected_centers[direction_index])), "frozen NPC visible-center table diverged from primary atlas body-confidence audit")

	var appearance0_shadow_center := _primary_frame_bbox_center_x(0, 7, 0, false)
	var appearance0_body_center := _primary_frame_bbox_center_x(0, 7, 0, true)
	assert(is_equal_approx(appearance0_shadow_center, 34.5), "appearance 0 dir 7 alpha audit lost the source shadow evidence")
	assert(is_equal_approx(appearance0_body_center, 16.5), "appearance 0 dir 7 body-confidence audit changed")
	assert(abs(appearance0_shadow_center - appearance0_body_center) > 1.0, "appearance 0 dir 7 shadow pixels were not excluded")
	var appearance15_shadow_center := _primary_frame_bbox_center_x(15, 5, 0, false)
	var appearance15_body_center := _primary_frame_bbox_center_x(15, 5, 0, true)
	assert(is_equal_approx(appearance15_shadow_center, 37.0), "appearance 15 dir 5 alpha audit lost the source shadow evidence")
	assert(is_equal_approx(appearance15_body_center, 28.0), "appearance 15 dir 5 body-confidence audit changed")
	assert(abs(appearance15_shadow_center - appearance15_body_center) > 1.0, "appearance 15 dir 5 shadow pixels were not excluded")
	for npc in actors:
		var direction_index := ArtSpec.direction_index(npc.facing)
		var expected_visual_center_x := float(expected_visible_centers[npc.appearance][direction_index])
		var label_center_x := npc.name_label.position.x + npc.name_label.size.x * 0.5
		assert(is_equal_approx(label_center_x, expected_visual_center_x), "NPC name center is not aligned with the facing-specific visible source center")
	for appearance_value in expected_visible_centers:
		var npc := NPCActor.new()
		npc.setup("alignment-%d" % appearance_value, "shop", [], "", appearance_value, Vector2.ZERO)
		add_child(npc)
		await get_tree().process_frame
		assert(npc.uses_final_art(), "formal Bich NPC appearance did not load")
		var expected_centers: Array = expected_visible_centers[appearance_value]
		for direction_index in range(8):
			npc.face_toward(npc.global_position + NPCActor.FACING_DIRECTIONS[direction_index])
			var expected_center_x := float(expected_centers[direction_index])
			var actual_center_x := npc.name_label.position.x + npc.name_label.size.x * 0.5
			assert(is_equal_approx(actual_center_x, expected_center_x), "formal Bich NPC name center is not facing-specific body-confidence aligned")
			for _frame in range(4):
				await get_tree().process_frame
			var stable_center_x := npc.name_label.position.x + npc.name_label.size.x * 0.5
			assert(is_equal_approx(stable_center_x, expected_center_x), "NPC name center moved during animation frames")
		npc.face_toward(npc.global_position + NPCActor.FACING_DIRECTIONS[7])
		npc.reset_to_default_facing()
		var reset_center_x := npc.name_label.position.x + npc.name_label.size.x * 0.5
		assert(is_equal_approx(reset_center_x, expected_centers[0]), "NPC name anchor did not follow reset_to_default_facing")
		npc.queue_free()

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
