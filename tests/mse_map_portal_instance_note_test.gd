extends Node

const PORTAL_ASSET_ID := "user.boss_entrance.20260823.confusion_hall"
const NON_PORTAL_ASSET_ID := "mse.small_decor.001"
const NOTE := "N方向连接祖玛寺庙二层 S方向入口"
const SAVE_PATH := "user://mse_map_portal_instance_note_test/editor.json"


func _ready() -> void:
	var document := MapEditorTypes.new_map(
		"mse_portal_note_test",
		990991,
		"入口备注测试",
		Vector2i(80, 80)
	)
	var placed := MapEditorInstanceService.create_instance(
		document,
		PORTAL_ASSET_ID,
		"terrain",
		Vector2i(20, 20),
		"object_base"
	)
	assert(bool(placed.get("ok", false)), str(placed.get("errors", [])))
	var instance_id := str(placed.instance.instance_id)
	assert(
		not placed.instance.has(MapEditorInstanceService.MAP_PORTAL_NOTE_FIELD),
		"new portal instances must start without a note"
	)

	var updated := MapEditorInstanceService.update_map_portal_note(
		document,
		instance_id,
		"  " + NOTE + "  "
	)
	assert(bool(updated.get("ok", false)), str(updated.get("errors", [])))
	assert(str(updated.note) == NOTE)
	assert(
		str(
			MapEditorInstanceService._locate(document, instance_id).instance.get(
				MapEditorInstanceService.MAP_PORTAL_NOTE_FIELD,
				""
			)
		) == NOTE
	)

	var absolute_save_path := ProjectSettings.globalize_path(SAVE_PATH)
	var saved := MapEditorSaveService.save_document(document, absolute_save_path)
	assert(bool(saved.get("ok", false)), str(saved.get("errors", [])))
	var loaded := MapEditorLoadService.load_document(absolute_save_path, false)
	assert(bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	assert(
		str(
			MapEditorInstanceService._locate(loaded.document, instance_id).instance.get(
				MapEditorInstanceService.MAP_PORTAL_NOTE_FIELD,
				""
			)
		) == NOTE,
		"portal note must survive editor save/load"
	)

	var duplicate := MapEditorInstanceService.duplicate_instance_snapshot(
		document,
		updated.instance,
		Vector2i(35, 35)
	)
	assert(bool(duplicate.get("ok", false)), str(duplicate.get("errors", [])))
	assert(
		not duplicate.instance.has(MapEditorInstanceService.MAP_PORTAL_NOTE_FIELD),
		"a copied endpoint must not inherit another endpoint's note"
	)

	var non_portal := MapEditorInstanceService.create_instance(
		document,
		NON_PORTAL_ASSET_ID,
		"decoration",
		Vector2i(50, 50),
		"object_base"
	)
	assert(bool(non_portal.get("ok", false)), str(non_portal.get("errors", [])))
	var rejected := MapEditorInstanceService.update_map_portal_note(
		document,
		str(non_portal.instance.instance_id),
		"不得写入"
	)
	assert(not bool(rejected.get("ok", false)))
	assert(rejected.get("errors", []) == ["instance_is_not_map_portal"])
	assert(
		not MapEditorInstanceService._locate(
			document,
			str(non_portal.instance.instance_id)
		).instance.has(MapEditorInstanceService.MAP_PORTAL_NOTE_FIELD)
	)

	var runtime := MapEditorBuildRuntimeService._compile(
		document,
		{"blocked_tiles": {}}
	)
	for runtime_instance: Dictionary in runtime.get("instances", []):
		assert(
			not runtime_instance.has(MapEditorInstanceService.MAP_PORTAL_NOTE_FIELD),
			"editor-only portal notes must not enter runtime snapshots"
		)

	var editor := MapEditorApp.new()
	editor.load_default_workspace_on_ready = false
	editor.persist_last_document_path = false
	add_child(editor)
	await get_tree().process_frame
	editor.current_document = document
	editor.preview.set_document(document)
	editor.preview.selected_selectable_id = instance_id
	editor._on_selectable_selected(instance_id, false)
	assert(editor.map_portal_note_container.visible)
	assert(editor.map_portal_note_edit.text == NOTE)
	editor.map_portal_note_edit.text = "E方向连接封魔殿 W方向入口"
	editor._on_save_selected_map_portal_note_pressed()
	assert(
		str(
			MapEditorInstanceService._locate(document, instance_id).instance.get(
				MapEditorInstanceService.MAP_PORTAL_NOTE_FIELD,
				""
			)
		) == "E方向连接封魔殿 W方向入口"
	)
	editor._on_selectable_selected(str(non_portal.instance.instance_id), false)
	assert(not editor.map_portal_note_container.visible)
	editor.queue_free()

	var cleared := MapEditorInstanceService.update_map_portal_note(
		document,
		instance_id,
		"   "
	)
	assert(bool(cleared.get("ok", false)))
	assert(
		not MapEditorInstanceService._locate(document, instance_id).instance.has(
			MapEditorInstanceService.MAP_PORTAL_NOTE_FIELD
		),
		"blank notes must remove the optional field"
	)

	_cleanup_save_files()
	print(
		"MSE_MAP_PORTAL_INSTANCE_NOTE_PASS "
		+ "field=map_portal_note persistence=editor_only copy=cleared"
	)
	get_tree().quit(0)


func _cleanup_save_files() -> void:
	var absolute := ProjectSettings.globalize_path(SAVE_PATH)
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := absolute + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
