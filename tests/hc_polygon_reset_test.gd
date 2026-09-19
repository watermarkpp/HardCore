extends Node
const Controller := preload("res://scripts/map_editor/polygon/poly_editor_controller.gd")
const Reset := preload("res://scripts/map_editor/polygon/poly_reset.gd")
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Author := preload("res://scripts/map_editor/polygon/poly_authoring.gd")
const Binding := preload("res://scripts/map_editor/polygon/poly_instance_binding.gd")
const Codec := preload("res://scripts/map_editor/map_editor_json_codec.gd")

# Execute production controller + original CommandStack. Only texture and
# ground-raster I/O is suppressed; this is not a replacement reset algorithm.
class InputCanvas extends MapEditorCanvasPreview:
	func _draw() -> void:
		pass
	func set_document(value: Dictionary) -> void:
		document = value
		if is_instance_valid(_hc_polygon_controller):
			_hc_polygon_controller.invalidate_document()
class EditorShell extends Control:
	var preview: Variant
	var sidebar: VBoxContainer
	var status_label: Label
	var command_stack := MapEditorCommandStack.new()
	var current_document: Dictionary
	var current_document_path: String = "user://hc_r3_not_saved.editor.json"
	var _last_build_candidate: Dictionary = {"must_be_invalidated":true}

var errors: Array[String] = []
var checks: int = 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors.append(message)
		push_error("HC_POLYGON_RESET: " + message)
func _ready() -> void:
	call_deferred("run")

func fixture(legacy: bool) -> Dictionary:
	var document: Dictionary = MapEditorTypes.new_map("hc_r3_reset",990993,"R3 reset",Vector2i(80,80))
	document.editor_meta["revision"] = 7
	document.editor_meta["runtime_approved"] = true
	document.editor_meta["unrelated_note"] = "preserved"
	document.layers.collision = [
		{"collision_id":"manual_000001","shape":"rect","data":{"rect":[4,4,1,1]}},
		{"collision_id":"manual_000002","shape":"polygon","data":{"points":[[8,8],[11,8],[11,11]]}}]
	if not legacy:
		document.editor_meta["collision_authority"] = Geo.AUTHORITY
		document.layers.collision = [Author.entry("p1",Geo.rectangle_points(Rect2(4,4,2,2))),
			Author.entry("p2",Geo.rectangle_points(Rect2(8.2,9.3,1.1,2.7)))]
	document.layers.collision_erase = [{"tile":[4,4],"source":"single_cell_erase"}]
	for number: int in range(2):
		var instance: Dictionary = {"instance_id":"inst_%06d" % (number+1),
			"asset_id":"hc_reset_fixture","object_role":"obstacle","layer":"object_base",
			"tile":[20+number*4,20],"footprint_tiles":[2,2],"offset_px":[3.25,-4.5],
			"scale":[1.25,1.5],"rotation_deg":17.0,"anchor_px":[32,64],
			"collision_policy":"solid_footprint","collision_profile_id":"fixture",
			"collision_cells":[[0,0]],"collision_footprint_tiles":[2,2],
			"map_collision_override":"default","navigation_policy":"block_player_and_monster",
			"runtime_export":number==0}
		instance[Binding.FIELD] = [{"id":"local_1","points":[[28,60],[36,60],[32,68]],
			"contract_id":Binding.CONTRACT}]
		document.layers.object_base.append(instance)
	for layer: String in ["npc_points","door_points","map_entrance_points","map_exit_points",
		"respawn_points","monster_spawn","boss_spawn","safe_area","light","region_trigger",
		"interactables","region_semantics","shadow"]:
		document.layers[layer] = [{"fixture_tag":layer,"tile":[30,30],"unrelated":true}]
	return document

func stable_content(document: Dictionary) -> String:
	var result: Dictionary = document.duplicate(true)
	result.layers.erase("collision")
	result.layers.erase("collision_erase")
	for instance: Dictionary in Binding.instances(result):
		instance.erase(Binding.FIELD)
	for name: String in Controller.META_KEYS:
		result.editor_meta.erase(name)
	result.editor_meta.erase("revision")
	result.editor_meta.erase("runtime_approved")
	return Codec.encode(result)

func collision_state(controller: Node, document: Dictionary) -> String:
	return Codec.encode(controller._snapshot(document))

