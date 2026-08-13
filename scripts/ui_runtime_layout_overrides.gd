class_name UIRuntimeLayoutOverrides
extends RefCounted

const CONTRACT_PATH := "res://assets/data/ui/manual_layout_overrides.json"
const CONTRACT_SHA256 := "4D77B33D45286CB2C60FF10FF9382CF837264C9B00D2453C9D186F299C53B9A4"
const SCHEMA_VERSION := 3
const KNOWN_PROFILE_IDS := {
	"character_hall": true,
	"confirmation_dialog": true,
	"death_revival": true,
	"inventory": true,
	"map": true,
	"quest": true,
	"shop_buy": true,
	"shop_sell": true,
	"skill": true,
	"system_menu": true,
	"warehouse": true,
}
const EXTERNAL_PROFILE_MAX_NODES := 512
const EXTERNAL_PROFILE_MAX_PATH_LENGTH := 256
const EXTERNAL_PROFILE_ALLOWED_ENTRY_KEYS := {
	"deleted": true,
	"fontSize": true,
	"layoutRevision": true,
	"logicalFontSize": true,
	"logicalRect": true,
	"modulate": true,
	"mouseFilter": true,
	"selfModulate": true,
	"text": true,
	"textRevision": true,
	"themeVariation": true,
	"visible": true,
	"zIndex": true,
}

static var _contract: Dictionary = {}
static var _loaded := false
static var _target_tokens: Dictionary = {}


## Captures only the static controls addressed by an incoming patch.  The
## result is another schema-3 profile, so it can be persisted as a compact
## Device Lab checkpoint and applied through the same validated transaction.
static func capture_external_profile(
	target: Control,
	profile_id: String,
	requested_entries: Dictionary
) -> Dictionary:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return {}
	var nodes := {}
	for raw_path: Variant in requested_entries.keys():
		var path := str(raw_path)
		if path == "." or _dynamic_map_path(path) or _retired(target, path):
			continue
		var control := target.get_node_or_null(NodePath(path)) as Control
		if control == null or not _can_write(target, control):
			continue
		var entry := {
			"logicalRect": [control.position.x, control.position.y, control.size.x, control.size.y],
			"visible": control.visible,
			"deleted": false,
			"themeVariation": str(control.theme_type_variation),
			"modulate": [control.modulate.r, control.modulate.g, control.modulate.b, control.modulate.a],
			"selfModulate": [control.self_modulate.r, control.self_modulate.g, control.self_modulate.b, control.self_modulate.a],
			"zIndex": control.z_index,
			"mouseFilter": control.mouse_filter,
		}
		if _supports_text(control) and not bool(control.get_meta("calibration_runtime_text", false)):
			entry["text"] = _control_text(control)
			entry["logicalFontSize"] = control.get_theme_font_size("font_size")
		nodes[path] = entry
	if nodes.is_empty():
		return {}
	return {
		"schemaVersion": SCHEMA_VERSION,
		"profiles": {
			profile_id: {
				"logicalDesignSize": [target.size.x, target.size.y],
				"nodes": nodes,
			},
		},
	}


