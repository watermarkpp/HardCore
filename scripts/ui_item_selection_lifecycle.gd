class_name UIItemSelectionLifecycle
extends Node

## R3 close means a fresh presentation session on the next open.
## Does NOT undo equip, withdraw, consume, buy/sell, or release transaction locks.
var panel: Control
var epoch := 0
var _was_visible := false
var _clearing := false
var _links: Array = []

static func attach(owner: Control) -> UIItemSelectionLifecycle:
	var old := owner.get_node_or_null("R3SelectionLifecycle") as UIItemSelectionLifecycle
	if old != null:
		return old
	var guard := UIItemSelectionLifecycle.new()
	guard.name = "R3SelectionLifecycle"
	guard.panel = owner
	owner.add_child(guard)
	guard.set_process(false)
	guard.set_physics_process(false)
	guard._bind()
	guard._was_visible = owner.is_visible_in_tree()
	return guard

func _enter_tree() -> void:
	_bind.call_deferred()

func _bind() -> void:
	if not is_inside_tree() or not is_instance_valid(panel):
		return
	var cursor: Node = panel
	while cursor != null:
		if cursor.has_signal("visibility_changed"):
			var cb := Callable(self, "sync_visibility")
			if not cursor.is_connected("visibility_changed", cb):
				cursor.connect("visibility_changed", cb)
				_links.append([weakref(cursor), &"visibility_changed", cb])
		cursor = cursor.get_parent()
	if not panel.tree_exiting.is_connected(_on_leaving):
		panel.tree_exiting.connect(_on_leaving)
	sync_visibility()

func _exit_tree() -> void:
	for entry: Array in _links:
		var object: Object = (entry[0] as WeakRef).get_ref()
		if is_instance_valid(object) and object.is_connected(entry[1], entry[2]):
			object.disconnect(entry[1], entry[2])
	_links.clear()

func sync_visibility() -> void:
	if _clearing or not is_instance_valid(panel):
		return
	var now := panel.is_visible_in_tree()
	if now == _was_visible:
		return
	_was_visible = now
	epoch += 1
	_clear_presentation()

func _on_leaving() -> void:
	epoch += 1
	_was_visible = false
	_clear_presentation()

func _clear_presentation() -> void:
	if _clearing or not is_instance_valid(panel):
		return
	_clearing = true
	# Native gesture guards are cancelled only for THIS item's panel. No global
	# touch reset, no game attack-token change, no clearing another pointer.
	for target: Node in panel.find_children("HCActivationOnce", "", true, false):
		if target.has_method("cancel"):
			target.call("cancel")
	if panel.has_method("_ui_dismiss_selection"):
		panel.call("_ui_dismiss_selection")
	# A leaving parent may still exist after some of its controls left the tree.
	# Do not skip the semantic cleanup above; guard only viewport/focus operations.
	if panel.is_inside_tree():
		var viewport := panel.get_viewport()
		if viewport != null:
			var focus := viewport.gui_get_focus_owner()
			if is_instance_valid(focus) and focus.is_inside_tree() and focus.has_focus() and (focus == panel or panel.is_ancestor_of(focus)):
				focus.release_focus()
	# The semantic owner clears selection and authoritative pressed metadata;
	# never indiscriminately untoggle trade tabs or equipped-item data.
	_clearing = false

func allows_presentation(token: int) -> bool:
	return is_instance_valid(panel) and panel.is_visible_in_tree() and token == epoch
