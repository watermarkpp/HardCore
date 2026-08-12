class_name UIRuntimeLayoutOverrides
extends RefCounted

const CONTRACT_PATH := "res://assets/data/ui/manual_layout_overrides.json"
const CONTRACT_SHA256 := "A0286CB7F20B152DAA829A1FB36201780159C927E76AB3D5B6C93AE5DC5A322E"
const SCHEMA_VERSION := 3

static var _contract: Dictionary = {}
static var _loaded := false
static var _target_tokens: Dictionary = {}

static func apply_profile(target: Control, profile_id: String) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var tree: SceneTree = target.get_tree()
	if tree == null:
		return
	_load_contract()
	var profile: Dictionary = _contract.get("profiles", {}).get(profile_id, {})
	var entries: Dictionary = profile.get("nodes", {})
	if entries.is_empty():
		return
	var target_id := target.get_instance_id()
	var token := int(_target_tokens.get(target_id, 0)) + 1
	_target_tokens[target_id] = token
	var resolved: Array[Dictionary] = []
	var inventory_map := _legacy_inventory_map(target, entries)
	var quest_map := _legacy_quest_map(target, entries)
	var used: Dictionary = {}
	for raw_path: Variant in entries.keys():
		var path := str(raw_path)
		var entry: Variant = entries[raw_path]
		if not entry is Dictionary or _retired(target, path) or _dynamic_map_path(path):
			continue
		var control := _resolve(target, path, inventory_map, quest_map)
		if control == null or used.has(control.get_instance_id()):
			continue
		if _stale(control, entry as Dictionary) or _dependency_retired(target, entries, control):
			continue
		used[control.get_instance_id()] = true
		resolved.append({"path": path, "control": control, "entry": entry})
	resolved.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _depth(a["control"] as Node, target) < _depth(b["control"] as Node, target)
	)
	# First pass establishes parent geometry.  A second pass is required because
	# anchors and minimum sizes may settle after the parent has changed.
	for pass_index in 2:
		for item in resolved:
			if int(_target_tokens.get(target_id, 0)) != token:
				return
			var raw_control: Variant = item["control"]
			if not is_instance_valid(raw_control):
				continue
			var control := raw_control as Control
			if not is_instance_valid(control):
				continue
			if not _can_write(target, control):
				return
			_apply_geometry(control, item["entry"] as Dictionary, profile, target, str(item["path"]))
			if int(_target_tokens.get(target_id, 0)) != token:
				return
		await tree.process_frame
		if not _can_write(target, target):
			return
		if int(_target_tokens.get(target_id, 0)) != token:
			return
		# Font and visibility are deliberately applied without saved text content.
	for item in resolved:
		if int(_target_tokens.get(target_id, 0)) != token:
			return
		var raw_control: Variant = item["control"]
		if not _can_write(target, raw_control):
			continue
		var control := raw_control as Control
		if not is_instance_valid(control):
			continue
		var entry := item["entry"] as Dictionary
		if not _can_write(target, control):
			return
		if entry.has("fontSize") and _supports_text(control):
			_set_font_size(control, entry, profile, target)
		if not _can_write(target, control):
			return
		control.visible = bool(entry.get("visible", true)) and not bool(entry.get("deleted", false))
	await tree.process_frame
	if not _can_write(target, target):
		return
	if int(_target_tokens.get(target_id, 0)) != token:
		return
	# Reassert geometry after font/minimum-size changes.
	for item in resolved:
		if int(_target_tokens.get(target_id, 0)) != token:
			return
		var raw_control: Variant = item["control"]
		if not is_instance_valid(raw_control):
			continue
		var control := raw_control as Control
		if _can_write(target, control):
			_apply_geometry(control, item["entry"] as Dictionary, profile, target, str(item["path"]))
	if int(_target_tokens.get(target_id, 0)) == token and _can_write(target, target) and target.has_method("_on_runtime_layout_profile_applied"):
		target.call("_on_runtime_layout_profile_applied", profile_id)


static func _load_contract() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(CONTRACT_PATH):
		push_warning("UI layout contract missing: %s" % CONTRACT_PATH)
		return
	var hash := FileAccess.get_sha256(CONTRACT_PATH).to_upper()
	if hash != CONTRACT_SHA256:
		push_warning("UI layout contract hash mismatch: %s" % hash)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	if parsed is Dictionary and int(parsed.get("schemaVersion", 0)) == SCHEMA_VERSION:
		_contract = parsed


static func _resolve(target: Control, path: String, inventory_map: Dictionary, quest_map: Dictionary) -> Control:
	var direct := target.get_node_or_null(NodePath(path)) as Control
	if direct != null:
		return direct
	if path.begins_with("BagPanel/InventoryScroll/ItemGrid/"):
		return _legacy_child(target, path, inventory_map, "BagPanel/InventoryScroll/ItemGrid/")
	if path.begins_with("QuestListPanel/QuestListScroll/QuestList/"):
		return _legacy_child(target, path, quest_map, "QuestListPanel/QuestListScroll/QuestList/")
	return null


static func _legacy_child(target: Control, path: String, mapping: Dictionary, prefix: String) -> Control:
	var rest := path.trim_prefix(prefix)
	var slash := rest.find("/")
	var legacy := rest if slash < 0 else rest.left(slash)
	var root := mapping.get(legacy) as Control
	if root == null:
		return null
	return root if slash < 0 else root.get_node_or_null(NodePath(rest.substr(slash + 1))) as Control