func run() -> void:
	var shell := EditorShell.new()
	add_child(shell)
	shell.sidebar = VBoxContainer.new()
	shell.add_child(shell.sidebar)
	shell.status_label = Label.new()
	shell.add_child(shell.status_label)
	shell.preview = InputCanvas.new()
	shell.preview.size = Vector2(1000,700)
	shell.add_child(shell.preview)
	shell.current_document = fixture(false)
	shell.preview.set_document(shell.current_document)
	var controller := Controller.new()
	shell.add_child(controller)
	controller.setup(shell)
	controller.test_reset_backup_root = "user://hc_r3_reset_backups_%d" % Time.get_ticks_usec()
	await get_tree().process_frame
	check(controller.clear_all_button.text == "清空当前地图全部碰撞，重新绘制", "button wording")
	check(is_instance_valid(controller.clear_all_dialog), "confirmation dialog installed")

	# Button click is only a request: no mutation or implicit save.
	var before: String = Codec.encode(shell.current_document)
	controller.clear_all_button.pressed.emit()
	check(Codec.encode(shell.current_document)==before, "opening confirmation has no mutation")
	check(controller.clear_all_dialog.dialog_text.contains("hc_r3_reset"), "confirmation names current map")
	controller._cancel_clear_all()
	check(not controller._confirm_clear_all().ok, "cancel cannot execute later")
	check(Codec.encode(shell.current_document)==before, "cancel preserves document")
	check(not shell.command_stack.undo(), "cancel does not push an undo record")

	# Refuse a stale confirmation even when map_id stays the same.
	controller._request_clear_all()
	shell.current_document.editor_meta["unrelated_note"] = "edited after dialog"
	before = Codec.encode(shell.current_document)
	check(not controller._confirm_clear_all().ok, "stale same-document confirmation rejected")
	check(Codec.encode(shell.current_document)==before, "stale rejection preserves new edit")
	controller._request_clear_all()
	shell.current_document = shell.current_document.duplicate(true)
	before = Codec.encode(shell.current_document)
	check(not controller._confirm_clear_all().ok, "replaced document identity rejected")
	check(Codec.encode(shell.current_document)==before, "cross-session rejection preserves document")

	# Backup failure is an atomic rejection: no revision, stack or candidate change.
	controller._request_clear_all()
	before = Codec.encode(shell.current_document)
	Reset.test_fail_backup = true
	var failed: Dictionary = controller._confirm_clear_all()
	Reset.test_fail_backup = false
	check(not failed.ok, "forced backup failure refuses reset")
	check(Codec.encode(shell.current_document)==before, "backup failure has zero document mutation")
	check(shell._last_build_candidate.has("must_be_invalidated"), "failed reset retains build candidate")
	check(not shell.command_stack.undo(), "failed reset does not push undo")

	# Exercise a real file obstruction, not only the test flag. Production
	# must reject BEFORE calling recursive mkdir (which logs an engine ERROR).
	var correct_root: String = controller.test_reset_backup_root
	var not_directory: String = "user://hc_r3_backup_file_%d" % Time.get_ticks_usec()
	var blocking_file: FileAccess = FileAccess.open(not_directory,FileAccess.WRITE)
	check(blocking_file != null,"create isolated backup failure fixture")
	if blocking_file != null:
		blocking_file.store_string("This is a file, not a backup directory.")
		blocking_file.close()
		for blocked_root: String in [not_directory, not_directory.path_join("nested/child")]:
			controller.test_reset_backup_root = blocked_root
			controller._request_clear_all()
			before = Codec.encode(shell.current_document)
			var obstructed: Dictionary = controller._confirm_clear_all()
			check(not obstructed.ok,"real backup directory failure refuses reset")
			check(obstructed.get("errors",[]).has("reset_backup_path_is_file"),"file obstruction gets precise preflight failure")
			check(Codec.encode(shell.current_document)==before,"real I/O failure leaves document unchanged")
			check(not shell.command_stack.undo(),"real I/O failure leaves undo history unchanged")
			check(shell._last_build_candidate.has("must_be_invalidated"),"real I/O failure preserves candidate")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(not_directory))
	controller.test_reset_backup_root = correct_root

	# Polygon and legacy modes both get a truly empty clean slate, then one undo.
	for legacy: bool in [false,true]:
		shell.command_stack.clear()
		shell.current_document = fixture(legacy)
		shell.preview.set_document(shell.current_document)
		var preserved: String = stable_content(shell.current_document)
		var state_before: String = collision_state(controller,shell.current_document)
		var document_before_text: String = Codec.encode(shell.current_document)
		var counts: Dictionary = Reset.summary(shell.current_document)
		check(counts.ok and counts.bound_polygons==2, "count exported and nonexported bound shapes")
		var prepared: Dictionary = Reset.plan(shell.current_document,shell.current_document_path)
		check(prepared.ok, "reset plan accepted")
		if legacy and prepared.ok:
			check(not prepared.backup_payload.effective_legacy_walkability.blocked_tiles.has("4,4"),
				"legacy backup reflects prior erasure, not raw shape union")
		controller._request_clear_all()
		var result: Dictionary = controller._confirm_clear_all()
		check(result.ok, "confirmed reset succeeds: %s" % str(result.get("errors",[])))
		if not result.ok:
			continue
		check(Geo.enabled(shell.current_document), "clean slate switches directly to polygon authority")
		check(shell.current_document.layers.collision.is_empty(), "all map and legacy shapes removed")
		check(shell.current_document.layers.collision_erase.is_empty(), "old erase records removed")
		for instance: Dictionary in Binding.instances(shell.current_document):
			check(not instance.has(Binding.FIELD), "all bindings removed including runtime_export=false")
		check(stable_content(shell.current_document)==preserved, "all noncollision fields identical")
		check(shell.current_document.editor_meta.revision==8, "reset increments revision exactly once")
		check(not shell.current_document.editor_meta.runtime_approved, "reset revokes approval")
		check(shell._last_build_candidate.is_empty(), "reset invalidates candidate")
		check(FileAccess.file_exists(result.backup_path), "verified backup exists")
		var backup: Dictionary = Reset.read_backup(str(result.backup_path))
		check(bool(backup.get("ok",false)), "backup passes production disk recovery verification")
		if bool(backup.get("ok",false)):
			check(backup.document_json == document_before_text, "backup preserves exact complete pre-reset JSON bytes")
			check(str(backup.document_json).sha256_text()==str(backup.document_sha256), "backup complete document hash valid")
			# Both sides are in the DISK domain, whose numbers are float. Do not
			# require encode(parse(E)) == E. Raw E equality is checked above;
			# the in-memory Undo byte-equivalence checks below remain unchanged.
			var expected_disk_document: Dictionary = Codec.decode(document_before_text)
			check(collision_state(controller,backup.document)==collision_state(controller,expected_disk_document), "backup includes complete previous collision state")
		var parts: Dictionary = Author.prepare(shell.current_document)
		check(parts.ok and parts.parts.is_empty() and parts.entries.is_empty(), "retained instance policies cannot resurrect shapes")
		var walk: Dictionary = MapEditorCollisionService.build_walkability(shell.current_document)
		check(walk.ok and walk.blocked_tiles.is_empty(), "diagnostic bridge remains empty")
		check(shell.command_stack.undo(), "one undo exists")
		check(collision_state(controller,shell.current_document)==state_before, "one undo restores authority, map, binding and erase state")
		check(stable_content(shell.current_document)==preserved, "undo preserves noncollision fields")
		check(shell.current_document.editor_meta.revision==9, "undo is a new edit, not a stale revision rollback")
		check(shell.command_stack.redo(), "one redo exists")
		check(Geo.enabled(shell.current_document) and shell.current_document.layers.collision.is_empty(), "redo clean slate")
		check(shell.current_document.editor_meta.revision==10, "redo revision increments once")

	# A missing optional erase layer must remain missing when undo restores it.
	shell.command_stack.clear()
	shell.current_document = fixture(false)
	shell.current_document.layers.erase("collision_erase")
	controller._request_clear_all()
	check(controller._confirm_clear_all().ok, "reset accepts absent optional erase layer")
	check(shell.command_stack.undo(), "undo absent erase case")
	check(not shell.current_document.layers.has("collision_erase"), "undo restores exact key presence")
	var duplicate: Dictionary = fixture(false)
	duplicate.layers.object_base[1].instance_id = duplicate.layers.object_base[0].instance_id
	check(not Reset.plan(duplicate,"fixture").ok, "ambiguous bound owners fail closed before backup")
	_test_backup_contract(controller.test_reset_backup_root.path_join("r31_contract"))
	Reset.test_fail_backup = false
	shell.queue_free()
	await get_tree().process_frame
	if errors.is_empty():
		print("HC_POLYGON_RESET_TEST_PASS checks=",checks)
	get_tree().quit(0 if errors.is_empty() else 1)