## Applies a Device Lab profile as one guarded transaction.  This is separate
## from apply_profile(): the formal resource loader keeps its historical async
## contract, while the external bridge must be able to report a failed commit
## and restore every Control it touched.
static func apply_external_profile_transaction(
	target: Control,
	profile_id: String,
	external_contract: Dictionary
) -> Dictionary:
	var failure := {"ok": false, "profile": profile_id, "applied": [], "rolledBack": false, "error": ""}
	if not _can_write(target, target):
		failure["error"] = "target_unavailable"
		return failure
	var validation := validate_external_profile(profile_id, external_contract)
	if not bool(validation.get("ok", false)):
		failure["error"] = str(validation.get("error", "invalid_profile"))
		return failure
	var profile: Dictionary = (external_contract.get("profiles", {}) as Dictionary).get(profile_id, {})
	var entries: Dictionary = profile.get("nodes", {})
	var plan_result := _build_external_plan(target, entries)
	if not bool(plan_result.get("ok", false)):
		failure["error"] = str(plan_result.get("error", "plan_failed"))
		return failure
	var plan: Array = plan_result.get("plan", [])
	var target_id := target.get_instance_id()
	var token := int(_target_tokens.get(target_id, 0)) + 1
	_target_tokens[target_id] = token
	var backups: Array = []
	for item: Dictionary in plan:
		var control: Control = item.get("control") as Control
		if not _can_write(target, control):
			_rollback_external_profile(backups)
			failure["error"] = "node_released_before_commit"
			failure["rolledBack"] = true
			return failure
		backups.append(_backup_external_control(control))
	if not _transaction_valid(target, plan, token):
		_rollback_external_profile(backups)
		failure["error"] = "transaction_invalid_before_commit"
		failure["rolledBack"] = true
		return failure
	var tree: SceneTree = target.get_tree()
	for pass_index in 2:
		for item: Dictionary in plan:
			if not _transaction_valid(target, plan, token):
				_rollback_external_profile(backups)
				failure["error"] = "transaction_invalid_during_geometry"
				failure["rolledBack"] = true
				return failure
			var control: Control = item.get("control") as Control
			_apply_geometry(control, item.get("entry", {}) as Dictionary, profile, target, str(item.get("path", "")))
			if not _transaction_valid(target, plan, token):
				_rollback_external_profile(backups)
				failure["error"] = "transaction_invalid_after_geometry"
				failure["rolledBack"] = true
				return failure
		await tree.process_frame
		if not _transaction_valid(target, plan, token):
			_rollback_external_profile(backups)
			failure["error"] = "transaction_invalid_after_frame"
			failure["rolledBack"] = true
			return failure
	for item: Dictionary in plan:
		if not _transaction_valid(target, plan, token):
			_rollback_external_profile(backups)
			failure["error"] = "transaction_invalid_during_properties"
			failure["rolledBack"] = true
			return failure
		var control: Control = item.get("control") as Control
		var entry: Dictionary = item.get("entry", {}) as Dictionary
		if entry.has("fontSize") and _supports_text(control):
			_set_font_size(control, entry, profile, target)
		_apply_external_properties(control, entry)
		control.visible = bool(entry.get("visible", true)) and not bool(entry.get("deleted", false))
	if not _transaction_valid(target, plan, token):
		_rollback_external_profile(backups)
		failure["error"] = "transaction_invalid_after_properties"
		failure["rolledBack"] = true
		return failure
	await tree.process_frame
	if not _transaction_valid(target, plan, token):
		_rollback_external_profile(backups)
		failure["error"] = "transaction_invalid_after_properties_frame"
		failure["rolledBack"] = true
		return failure
	for item: Dictionary in plan:
		var control: Control = item.get("control") as Control
		if not _transaction_valid(target, plan, token):
			_rollback_external_profile(backups)
			failure["error"] = "transaction_invalid_during_reassert"
			failure["rolledBack"] = true
			return failure
		_apply_geometry(control, item.get("entry", {}) as Dictionary, profile, target, str(item.get("path", "")))
	if not _transaction_valid(target, plan, token):
		_rollback_external_profile(backups)
		failure["error"] = "transaction_invalid_after_reassert"
		failure["rolledBack"] = true
		return failure
	if target.has_method("_on_runtime_layout_profile_applied"):
		target.call("_on_runtime_layout_profile_applied", profile_id)
	if not _transaction_valid(target, plan, token):
		_rollback_external_profile(backups)
		failure["error"] = "transaction_invalid_after_callback"
		failure["rolledBack"] = true
		return failure
	var applied: Array[String] = []
	for item: Dictionary in plan:
		applied.append(str(item.get("path", "")))
	return {"ok": true, "profile": profile_id, "applied": applied, "rolledBack": false, "error": ""}