static func _legacy_inventory_map(target: Control, entries: Dictionary) -> Dictionary:
	var ids: Array[int] = []
	for key: Variant in entries.keys():
		var path := str(key)
		if not path.begins_with("BagPanel/InventoryScroll/ItemGrid/"):
			continue
		var name := path.trim_prefix("BagPanel/InventoryScroll/ItemGrid/").split("/")[0]
		if name.begins_with("@Control@") and name.trim_prefix("@Control@").is_valid_int():
			ids.append(int(name.trim_prefix("@Control@")))
	ids.sort()
	var grid := target.get_node_or_null("BagPanel/InventoryScroll/ItemGrid") as Control
	var result := {}
	if grid == null:
		return result
	for i in range(mini(ids.size(), grid.get_child_count())):
		result["@Control@%d" % ids[i]] = grid.get_child(i)
	return result


static func _legacy_quest_map(target: Control, entries: Dictionary) -> Dictionary:
	var ids: Array[int] = []
	for key: Variant in entries.keys():
		var path := str(key)
		if not path.begins_with("QuestListPanel/QuestListScroll/QuestList/"):
			continue
		var name := path.trim_prefix("QuestListPanel/QuestListScroll/QuestList/").split("/")[0]
		if name.begins_with("@Button@") and name.trim_prefix("@Button@").is_valid_int():
			ids.append(int(name.trim_prefix("@Button@")))
	ids.sort()
	var list := target.get_node_or_null("QuestListPanel/QuestListScroll/QuestList") as Control
	var result := {}
	if list == null:
		return result
	var cards: Array[Control] = []
	for child in list.get_children():
		if child is Button:
			cards.append(child as Control)
	for i in range(mini(ids.size(), cards.size())):
		result["@Button@%d" % ids[i]] = cards[i]
	return result


static func _apply_geometry(control: Control, entry: Dictionary, profile: Dictionary, root: Control, saved_path: String) -> void:
	if saved_path == "." or control == root or not _can_write(root, control):
		return
	var rect: Array = entry.get("logicalRect", [])
	if rect.size() != 4:
		return
	var design: Array = profile.get("logicalDesignSize", [])
	var root_size := root.size
	if root_size.x <= 0.0 or root_size.y <= 0.0:
		root_size = control.get_viewport().get_visible_rect().size
	var sx := root_size.x / float(design[0]) if design.size() == 2 and float(design[0]) > 0 else 1.0
	var sy := root_size.y / float(design[1]) if design.size() == 2 and float(design[1]) > 0 else 1.0
	# logicalRect is local to the saved parent (the editor writes localRect
	# under this name), so applying it directly preserves parent/child geometry.
	if not control is Container:
		control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	if control is Button:
		_prepare_button_for_size(control as Button, Vector2(float(rect[2]) * sx, float(rect[3]) * sy))
	control.position = Vector2(float(rect[0]) * sx, float(rect[1]) * sy)
	control.size = Vector2(float(rect[2]) * sx, float(rect[3]) * sy)
	if control is Button:
		(control as Button).clip_text = true


static func _prepare_button_for_size(button: Button, desired_size: Vector2) -> void:
	var minimum := button.get_combined_minimum_size()
	var relax_x := desired_size.x + 0.01 < minimum.x
	var relax_y := desired_size.y + 0.01 < minimum.y
	if not relax_x and not relax_y:
		return
	button.clip_text = true
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		var source := button.get_theme_stylebox(state)
		if source == null:
			continue
		var adjusted := source.duplicate() as StyleBox
		if relax_x:
			adjusted.content_margin_left = 0.0
			adjusted.content_margin_right = 0.0
		if relax_y:
			adjusted.content_margin_top = 0.0
			adjusted.content_margin_bottom = 0.0
		button.add_theme_stylebox_override(state, adjusted)
	button.update_minimum_size()


static func _can_write(target: Variant, control: Variant) -> bool:
	return target != null and is_instance_valid(target) and target.is_inside_tree() and control != null and is_instance_valid(control) and control is Control and (control as Control).is_inside_tree()


static func _set_font_size(control: Control, entry: Dictionary, profile: Dictionary, target: Control) -> void:
	var design: Array = profile.get("designSize", [])
	var logical: Array = profile.get("logicalDesignSize", [])
	var scale := 1.0
	if design.size() == 2 and logical.size() == 2 and float(design[1]) > 0:
		scale = target.size.y / float(logical[1]) if target.size.y > 0.0 else 1.0
	var logical_size := float(entry.get("logicalFontSize", float(entry.get("fontSize", 14.0)) / maxf(scale, 0.001)))
	var value := maxi(1, roundi(logical_size * scale))
	control.add_theme_font_size_override("font_size", value)


static func _supports_text(control: Control) -> bool:
	return control is Label or control is RichTextLabel or control is Button or control is LineEdit or control is TextEdit


static func _depth(node: Node, root: Node) -> int:
	var n := 0
	var cursor := node
	while cursor != null and cursor != root:
		n += 1
		cursor = cursor.get_parent()
	return n


static func _stale(control: Control, entry: Dictionary) -> bool:
	return int(control.get_meta("calibration_layout_revision", 0)) > int(entry.get("layoutRevision", 0))


static func _retired(target: Control, path: String) -> bool:
	return target.has_meta("calibration_retired_paths") and path in target.get_meta("calibration_retired_paths", [])


static func _dependency_retired(target: Control, entries: Dictionary, control: Control) -> bool:
	if not control.has_meta("calibration_layout_dependencies"):
		return false
	for dependency in control.get_meta("calibration_layout_dependencies", []):
		var item: Dictionary = entries.get(str(dependency), {})
		if bool(item.get("deleted", false)) or not bool(item.get("visible", true)):
			return true
	return false


static func _dynamic_map_path(path: String) -> bool:
	return path.begins_with("MapListPanel/MapListScroll/MapCards/") or path.begins_with("MapPreviewPanel/WorldTreeScroll/WorldTree/")
