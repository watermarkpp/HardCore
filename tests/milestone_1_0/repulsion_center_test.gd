extends Node
const Geometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const Cells := preload("res://scripts/skills/skill_geometry_service.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const Visual := preload("res://scripts/caster_skill_visual_effect.gd")
const Fixtures := preload("res://tests/game_root_wizard_geometry_integration_test.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "法师"
	PlayerState.level = 60
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		enemy.set_process(false)
		enemy.set_physics_process(false)
	var base: Vector2i = game._canonical_screen_px_to_grid_cell(game.player.global_position)
	var definition: Dictionary = SkillDataLoader.skill("wizard.repulsion_ring")
	var fixture := Fixtures.new()
	var checked := 0
	for fraction: Vector2 in [Vector2.ZERO, Vector2(0.49,0.49), Vector2(-0.49,-0.49), Vector2(0.49,-0.49), Vector2(-0.49,0.49)]:
		var center := Vector2(base) + fraction
		var coordinate: Dictionary = game._canonical_snapshot_absolute_context(center)
		var validation: Dictionary = game._canonical_snapshot_validation_context(center)
		var cells := Cells.cells(definition, base, Vector2i.DOWN)
		var snapshot := Geometry.create_exact_cell_union_release_snapshot("wizard.repulsion_ring", "center-test", center, cells, coordinate)
		assert(Snapshot.validate_for_consumer(snapshot,validation).valid)
		assert(snapshot.geometry_cells_grid_steps.size()==8)
		var bounds: Rect2 = Snapshot.ground_aabb(snapshot).bounds_ground_gu
		assert(bounds.get_center().is_equal_approx(center), "ring must follow subcell footpoint")
		var cells_only := snapshot.duplicate(true)
		cells_only.erase("polygons_ground_gu")
		assert((Snapshot.ground_aabb(cells_only).bounds_ground_gu as Rect2).get_center().is_equal_approx(center))
		var invalid := snapshot.duplicate(true)
		invalid["cell_origin_offset_gu"] = Vector2.INF
		assert(not Snapshot.validate_for_consumer(invalid,validation).valid)
		for direction: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			assert(Snapshot.intersects_target_combat_footprint_ground_gu(snapshot,center+direction*1.7,0.25))
			assert(not Snapshot.intersects_target_combat_footprint_ground_gu(snapshot,center+direction*1.8,0.25))
			checked += 2
		game.player.global_position = game._canonical_ground_gu_to_screen_px(center)
		# Exercises the actual target broadphase and post-snapshot selection,
		# including the old redundant snapped-cell filter.
		var direction := Vector2.RIGHT if fraction.x >= 0 else Vector2.LEFT
		var enemy: EnemyActor = fixture._make_enemy_at_fractional_tile(game,game.player,center+direction*1.65,"抗拒边缘")
		enemy.combat_radius_gu = 0.25
		enemy.set_combat_position(game._canonical_ground_gu_to_screen_px(center+direction*1.65), &"repulsion_test")
		var context: Dictionary = game._canonical_target_context(definition,game.player.global_position,Vector2.DOWN,false)
		var found := false
		for entry: Dictionary in context.targets:
			if entry.instance_id == enemy.get_instance_id(): found = true
		assert(found, "production selection must share centered ring at %s" % fraction)
		enemy.queue_free()
		await get_tree().process_frame
		var effect := Visual.new()
		var visual_context := Geometry.snapshot_visual_projection_context(snapshot,game.player.global_position,Callable(game,"_canonical_ground_gu_to_screen_px"),validation)
		visual_context["skill_footprint_snapshot"] = snapshot
		visual_context["snapshot_validation_context"] = validation
		effect.setup(game.player.global_position,"wizard.repulsion_ring",72,1,Vector2.DOWN,game.player,"",visual_context)
		game.add_child(effect)
		assert(effect.visual_loaded)
		var sprite = effect._sprites[0]
		assert(sprite.visual_bounds_center().is_equal_approx(Vector2.ZERO), "art source offset must be rebased around actor")
		assert(effect.global_position.is_equal_approx(game.player.global_position))
		effect.queue_free()
		await get_tree().process_frame
	fixture.free()
	game.queue_free()
	await get_tree().process_frame
	print("REPULSION_CENTER_PASS boundary_checks=%d" % checked)
	get_tree().quit()
