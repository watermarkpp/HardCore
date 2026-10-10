extends Node

const MapEditorAppScript := preload("res://scripts/map_editor/map_editor_app.gd")
const MapEditorTypes := preload("res://scripts/map_editor/map_editor_types.gd")
const GroundService := preload("res://scripts/map_editor/map_editor_ground_service.gd")
const SemanticService := preload("res://scripts/map_editor/map_editor_gameplay_semantic_service.gd")
const AssetCatalog := preload("res://scripts/map_assets/map_asset_catalog_service.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")

var proof := Proof.new()
var errors: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value, label)
	if not value:
		errors.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var nonce := Time.get_ticks_usec()
	var document := MapEditorTypes.new_map_from_catalog("sandbox_64", "quest_room", 991818, "B18 editor contract")
	document.editor_meta.workspace = "user://b18_editor_contract_%d" % nonce
	check(bool(GroundService.initialize(document).get("ok", false)), "ground workspace initializes")
	var app = MapEditorAppScript.new()
	app.load_default_workspace_on_ready = false
	app.persist_last_document_path = false
	add_child(app)
	await get_tree().process_frame
	await get_tree().process_frame
	app._adopt_new_document(document, "B18 contract", "user://b18_editor_contract.editor.json")

	# EDIT-001: the formal ground path must return the real write result to the App,
	# so a successful write updates the preview and reports success.
	var brush_id := ""
	for candidate: Dictionary in AssetCatalog.palette_assets():
		if str(candidate.get("asset_type", "")) == "ground_brush" and bool(candidate.get("placeable", false)):
			brush_id = str(candidate.get("asset_id", candidate.get("id", "")))
			if not brush_id.is_empty():
				break
	check(not brush_id.is_empty(), "formal ground brush is available")
	app.command_stack.clear()
	app._on_ground_paint_requested(Vector2i(2, 2), brush_id)
	check(app.status_label.text.begins_with("绘制 "), "ground write result reaches App success path")
	check(app.command_stack.can_undo(), "successful ground write is undoable")
	check(app.preview._paint_overrides.has("2,2"), "successful ground write refreshes preview override")

	# EDIT-002: a rejected semantic move must not create a history entry or alter
	# the object when Ctrl+Z later consumes the previous accepted command.
	var light := SemanticService.add_entry(document, "light", Vector2i(0, 5), {"radius_gu": 3.0})
	check(bool(light.get("ok", false)), "light semantic fixture is created")
	var light_id := str(light.entry.semantic_id)
	app.command_stack.clear()
	app.preview.selected_selectable_id = light_id
	app._on_selectable_move_requested(light_id, Vector2i(1, 0))
	check(SemanticService.find_entry(document, light_id).get("tile", []) == [1, 5], "accepted move changes semantic tile")
	check(app.command_stack.undo(), "accepted move can be undone")
	check(app.command_stack.can_redo(), "undo leaves an accepted redo branch")
	app._on_selectable_move_requested(light_id, Vector2i(-1, 0))
	var rejected_light := SemanticService.find_entry(document, light_id)
	check(rejected_light.get("tile", []) == [0, 5], "rejected move leaves semantic tile unchanged")
	check(not app.command_stack.can_undo(), "rejected move is absent from undo history")
	check(app.command_stack.can_redo(), "rejected move preserves the accepted redo branch")
	check(app.command_stack.redo(), "preserved redo branch remains executable")
	check(SemanticService.find_entry(document, light_id).get("tile", []) == [1, 5], "redo reapplies only the accepted move")

	# EDIT-003: each supported selected kind sends the fields that its editor
	# actually exposes through the production update button.
	app.semantic_radius.value = 4.0
	app._on_update_selected_semantic_pressed()
	check(is_equal_approx(float(SemanticService.find_entry(document, light_id).get("radius_gu", 0.0)), 4.0), "light radius updates from selected editor")
	var spawn := SemanticService.add_entry(document, "monster_spawn", Vector2i(6, 6), {"monster_id": 1, "count": 1, "respawn_seconds": 60, "max_alive": 1, "radius_gu": 2.0})
	check(bool(spawn.get("ok", false)), "monster semantic fixture is created")
	var spawn_id := str(spawn.entry.semantic_id)
	app.preview.selected_selectable_id = spawn_id
	app._sync_semantic_editor_fields(SemanticService.find_entry(document, spawn_id))
	app.semantic_count.value = 4
	app.semantic_respawn.value = 240
	app.semantic_max_alive.value = 7
	app.semantic_radius.value = 5.0
	app._on_update_selected_semantic_pressed()
	var updated_spawn := SemanticService.find_entry(document, spawn_id)
	check(int(updated_spawn.get("count", 0)) == 4 and int(updated_spawn.get("respawn_seconds", 0)) == 240 and int(updated_spawn.get("max_alive", 0)) == 7, "monster count respawn and max_alive update")
	check(is_equal_approx(float(updated_spawn.get("radius_gu", 0.0)), 5.0), "monster radius updates")
	var npc := SemanticService.add_entry(document, "npc", Vector2i(8, 8), {"npc_id": "npc.bich_guard", "content_id": "npc.bich_guard", "facing": "south"})
	check(bool(npc.get("ok", false)), "npc semantic fixture is created")
	var npc_id := str(npc.entry.semantic_id)
	app.preview.selected_selectable_id = npc_id
	app._sync_semantic_editor_fields(SemanticService.find_entry(document, npc_id))
	for index in app.semantic_facing.item_count:
		if str(app.semantic_facing.get_item_metadata(index)) == "east":
			app.semantic_facing.select(index)
			break
	app._on_update_selected_semantic_pressed()
	check(str(SemanticService.find_entry(document, npc_id).get("facing", "")) == "east", "npc facing updates from selected editor")

	app.queue_free()
	await get_tree().process_frame
	var receipt_ok := proof.write_receipt("map_editor_semantic_command_contract_20261010_test", checks, errors.size())
	if not receipt_ok:
		errors.append("receipt write failed")
	print(("FRAMEWORK_MAP_EDITOR_SEMANTIC_COMMAND_CONTRACT_PASS" if errors.is_empty() else "FRAMEWORK_MAP_EDITOR_SEMANTIC_COMMAND_CONTRACT_FAIL") + " checks=" + str(checks) + " errors=" + str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
