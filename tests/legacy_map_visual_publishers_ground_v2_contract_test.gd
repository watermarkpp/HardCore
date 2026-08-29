extends Node

const MapEditorCoordinate := preload(
	"res://scripts/map_editor/map_editor_coordinate.gd"
)
const GDSCRIPT_PUBLISHERS := [
	"res://tools/map_editor/publish_wooma_runtime_visuals.gd",
	"res://tools/map_editor/publish_phase1_mine_runtime_visuals.gd",
	"res://tools/map_editor/publish_orc_tomb_runtime_visuals.gd",
]
const PYTHON_PACKAGER := (
	"res://tools/map_editor/package_bich_runtime_visuals.py"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var design_size := Vector2i(80, 80)
	assert(
		MapEditorCoordinate.ground_image_size(design_size)
		== Vector2i(5120, 2560)
	)
	assert(
		MapEditorCoordinate.ground_pixel_center(design_size)
		== Vector2(2560.0, 1264.0)
	)
	for path: String in GDSCRIPT_PUBLISHERS:
		var script: Variant = load(path)
		assert(script is Script, "legacy publisher failed to compile: %s" % path)
		_assert_gdscript_publisher_contract(path, _read_text(path))
	_assert_python_packager_contract(_read_text(PYTHON_PACKAGER))
	print(
		"LEGACY_MAP_VISUAL_PUBLISHERS_GROUND_V2_CONTRACT_PASS "
		+ "publishers=4 center_80x80=2560,1264"
	)
	get_tree().quit(0)


func _assert_gdscript_publisher_contract(path: String, source: String) -> void:
	assert(
		source.contains("res://scripts/map_editor/map_editor_coordinate.gd"),
		"MapEditorCoordinate preload missing: %s" % path,
	)
	assert(
		source.contains("manifest.get(\"coordinate_contract_id\", \"\")"),
		"manifest coordinate contract gate missing: %s" % path,
	)
	assert(
		source.contains("MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID"),
		"current ground contract constant missing: %s" % path,
	)
	assert(
		source.contains("\"ground_coordinate_contract_id\""),
		"visual ground contract output missing: %s" % path,
	)
	assert(
		source.contains("MapEditorCoordinate.ground_pixel_center"),
		"shared v2 center function missing: %s" % path,
	)
	for forbidden: String in [
		"float(pixel_size[1]) * 0.5",
		"float(pixel_size[1])/2.0",
		"pixel_size[1] / 2",
	]:
		assert(
			not source.contains(forbidden),
			"legacy vertical midpoint formula returned: %s:%s"
			% [path, forbidden],
		)


func _assert_python_packager_contract(source: String) -> void:
	for required: String in [
		"GROUND_COORDINATE_CONTRACT_ID = \"isometric_cell_center_64x32_v2\"",
		"manifest.get(\"coordinate_contract_id\")",
		"\"ground_coordinate_contract_id\": GROUND_COORDINATE_CONTRACT_ID",
		"def ground_pixel_center_v2(design_size, ground_size):",
		"float(ground_size[0]) / 2.0",
		"float(width + height - 2) * 8.0",
	]:
		assert(source.contains(required), "Python v2 contract missing: %s" % required)
	for forbidden: String in [
		"ground_size[1] / 2",
		"ground_size[1] / 2.0",
	]:
		assert(
			not source.contains(forbidden),
			"Python legacy vertical midpoint formula returned: %s" % forbidden,
		)


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "source missing: %s" % path)
	var text := file.get_as_text()
	file.close()
	return text