static func _build_external_plan(target: Control, entries: Dictionary) -> Dictionary:
	var inventory_map := _legacy_inventory_map(target, entries)
	var quest_map := _legacy_quest_map(target, entries)
	var used: Dictionary = {}
	var plan: Array = []
	for raw_path: Variant in entries.keys():
		var path := str(raw_path)
		var raw_entry: Variant = entries[raw_path]
		if not raw_entry is Dictionary or _retired(target, path) or _dynamic_map_path(path):
			continue
		var control := _resolve(target, path, inventory_map, quest_map)
		if control == null or used.has(control.get_instance_id()):
			continue
		var entry := raw_entry as Dictionary
		if _stale(control, entry) or _dependency_retired(target, entries, control):
			continue
		used[control.get_instance_id()] = true
		plan.append({"path": path, "control": control, "entry": entry})
	if plan.is_empty():
		return {"ok": false, "error": "no_applicable_nodes"}
	plan.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _depth(a["control"] as Node, target) < _depth(b["control"] as Node, target)
	)
	return {"ok": true, "plan": plan}


static func _transaction_valid(target: Control, plan: Array, token: int) -> bool:
	if not _can_write(target, target):
		return false
	if int(_target_tokens.get(target.get_instance_id(), 0)) != token:
		return false
	for item: Dictionary in plan:
		if not _can_write(target, item.get("control") as Control):
			return false
	return true


static func _backup_external_control(control: Control) -> Dictionary:
	var backup := {
		"control": control,
		"position": control.position,
		"size": control.size,
		"anchors": [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom],
		"visible": control.visible,
		"modulate": control.modulate,
		"self_modulate": control.self_modulate,
		"z_index": control.z_index,
		"mouse_filter": control.mouse_filter,
		"theme_variation": control.theme_type_variation,
		"text": _control_text(control),
		"has_font_size": control.has_theme_font_size_override("font_size"),
		"font_size": control.get_theme_font_size("font_size"),
	}
	if control is Button:
		backup["clip_text"] = (control as Button).clip_text
		var styleboxes: Dictionary = {}
		for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
			styleboxes[state] = {
				"has": (control as Button).has_theme_stylebox_override(state),
				"value": (control as Button).get_theme_stylebox(state),
			}
		backup["styleboxes"] = styleboxes
	return backup


static func _rollback_external_profile(backups: Array) -> void:
	for index in range(backups.size() - 1, -1, -1):
		var backup: Dictionary = backups[index]
		var control: Control = backup.get("control") as Control
		if control == null or not is_instance_valid(control):
			continue
		var anchors: Array = backup.get("anchors", [])
		if anchors.size() == 4:
			control.anchor_left = float(anchors[0])
			control.anchor_top = float(anchors[1])
			control.anchor_right = float(anchors[2])
			control.anchor_bottom = float(anchors[3])
		control.position = backup.get("position", Vector2.ZERO)
		control.size = backup.get("size", Vector2.ZERO)
		control.visible = bool(backup.get("visible", true))
		control.modulate = backup.get("modulate", Color.WHITE)
		control.self_modulate = backup.get("self_modulate", Color.WHITE)
		control.z_index = int(backup.get("z_index", 0))
		control.mouse_filter = int(backup.get("mouse_filter", Control.MOUSE_FILTER_STOP))
		control.theme_type_variation = str(backup.get("theme_variation", ""))
		if _supports_text(control):
			_set_control_text(control, str(backup.get("text", "")))
		if control.has_theme_font_size_override("font_size"):
			control.remove_theme_font_size_override("font_size")
		if bool(backup.get("has_font_size", false)):
			control.add_theme_font_size_override("font_size", int(backup.get("font_size", 14)))
		if control is Button:
			var button := control as Button
			button.clip_text = bool(backup.get("clip_text", false))
			var styleboxes: Dictionary = backup.get("styleboxes", {})
			for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
				var state_backup: Dictionary = styleboxes.get(state, {})
				if bool(state_backup.get("has", false)):
					button.add_theme_stylebox_override(state, state_backup.get("value"))
				else:
					button.remove_theme_stylebox_override(state)

