extends Node


const EXPECTED_FRAMES := {
	"idle": 4,
	"walk": 4,
	"attack": 6,
	"hit": 2,
	"death": 20,
}
const CELL_SIZE := Vector2i(288, 208)
const ALPHA_THRESHOLD := 12.0 / 255.0
const SUPPORT_BAND_FRACTION := 0.12
const MAX_SUPPORT_ANCHOR_DEVIATION_PX := 1.5


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var monster_data := GameData.get_monster_by_id(180)
	assert(not monster_data.is_empty(), "redmoon gameplay data missing")
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	var enemy := EnemyActor.new()
	enemy.setup(monster_data, player, true)
	add_child(enemy)
	enemy.set_physics_process(false)
	await get_tree().process_frame
	var visual: MonsterVisual = enemy.visual
	assert(visual.uses_final_art(), "redmoon final art did not load")
	assert(visual.frame_size == Vector2i(288, 208))
	var appearance := MonsterIdentity.appearance_profile(180)
	var actions: Dictionary = appearance.get("actions", {})
	var fixed_contact := enemy.ground_indicator_center()
	var fixed_radii := enemy.ground_indicator_radii()
	for action_name: String in EXPECTED_FRAMES:
		var frame_count := MonsterAnimationPolicy.frame_count(
			visual.active_resources,
			StringName(action_name),
		)
		assert(frame_count == EXPECTED_FRAMES[action_name])
		var texture: Texture2D = visual.active_resources[action_name]
		assert(texture != null)
		assert(texture.get_width() == 288 * frame_count)
		assert(texture.get_height() == 208 * 8)
		var action: Dictionary = actions.get(action_name, {})
		_assert_import_matches_source(
			action_name,
			texture,
			str(action.get("path", "")),
		)
		var anchor_metrics := _support_anchor_metrics(
			texture.get_image(), frame_count
		)
		var max_anchor_delta: Array = anchor_metrics.get(
			"maxAbsDeviationPx", [999.0, 999.0]
		)
		assert(
			float(max_anchor_delta[0]) <= MAX_SUPPORT_ANCHOR_DEVIATION_PX
				and float(max_anchor_delta[1]) <= MAX_SUPPORT_ANCHOR_DEVIATION_PX,
			"%s support anchor drift exceeds %.1fpx: %s"
			% [action_name, MAX_SUPPORT_ANCHOR_DEVIATION_PX, str(anchor_metrics)],
		)
		print(
			"REDMOON_SUPPORT_ANCHOR action=%s reference=%s maxAbs=%s perFrame=%s"
			% [
				action_name,
				str(anchor_metrics.get("reference", [])),
				str(anchor_metrics.get("maxAbsDeviationPx", [])),
				str(anchor_metrics.get("perFrame", [])),
			]
		)
		for direction in range(8):
			for frame in range(frame_count):
				visual.current_state = action_name
				visual.current_direction = direction
				visual.current_frame = frame
				visual.sprite.texture = texture
				visual.sprite.region_rect = Rect2(
					frame * 288,
					direction * 208,
					288,
					208,
				)
				assert(enemy.ground_indicator_center().is_equal_approx(fixed_contact))
				assert(enemy.ground_indicator_radii().is_equal_approx(fixed_radii))
	print("REDMOON_GENERATED_ANIMATION_RUNTIME_PASS native-alpha five-action atlas loaded for all frames and directions")
	get_tree().quit(0)


func _support_anchor_metrics(image: Image, frame_count: int) -> Dictionary:
	image.convert(Image.FORMAT_RGBA8)
	var anchors: Array[Vector2] = []
	for frame_index in range(frame_count):
		anchors.append(_support_anchor(image, frame_index))
	var x_values: Array[float] = []
	var y_values: Array[float] = []
	for anchor in anchors:
		x_values.append(anchor.x)
		y_values.append(anchor.y)
	var reference := Vector2(_median(x_values), _median(y_values))
	var deviations: Array = []
	var max_abs_x := 0.0
	var max_abs_y := 0.0
	for anchor in anchors:
		var delta := anchor - reference
		max_abs_x = maxf(max_abs_x, absf(delta.x))
		max_abs_y = maxf(max_abs_y, absf(delta.y))
		deviations.append([delta.x, delta.y])
	return {
		"reference": [reference.x, reference.y],
		"perFrame": deviations,
		"maxAbsDeviationPx": [max_abs_x, max_abs_y],
	}