# Real production writer/reader checks, without modifying any existing map.
func _test_backup_contract(root: String) -> void:
	var source: Dictionary = fixture(false)
	source.editor_meta["r31_values"] = {
		"mixed": [80,80.0,-0.0,0.015625,-4.5,true,false,null,[],{}],
		"large_integer": 9007199254740993,
		"unicode": "原始碰撞\n保留\t纹理与锚点",
		"lookalike": "80 is a string, not a number"}
	var original_text: String = Codec.encode(source)
	var roundtripped: Dictionary = Codec.decode(original_text)
	check(Codec.encode(roundtripped)!=original_text, "fixture reproduces native int to JSON float spelling change")
	var prepared: Dictionary = Reset.plan(source,"user://r31_fixture.editor.json")
	check(prepared.ok,"raw backup plan accepts mixed numbers")
	if not prepared.ok:
		return
	var payload: Dictionary = prepared.backup_payload
	check(str(payload.document_json)==original_text,"plan captures original serialization exactly once")
	var envelope_roundtrip: Variant = JSON.parse_string(Codec.encode(payload))
	check(envelope_roundtrip is Dictionary,"envelope JSON roundtrip")
	if not envelope_roundtrip is Dictionary:
		return
	var recovered: Dictionary = Reset.validate_backup_payload(envelope_roundtrip)
	check(recovered.ok,"raw document hash survives envelope parse")
	if recovered.ok:
		check(str(recovered.document_json)==original_text,"raw serialization including large integer is not reformatted")
		check(str(recovered.document_json).to_utf8_buffer()==original_text.to_utf8_buffer(),"numeric tokens and Unicode bytes unchanged")
	# Already-loaded editor documents (whose numbers are float) also work.
	var loaded_plan: Dictionary = Reset.plan(roundtripped,"user://r31_loaded.editor.json")
	check(loaded_plan.ok,"backup supports already parsed document")
	if loaded_plan.ok:
		var loaded_backup: Dictionary = Reset.write_backup(loaded_plan.backup_payload,root.path_join("loaded"))
		check(loaded_backup.ok,"loaded document backup writes and verifies")

	var tampered: Dictionary = payload.duplicate(true)
	tampered.document_json = str(tampered.document_json) + " "
	check(not Reset.validate_backup_payload(tampered).ok,"even whitespace tampering fails raw document hash")
	tampered = payload.duplicate(true)
	tampered.document_sha256 = "0".repeat(64)
	check(not Reset.validate_backup_payload(tampered).ok,"incorrect inner hash rejected")
	tampered = payload.duplicate(true)
	tampered.erase("document_json")
	check(not Reset.validate_backup_payload(tampered).ok,"missing raw source rejected")
	var bad_json: Dictionary = payload.duplicate(true)
	bad_json.document_json = "{\"map_id\":"
	bad_json.document_sha256 = str(bad_json.document_json).sha256_text()
	check(not Reset.validate_backup_payload(bad_json).ok,"correct hash never excuses invalid document JSON")
	var old_backup: Dictionary = {"contract_id":Reset.CONTRACT,"document":source,
		"document_sha256":Reset.fingerprint(source)}
	check(not Reset.validate_backup_payload(old_backup).ok,"old R3 format rejected explicitly, not silently rehashed")
	check(Codec.encode(source)==original_text,"all validation leaves source document untouched")

	var written: Dictionary = Reset.write_backup(payload,root)
	check(written.ok,"mixed-number backup writes and is recoverable on disk")
	if not written.ok:
		return
	var path: String = str(written.path)
	var disk: Dictionary = Reset.read_backup(path)
	check(disk.ok and str(disk.get("document_json",""))==original_text,"production recovery returns original document bytes")
	var repeated: Dictionary = Reset.write_backup(payload,root)
	check(repeated.ok and str(repeated.get("path",""))==path,"identical backup reuse is validated and idempotent")
	var exact_backup: String = FileAccess.get_file_as_string(path)
	var whole_hash: String = exact_backup.sha256_text()
	check(path.get_file()=="before_%s.json" % whole_hash,"outer filename binds complete backup including legacy metadata")
	# Intentional corruption stays in this isolated test backup only.
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	check(file!=null,"open isolated corruption fixture")
	if file == null:
		return
	file.store_string(exact_backup + " ")
	file.close()
	check(not Reset.read_backup(path).ok,"whole-file byte corruption rejected")
	check(not Reset.write_backup(payload,root).ok,"corrupted existing backup never overwritten")
	file = FileAccess.open(path,FileAccess.WRITE)
	if file != null:
		file.store_string(exact_backup.substr(0,exact_backup.length()/2))
		file.close()
		check(not Reset.read_backup(path).ok,"truncated backup rejected")
	file = FileAccess.open(path,FileAccess.WRITE)
	if file != null:
		file.store_buffer(PackedByteArray([255,254,253]))
		file.close()
		check(not Reset.read_backup(path).ok,"binary corruption rejected before UTF8 decoder can log")
		check(not Reset.write_backup(payload,root).ok,"binary-corrupted existing backup refused without decoding or overwriting")
	file = FileAccess.open(path,FileAccess.WRITE)
	if file != null:
		file.store_string(exact_backup)
		file.close()
	check(Reset.read_backup(path).ok,"fixture bytes restored for evidence")
	check(Codec.encode(source)==original_text,"writer and reader never mutate the source document")
