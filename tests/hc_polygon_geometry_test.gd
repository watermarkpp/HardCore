extends Node
## Downstream Godot test. This package does NOT claim it was run in the authoring sandbox.
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Author := preload("res://scripts/map_editor/polygon/poly_authoring.gd")
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
const Controller := preload("res://scripts/map_editor/polygon/poly_editor_controller.gd")
const CommandStack := preload("res://scripts/map_editor/map_editor_command_stack.gd")
var errors: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors.append(message)
		push_error("HC_POLYGON_GEOMETRY: " + message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var size_gu := Vector2i(12, 12)
	for bad: Array in [[], [[0, 0], [1, 1]], [[0, 0], [2, 2], [0, 2], [2, 0]], [[0, 0], [1, 0], [2, 0]], [[0, 0], [NAN, 1], [1, 0]], [[false, 0], [2, 0], [0, 2]], [[0, 0], [1, 0], [1, 0], [0, 1]]]:
		check(not Geo.validate(bad, size_gu).ok, "reject invalid/simple-polygon input")
	var concave := PackedVector2Array([Vector2(.13, .2), Vector2(5.1, .2), Vector2(5.1, 1.3), Vector2(1.4, 1.3), Vector2(1.4, 5.2), Vector2(.13, 5.2)])
	var doc := {"design": {"design_size": [12, 12]}, "editor_meta": {"collision_authority": Geo.AUTHORITY},
		"layers": {"collision": [Author.entry("concave", concave)]}}
	var prepared := Author.prepare(doc)
	check(prepared.ok, "concave authoring decomposes")
	if prepared.ok:
		var index := Index.new()
		check(index.setup(size_gu, prepared.parts), "convex pieces index")
		check(index.point_blocked(Vector2(.5, 4)), "L leg blocked")
		check(not index.point_blocked(Vector2(3, 3)), "L concavity not filled")
		check(not index.circle_blocked(Vector2(3, 3), .3), "open concavity body fits")
	var thin := [[5.001, 0], [5.007, 0], [5.007, 12], [5.001, 12]]
	var thin_index := Index.new()
	check(thin_index.setup(size_gu, [thin]), "thin wall index")
	check(thin_index.capsule_blocked(Vector2(1, 5), Vector2(9, 5), 0.0), "continuous segment cannot skip thin wall")
	check(not thin_index.capsule_blocked(Vector2(1, 3), Vector2(4, 3), .2), "clear segment stays clear")
	check(thin_index.footprint_blocked(Geo.rectangle_points(Rect2(4.9, 4.7, .3, .6))), "full foot intersects wall even when center is open")
	check(not thin_index.footprint_blocked(Geo.rectangle_points(Rect2(4.0, 4.7, .3, .6))), "legal foot not rolled back")
	var blocked: Dictionary = {}
	for y: int in range(8):
		for x: int in range(9):
			if x != 4:
				blocked["%d,%d" % [x, y]] = true
	var old := {"map_id": "test_old", "design": {"design_size": [12, 12]}, "editor_meta": {"revision": 7},
		"layers": {"collision": [{"shape": "rect", "data": {"rect": [0, 0, 9, 8]}}],
			"collision_erase": [{"tile": [4, 3]}], "object_base": [{"asset_id": "not_changed", "tile": [2, 2]}],
			"door_points": [{"semantic_id": "unchanged_door", "tile": [4, 3]}]}}
	var old_text := JSON.stringify(old, "", true, true)
	var migrated := Author.migrate(old, {"map_size": [12, 12], "blocked_tiles": blocked})
	check(migrated.ok, "legacy final walkability migration")
	check(JSON.stringify(old, "", true, true) == old_text, "migration never mutates input")
	if migrated.ok:
		var new_doc: Dictionary = migrated.document
		check(new_doc.layers.object_base == old.layers.object_base, "art/layout preserved")
		check(new_doc.layers.door_points == old.layers.door_points, "doors preserved")
		check(new_doc.layers.collision_erase == old.layers.collision_erase, "erase audit preserved")
		check(migrated.legacy_rect_count == 2, "exact row merging without smoothing")
		var rebuilt := Author.walkability(new_doc)
		check(rebuilt.ok and rebuilt.blocked_tiles == blocked, "every effective old cell preserved, opening not resurrected")
		var cut := Author.clear_legacy_region(new_doc.layers.collision, Rect2(1.25, 1.25, 1.5, 2.0))
		var changed := new_doc.duplicate(true)
		changed.layers.collision = cut
		var compiled := Author.prepare(changed)
		check(compiled.ok, "local rectangular removal remains valid polygons")
		var cut_index := Index.new()
		if compiled.ok and cut_index.setup(size_gu, compiled.parts):
			check(not cut_index.point_blocked(Vector2(2, 2)), "local old region removed")
			check(cut_index.point_blocked(Vector2(.5, 2)), "uncut old wall remains")
			check(not cut_index.point_blocked(Vector2(4.5, 3)), "old doorway still open after cut")
	var misleading := Author.entry("not_a_rectangle", concave, "legacy_final")
	check(Author.clear_legacy_region([misleading], Rect2(0, 0, 10, 10))[0] == misleading, "never erase an arbitrary polygon by its bounding box")
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(doc, "  ", true, true))
	check(roundtrip.layers.collision[0].data.points == doc.layers.collision[0].data.points, "fractional vertices survive JSON")
	check(not Geo.enabled(old), "opening old document does not implicitly activate new mode")
	## Existing command stack remains the transaction owner; no alternate global undo stack.
	var stack := CommandStack.new()
	var counter := {"value": 0}
	var do_action: Callable = func() -> void: counter.value = 1
	var undo_action: Callable = func() -> void: counter.value = 0
	check(stack.execute({"do": do_action, "undo": undo_action}), "original command stack accepts transaction")
	check(counter.value == 1 and stack.undo() and counter.value == 0, "undo works")
	check(stack.redo() and counter.value == 1, "redo works")
	check(Controller != null, "editor controller script preloads with production dependencies")
	if errors.is_empty():
		print("HC_POLYGON_GEOMETRY_TEST_PASS checks=", checks)
	get_tree().quit(0 if errors.is_empty() else 1)