func _support_anchor(image: Image, frame_index: int) -> Vector2:
	var frame_x := frame_index * CELL_SIZE.x
	var top := CELL_SIZE.y
	var bottom := -1
	var row_centers: Array[float] = []
	var row_numbers: Array[float] = []
	for y in range(CELL_SIZE.y):
		var row_x: Array[int] = []
		for x in range(CELL_SIZE.x):
			if image.get_pixel(frame_x + x, y).a >= ALPHA_THRESHOLD:
				row_x.append(x)
		if row_x.is_empty():
			continue
		top = mini(top, y)
		bottom = maxi(bottom, y)
		row_centers.append(_median(row_x))
		row_numbers.append(float(y))
	assert(bottom >= 0, "empty Red Moon frame while finding support anchor")
	var band_height := maxi(
		2,
		roundi(float(bottom - top + 1) * SUPPORT_BAND_FRACTION),
	)
	var band_start := maxi(top, bottom - band_height)
	var support_centers: Array[float] = []
	var support_rows: Array[float] = []
	for index in range(row_numbers.size()):
		if int(row_numbers[index]) >= band_start:
			support_centers.append(row_centers[index])
			support_rows.append(row_numbers[index])
	return Vector2(_median(support_centers), _median(support_rows))


func _median(values: Array) -> float:
	assert(not values.is_empty(), "median requires at least one value")
	var sorted_values: Array = values.duplicate()
	sorted_values.sort()
	var middle := sorted_values.size() / 2
	if sorted_values.size() % 2 == 1:
		return float(sorted_values[middle])
	return (
		float(sorted_values[middle - 1])
		+ float(sorted_values[middle])
	) / 2.0


func _assert_import_matches_source(
	action_name: String,
	texture: Texture2D,
	source_path: String,
) -> void:
	assert(not source_path.is_empty(), "%s source path missing" % action_name)
	var source := Image.load_from_file(
		ProjectSettings.globalize_path(source_path)
	)
	var imported := texture.get_image()
	assert(not source.is_empty(), "%s source PNG failed to load" % action_name)
	assert(not imported.is_empty(), "%s imported texture failed to decode" % action_name)
	source.convert(Image.FORMAT_RGBA8)
	imported.convert(Image.FORMAT_RGBA8)
	assert(source.get_size() == imported.get_size())
	# Direction rows are byte-identical for this fixed-body monster. Comparing
	# the complete first row catches a stale .ctex while avoiding an unnecessary
	# eightfold scan of the same pixels. Godot's alpha-border import may change
	# RGB values on transparent and antialiased edge pixels, so normalize RGB
	# unless the pixel is fully opaque while retaining the complete alpha mask.
	var row_rect := Rect2i(0, 0, source.get_width(), 208)
	var source_bytes := source.get_region(row_rect).get_data()
	var imported_bytes := imported.get_region(row_rect).get_data()
	assert(source_bytes.size() == imported_bytes.size())
	for byte_index in range(0, source_bytes.size(), 4):
		if source_bytes[byte_index + 3] < 255:
			source_bytes[byte_index] = 0
			source_bytes[byte_index + 1] = 0
			source_bytes[byte_index + 2] = 0
		if imported_bytes[byte_index + 3] < 255:
			imported_bytes[byte_index] = 0
			imported_bytes[byte_index + 1] = 0
			imported_bytes[byte_index + 2] = 0
	assert(
		source_bytes == imported_bytes,
		"%s runtime import pixels differ from source PNG; stale .ctex cache"
		% action_name,
	)
