extends "res://tests/wall_atomic_foreground_occlusion_runtime_test.gd"

# Additional bounded regressions reuse the existing exact pixel, hash and
# crossing assertions. The original all-published scene remains unchanged.
@export_enum("authored_fixture", "orc_real_pixels", "atomic_crossings") var subset := "authored_fixture"

func _run() -> void:
	MapAssetCatalogService.invalidate_cache()
	if subset == "authored_fixture":
		await _assert_static_authored_bridge_fixture()
	elif subset == "orc_real_pixels":
		await _assert_orc_tomb_f1_real_bridge()
	else:
		var fixture := _shape_fixture()
		var commands := VisualGeometry.sorted_draw_commands(fixture.instances)
		var groups := _assert_atomic_command_contract(commands)
		await _assert_world_background_graph(fixture, commands, groups)
		_assert_monotonic_crossing(commands)
	print("WALL_MATERIAL_BRIDGE_SUBSET_PASS subset=", subset)
	get_tree().quit(0)