static func apply_profile(
	target: Control,
	profile_id: String,
	external_contract: Dictionary = {}
) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var tree: SceneTree = target.get_tree()
	if tree == null:
		return
	var source_contract := external_contract
	if source_contract.is_empty():
		_load_contract()
		source_contract = _contract
	else:
		var validation := validate_external_profile(profile_id, source_contract)
		if not bool(validation.get("ok", false)):
			push_warning("Device Lab rejected UI profile: %s" % str(validation.get("error", "invalid_profile")))
			return
	var profile: Dictionary = source_contract.get("profiles", {}).get(profile_id, {})
	var entries: Dictionary = profile.get("nodes", {})
	if entries.is_empty():
		return
	target.set_meta(_ready_meta_key(profile_id), false)
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
	if int(_target_tokens.get(target_id, 0)) == token and _can_write(target, target):
		target.set_meta(_ready_meta_key(profile_id), true)
		if target.has_method("_on_runtime_layout_profile_applied"):
			target.call("_on_runtime_layout_profile_applied", profile_id)


static func profile_is_ready(target: Control, profile_id: String) -> bool:
	return (
		target != null
		and is_instance_valid(target)
		and bool(target.get_meta(_ready_meta_key(profile_id), false))
	)


static func _ready_meta_key(profile_id: String) -> StringName:
	return StringName("runtime_layout_profile_ready_%s" % profile_id)


## Validates an external Device Lab profile without touching any scene node.
## The formal resource contract remains loaded through _load_contract() for all
## existing callers; this gate only accepts a copied, schema-versioned profile.
static func validate_external_profile(profile_id: String, contract: Dictionary) -> Dictionary:
	if not KNOWN_PROFILE_IDS.has(profile_id):
		return {"ok": false, "error": "unknown_profile"}
	if contract.is_empty():
		return {"ok": false, "error": "empty_contract"}
	if int(contract.get("schemaVersion", 0)) != SCHEMA_VERSION:
		return {"ok": false, "error": "schema_version"}
	var profiles: Variant = contract.get("profiles", {})
	if not profiles is Dictionary:
		return {"ok": false, "error": "profiles_not_object"}
	var profile: Variant = (profiles as Dictionary).get(profile_id, {})
	if not profile is Dictionary:
		return {"ok": false, "error": "profile_not_object"}
	var nodes: Variant = (profile as Dictionary).get("nodes", {})
	if not nodes is Dictionary or (nodes as Dictionary).is_empty():
		return {"ok": false, "error": "nodes_not_object"}
	if (nodes as Dictionary).size() > EXTERNAL_PROFILE_MAX_NODES:
		return {"ok": false, "error": "nodes_limit"}
	for raw_path: Variant in (nodes as Dictionary).keys():
		var path := str(raw_path)
		if path.is_empty() or path.length() > EXTERNAL_PROFILE_MAX_PATH_LENGTH:
			return {"ok": false, "error": "path_length"}
		if path != "." and (path.begins_with("/") or path.contains("..") or path.contains("\\")):
			return {"ok": false, "error": "path_not_allowlisted"}
		var raw_entry: Variant = (nodes as Dictionary)[raw_path]
		if not raw_entry is Dictionary:
			return {"ok": false, "error": "entry_not_object"}
		var entry := raw_entry as Dictionary
		for raw_key: Variant in entry.keys():
			if not EXTERNAL_PROFILE_ALLOWED_ENTRY_KEYS.has(str(raw_key)):
				return {"ok": false, "error": "entry_key_not_allowlisted:%s" % str(raw_key)}
		if entry.has("logicalRect"):
			var rect: Variant = entry.get("logicalRect", [])
			if not rect is Array or (rect as Array).size() != 4:
				return {"ok": false, "error": "logical_rect"}
			for value: Variant in rect as Array:
				if not (value is int or value is float) or not is_finite(float(value)):
					return {"ok": false, "error": "logical_rect_number"}
		if entry.has("logicalFontSize") and (not (entry.logicalFontSize is int or entry.logicalFontSize is float) or not is_finite(float(entry.logicalFontSize))):
			return {"ok": false, "error": "logical_font_size"}
		if entry.has("fontSize") and (not (entry.fontSize is int or entry.fontSize is float) or not is_finite(float(entry.fontSize))):
			return {"ok": false, "error": "font_size"}
		if entry.has("visible") and not (entry.visible is bool):
			return {"ok": false, "error": "visible_type"}
		if entry.has("deleted") and not (entry.deleted is bool):
			return {"ok": false, "error": "deleted_type"}
		if entry.has("layoutRevision") and not (entry.layoutRevision is int or entry.layoutRevision is float):
			return {"ok": false, "error": "layout_revision_type"}
		if entry.has("themeVariation") and not (entry.themeVariation is String):
			return {"ok": false, "error": "theme_variation_type"}
		for color_key: String in ["modulate", "selfModulate"]:
			if entry.has(color_key) and not _valid_color_array(entry.get(color_key)):
				return {"ok": false, "error": "%s_type" % color_key}
		if entry.has("zIndex") and not (entry.zIndex is int or entry.zIndex is float):
			return {"ok": false, "error": "z_index_type"}
		if entry.has("mouseFilter") and (not (entry.mouseFilter is int or entry.mouseFilter is float) or int(entry.mouseFilter) not in [0, 1, 2]):
			return {"ok": false, "error": "mouse_filter_type"}
	return {"ok": true, "profile": profile_id, "nodes": (nodes as Dictionary).size()}


