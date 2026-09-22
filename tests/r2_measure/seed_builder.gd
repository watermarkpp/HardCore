extends Node

## Builds the R2 QA seed with the authoritative PlayerState interfaces only.
## test_mode stays false so the files are the real save format. Writes
## character_profiles.json, shared_warehouse.json and characters/<id>.json
## under the isolated user:// r2_seed_out/ staging folder for the executor to
## hash and copy into each measure tree.

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var root := ProjectSettings.globalize_path("user://")
	var out := root + "r2_seed_out"
	DirAccess.make_dir_recursive_absolute(out + "/characters")
	PlayerState.test_mode = false
	var profile_id: String = ""
	var index_bytes: PackedByteArray = FileAccess.get_file_as_bytes(PlayerState.profile_index_path)
	var parsed: Variant = JSON.parse_string(index_bytes.get_string_from_utf8())
	var entries: Array = []
	if parsed is Array:
		entries = parsed
	elif parsed is Dictionary and (parsed as Dictionary).has("profiles"):
		entries = (parsed as Dictionary)["profiles"]
	for entry: Variant in entries:
		if entry is Dictionary and str((entry as Dictionary).get("name", "")) == "R2延迟测量":
			profile_id = str((entry as Dictionary).get("id", ""))
			break
	if profile_id.is_empty():
		push_error("SEED_REUSE_PROFILE_FAILED")
		get_tree().quit(1)
		return
	PlayerState.active_profile_id = profile_id
	PlayerState.reset_progress(false)
	PlayerState.level = 60
	PlayerState.gold = 500000
	var add0 := PlayerState.add_item("木剑", 1)
	var add1 := PlayerState.add_item("铁剑", 1)
	if add0.is_empty() or add1.is_empty():
		push_error("SEED_ADD_ITEM_FAILED")
		get_tree().quit(1)
		return
	var ok: bool = PlayerState.save_game(true)
	if not ok:
		push_error("SEED_SAVE_FAILED")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	for rel in ["character_profiles.json", "shared_warehouse.json", "characters/" + profile_id + ".json"]:
		var src: String = root + rel
		if not FileAccess.file_exists(src):
			push_error("SEED_FILE_MISSING:" + rel)
			get_tree().quit(1)
			return
		var dst: String = out + "/" + rel
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(src)
		FileAccess.open(dst, FileAccess.WRITE).store_buffer(bytes)
		print("SEED_COPIED %s %d %s" % [rel, bytes.size(), FileAccess.get_sha256(src)])
	print("SEED_PROFILE_ID " + profile_id)
	get_tree().quit(0)
