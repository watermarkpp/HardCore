extends Node
## Persistence verification sidecar (scratch): SECOND process boots the
## production chain, selects the probe seed character, and dumps the persisted
## state so the probe session's final state can be proven durable.

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := {"schema": "hardcore.ui_latency_verify.v1"}
	if not GameData.ensure_loaded():
		out["error"] = "GAME_DATA_FAILED"
		_finish(out)
		return
	var seed_name := "延迟探针"
	var pid := ""
	var idx_path: String = ProjectSettings.globalize_path(PlayerState.profile_index_path)
	if FileAccess.file_exists(idx_path):
		var parsed: Variant = JSON.parse_string(FileAccess.open(idx_path, FileAccess.READ).get_as_text())
		if parsed is Dictionary:
			var stack: Array = [parsed]
			while not stack.is_empty() and pid == "":
				var cur: Variant = stack.pop_back()
				if cur is Dictionary:
					if str(cur.get("name", "")) == seed_name and str(cur.get("profile_id", cur.get("id", ""))) != "":
						pid = str(cur.get("profile_id", cur.get("id")))
					for v in cur.values():
						if v is Dictionary or v is Array:
							stack.append(v)
				elif cur is Array:
					stack.append_array(cur)
	out["profile_id"] = pid
	if pid == "" or not PlayerState.select_character(pid):
		out["error"] = "SELECT_FAILED"
		_finish(out)
		return
	var save_path: String = ProjectSettings.globalize_path("user://player_save_v03.json")
	out["gold"] = PlayerState.gold
	out["weapon"] = str(PlayerState.equipment.get("武器", {}).get("name", ""))
	out["jinchuang_count"] = PlayerState.item_count("超级金创药")
	out["dagger_in_inventory"] = PlayerState.item_count("匕首")
	out["save_exists"] = FileAccess.file_exists(save_path)
	if bool(out.save_exists):
		out["save_sha256_12"] = FileAccess.get_sha256(save_path).substr(0, 12)
	out["test_mode"] = PlayerState.test_mode
	_finish(out)

func _finish(out: Dictionary) -> void:
	var path := "res://outputs/test_logs/ui_latency_verify.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	print("UI_LAT_VERIFY_WRITTEN gold=%s weapon=%s" % [str(out.get("gold", "?")), str(out.get("weapon", "?"))])
	get_tree().quit(0)
