extends "res://tests/crowd_formal_grid_comparison_20261008.gd"

## Fixed v107 diagnostic: only the number of engaged actors changes.
## The 30-engaged arm has exactly the existing comparison layout and can
## reuse its retained evidence; remaining actors use the same legal far list.
func _place_scaling_actors(enemies: Array) -> Dictionary:
	var layout := super._place_scaling_actors(enemies)
	if _scaling_engaged == 30 or layout.actors.is_empty():
		return layout
	var probe: EnemyActor = enemies[0]
	var center := Vector2(layout.center_ground[0], layout.center_ground[1])
	var far: Array[Vector2] = []
	for y in range(3, 62):
		for x in range(3, 34):
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			if point.distance_to(center) > FORMAL_GRID_FAR_MIN_GU and probe._hc_point_walkable(point):
				far.append(point)
	if far.size() < enemies.size() - _scaling_engaged:
		_scaling_failures.append("insufficient_background_sites")
		return layout
	var rows: Array[Dictionary] = []
	for serial in range(enemies.size()):
		var actor: EnemyActor = enemies[serial]
		var ground := Vector2(layout.actors[serial].ground[0], layout.actors[serial].ground[1]) if serial < _scaling_engaged else far[serial - _scaling_engaged]
		actor.set_combat_position(_ground_to_screen(ground), &"v107_cost_growth")
		actor.set_meta("spawn_position", _ground_to_screen(ground))
		rows.append({"serial":serial, "monster_id":actor.monster_id,
			"ground":[ground.x,ground.y], "cell":[floori(ground.x),floori(ground.y)],
			"engaged":serial < _scaling_engaged})
	layout.actors = rows
	layout.layout_sha256 = JSON.stringify(rows).sha256_text()
	return layout

func _append_scaling_result(result: Dictionary) -> void:
	result["growth_contract"] = {"fixed_build_sha":"edae6fdef6a6551a951fab1ea8c6ade43359d603",
		"engaged_requested":_scaling_engaged,"total_actors":34,
		"background_count":34-_scaling_engaged,"physics_ticks":300,
		"changed_input":"engaged population only; same identity order/near sites/far site list/input policy",
		"cpu_only":"headless does not measure GPU or device FPS"}
	super._append_scaling_result(result)

func _scaling_source_hashes() -> Dictionary:
	var hashes := super._scaling_source_hashes()
	hashes["res://tests/crowd_v107_cost_growth_20261008.gd"] = FileAccess.get_sha256("res://tests/crowd_v107_cost_growth_20261008.gd")
	return hashes
