extends Node


const EXPECTED := {
	"user.2a66da10acdafadf": ["雕塑 001", Vector2i(4, 4), Vector2i(196, 443)],
	"user.abf0bff8b4111ffa": ["雕塑 002", Vector2i(4, 4), Vector2i(181, 428)],
	"user.bf1a8323ba9865d2": ["雕塑 003", Vector2i(4, 4), Vector2i(96, 433)],
	"user.d08a9a87bd323625": ["雕塑 004", Vector2i(4, 4), Vector2i(133, 433)],
	"user.12798528952dee3c": ["雕塑 005", Vector2i(4, 4), Vector2i(183, 415)],
	"user.e669572580d701f7": ["雕塑 006", Vector2i(4, 4), Vector2i(139, 413)],
	"user.fd2ef972b3611919": ["雕塑 007", Vector2i(3, 3), Vector2i(215, 424)],
	"user.5bc26f0181587097": ["雕塑 008", Vector2i(3, 3), Vector2i(152, 413)],
	"user.0da97f08519bd179": ["雕塑 009", Vector2i(3, 3), Vector2i(152, 415)],
	"user.57aeb1b2b35adda0": ["雕塑 010", Vector2i(3, 3), Vector2i(160, 398)],
	"user.2a4ca216beb37aa9": ["雕塑 011", Vector2i(3, 3), Vector2i(201, 400)],
	"user.d2ca69e761034ea9": ["雕塑 012", Vector2i(3, 3), Vector2i(160, 398)],
	"user.969ed3f30f6855af": ["雕塑 029", Vector2i(4, 4), Vector2i(181, 330)],
	"user.ea1b12b1c0e8c494": ["雕塑 030", Vector2i(4, 4), Vector2i(181, 330)],
	"user.6b2dffcfdd0d208d": ["雕塑 031", Vector2i(4, 4), Vector2i(137, 434)],
	"user.7e27f8885870ab61": ["雕塑 032", Vector2i(4, 4), Vector2i(96, 436)],
	"user.c8db196bd1c1b209": ["雕塑 033", Vector2i(4, 4), Vector2i(133, 432)],
	"user.2a497c7587545a48": ["雕塑 034", Vector2i(4, 4), Vector2i(139, 409)],
	"user.aa1eed4e6f085590": ["雕塑 035", Vector2i(3, 3), Vector2i(140, 411)],
	"user.f2fff8dc89de5453": ["雕塑 036", Vector2i(3, 3), Vector2i(190, 413)],
}


func _ready() -> void:
	MapAssetCatalogService.invalidate_cache()
	var sculpture_names: Array[String] = []
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		if str(asset.get("package_id", "")) == "mse_xzsc_sculpture_v3":
			sculpture_names.append(str(asset.get("display_name", "")))
	assert(sculpture_names.size() == 36)
	for index: int in sculpture_names.size():
		assert(sculpture_names[index] == "雕塑 %03d" % (index + 1))

	for asset_id: String in EXPECTED:
		var expected: Array = EXPECTED[asset_id]
		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), asset_id)
		assert(str(effective.get("display_name", "")) == str(expected[0]), asset_id)
		var footprint := Vector2i(
			int(effective.get("footprint_tiles", [0, 0])[0]),
			int(effective.get("footprint_tiles", [0, 0])[1])
		)
		var occupancy := Vector2i(
			int(effective.get("occupancy_footprint_tiles", [0, 0])[0]),
			int(effective.get("occupancy_footprint_tiles", [0, 0])[1])
		)
		var visual := Vector2i(
			int(effective.get("visual_footprint_tiles", [0, 0])[0]),
			int(effective.get("visual_footprint_tiles", [0, 0])[1])
		)
		var base := Vector2i(
			int(effective.get("base_footprint_tiles", [0, 0])[0]),
			int(effective.get("base_footprint_tiles", [0, 0])[1])
		)
		var anchor := Vector2i(
			int(effective.get("anchor_px", [0, 0])[0]),
			int(effective.get("anchor_px", [0, 0])[1])
		)
		assert(footprint == expected[1], asset_id)
		assert(occupancy == expected[1], asset_id)
		assert(visual == expected[1], asset_id)
		assert(base == expected[1], asset_id)
		assert(anchor == expected[2], asset_id)

	print("MSE_XZSC_SCULPTURE_VERIFIED_CALIBRATION_PASS")
	get_tree().quit(0)