static func _valid_color_array(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 4:
		return false
	for component: Variant in value as Array:
		if not (component is int or component is float) or not is_finite(float(component)):
			return false
	return true


static func _apply_external_properties(control: Control, entry: Dictionary) -> void:
	if entry.has("text") and _supports_text(control) and not bool(control.get_meta("calibration_runtime_text", false)):
		_set_control_text(control, str(entry.get("text", "")))
	if entry.has("themeVariation"):
		control.theme_type_variation = str(entry.get("themeVariation", ""))
	if entry.has("modulate"):
		control.modulate = _color_from_array(entry.get("modulate", []))
	if entry.has("selfModulate"):
		control.self_modulate = _color_from_array(entry.get("selfModulate", []))
	if entry.has("zIndex"):
		control.z_index = int(entry.get("zIndex", control.z_index))
	if entry.has("mouseFilter"):
		control.mouse_filter = int(entry.get("mouseFilter", control.mouse_filter))


static func _color_from_array(value: Array) -> Color:
	return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))


static func _control_text(control: Control) -> String:
	if _supports_text(control):
		return str(control.get("text"))
	return ""


static func _set_control_text(control: Control, value: String) -> void:
	if _supports_text(control):
		control.set("text", value)


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
	return (
		# Inventory cells and their descendants are rebuilt from PlayerState on
		# every data refresh.  They are not authored layout layers: applying a
		# saved cell/button rect to a newly-created child can restore a stale
		# position/size (and, after a consume removes a stack, the stale entry can
		# belong to a different item).  The grid/viewport itself remains static and
		# is still eligible for the formal profile above this path.
		path.begins_with("BagPanel/InventoryScroll/ItemGrid/")
		or
		path.begins_with("MapListPanel/MapListScroll/MapCards/")
		or path.begins_with("MapPreviewPanel/WorldTreeScroll/WorldTree/")
		or path.begins_with("GoodsPanel/GoodsScroll/GoodsGrid/")
		or path.begins_with("QuestListPanel/QuestListScroll/QuestList/")
		or path.begins_with("StashSection/StashScroll/StashGrid/")
		or path.begins_with("BagSection/BagScroll/BagGrid/")
	)
