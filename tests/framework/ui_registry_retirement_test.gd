extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Guard := preload("res://scripts/ui_selection_dismiss_guard.gd")
const Scroll := preload("res://scripts/touch_scroll_support.gd")
const Layout := preload("res://scripts/ui_runtime_layout_overrides.gd")
const HUDScript := preload("res://scripts/hud.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

class Scope extends Panel:
	func _ui_selection_token() -> Array: return [0]
	func _ui_dismiss_selection() -> void: pass

func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var survivor := Scope.new(); survivor.size = Vector2(640,480); add_child(survivor)
	var survivor_button := Button.new(); survivor_button.position = Vector2(20,20); survivor_button.size = Vector2(100,50); survivor.add_child(survivor_button)
	var survivor_scroll := ScrollContainer.new(); survivor.add_child(survivor_scroll)
	var survivor_modal := Window.new(); survivor_modal.visible = false; survivor.add_child(survivor_modal)
	Guard.attach(survivor)
	var support: Node = Scroll.attach_tree(survivor)
	for frame in 3: await get_tree().process_frame
	var guard: Node = get_tree().root.get_node(Guard.NAME)
	for cycle in 3:
		var scope := Scope.new(); add_child(scope)
		Guard.attach(scope); Scroll.attach_tree(scope)
		for count in 50: scope.add_child(Button.new())
		for count in 5: scope.add_child(ScrollContainer.new())
		var modal := Window.new(); modal.visible = false; scope.add_child(modal)
		for frame in 2: await get_tree().process_frame
		check(guard._functional.size() >= 50 and support._registered_controls.size() >= 6,"real dynamic controls register in cycle "+str(cycle))
		scope.queue_free()
		for frame in 4: await get_tree().process_frame
		check(_dead(guard._functional) == 0 and _dead(guard._modals) == 0 and _dead(guard._scopes) == 0,"dismiss registry retires destroyed nodes without any synthetic tap: "+str(cycle))
		check(_dead(support._registered_controls) == 0,"scroll registry retires destroyed nodes without drag: "+str(cycle))
		check(_contains(guard._functional,survivor_button) and _contains(guard._scopes,survivor) and _contains(support._registered_controls,survivor_scroll),"live control/scoping identities remain registered: "+str(cycle))
	# A removal may be a reparent rather than destruction. Cleanup must not
	# retire a live weak target or make its existing metadata block re-entry.
	remove_child(survivor)
	for frame in 3: await get_tree().process_frame
	check(_contains(support._registered_controls,survivor_scroll) and _contains(guard._scopes,survivor),"temporarily detached live controls retain registration")
	add_child(survivor)
	for frame in 3: await get_tree().process_frame
	check(_contains(support._registered_controls,survivor_scroll) and _contains(guard._functional,survivor_button),"re-entered controls keep their actual observer membership")
	for cycle in 50:
		remove_child(survivor)
		for frame in 2: await get_tree().process_frame
		check(_identity_count(guard._functional,survivor_button) == 1 and _identity_count(guard._modals,survivor_modal) == 1,"detached live button/window keep exactly one identity: "+str(cycle))
		add_child(survivor)
		for frame in 2: await get_tree().process_frame
		check(_identity_count(guard._functional,survivor_button) == 1 and _identity_count(guard._modals,survivor_modal) == 1,"reattached button/window registration is idempotent: "+str(cycle))
		check(_identity_count(guard._scopes,survivor) == 1 and _identity_count(support._registered_controls,survivor_scroll) == 1,"scope and scroll ownership stays singular: "+str(cycle))
		check(guard._protected_at(survivor,Vector2(30,30)) and not guard._blocked_by_modal(),"live button protection and hidden-window behavior survive reattachment: "+str(cycle))
	var copied_button := survivor_button.duplicate() as Button
	var copied_scroll := survivor_scroll.duplicate() as ScrollContainer
	survivor.add_child(copied_button); survivor.add_child(copied_scroll)
	for frame in 3: await get_tree().process_frame
	check(_identity_count(guard._functional,copied_button) == 1 and _identity_count(support._registered_controls,copied_scroll) == 1,"copied metadata cannot transfer the original control's registration identity")
	copied_button.queue_free(); copied_scroll.queue_free()
	for frame in 4: await get_tree().process_frame
	check(_dead(guard._functional) == 0 and _dead(support._registered_controls) == 0,"copied controls retire independently while originals remain alive")
	survivor.queue_free()
	for frame in 4: await get_tree().process_frame
	check(guard._functional.is_empty() and guard._modals.is_empty() and guard._scopes.is_empty() and support._registered_controls.is_empty(),"all owned registration containers drain after final destruction")
	await _detached_destruction(guard,support,false)
	await _detached_destruction(guard,support,true)
	await _unclaimed_copy_retention(guard,support)
	await _unclaimed_copy_destroy_first(guard,support)
	await _layout_lifetimes()
	if not proof.write_receipt("ui_registry_retirement_test",checks,failures.size()): failures.append("receipt")
	print("UI_REGISTRY_RETIREMENT_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)

func _unclaimed_copy_retention(guard: Node,support: Node) -> void:
	# Run each owner separately: destroying a ScrollContainer also destroys
	# internal Range controls, whose guard cleanup would mask a Button leak.
	for scrolling in [false,true]:
		var original: Control = ScrollContainer.new() if scrolling else Button.new()
		add_child(original)
		if scrolling: Scroll.attach_tree(original)
		for frame in 3: await get_tree().process_frame
		var refs: Array = support._registered_controls if scrolling else guard._functional
		check(_identity_count(refs,original) == 1,"original registers before its unclaimed copy exists: "+str(scrolling))
		var copied := original.duplicate() as Control
		check(not copied.is_inside_tree(),"copy stays outside the tree without any registration claim: "+str(scrolling))
		var original_ref: WeakRef = weakref(original)
		original.queue_free()
		for frame in 4: await get_tree().process_frame
		check(original_ref.get_ref() == null and is_instance_valid(copied),"original is destroyed while its unclaimed copy survives: "+str(scrolling))
		check(_dead(refs) == 0,"unclaimed copied metadata cannot delay original identity retirement: "+str(scrolling))
		# No other registered target in this service is destroyed before the
		# assertion. A later claim must also accept the surviving copied node.
		add_child(copied)
		if scrolling: Scroll.attach_tree(copied)
		for frame in 3: await get_tree().process_frame
		check(_identity_count(refs,copied) == 1,"orphaned copied metadata does not block new registration: "+str(scrolling))
		copied.queue_free()
		for frame in 4: await get_tree().process_frame
		check(_dead(refs) == 0,"copy retirement finishes without another input event: "+str(scrolling))

func _detached_destruction(guard: Node,support: Node,delayed: bool) -> void:
	var holder := Control.new(); add_child(holder)
	var scope := Scope.new(); holder.add_child(scope)
	var button := Button.new(); scope.add_child(button)
	var scroll := ScrollContainer.new(); scope.add_child(scroll)
	var modal := Window.new(); modal.visible = false; scope.add_child(modal)
	Guard.attach(scope); Scroll.attach_tree(scope)
	for frame in 3: await get_tree().process_frame
	var owned: WeakRef = weakref(scope)
	if delayed:
		holder.remove_child(scope)
		for frame in 4: await get_tree().process_frame
		check(_identity_count(guard._scopes,scope) == 1 and _identity_count(support._registered_controls,scroll) == 1,"delayed destruction preserves still-live detached ownership")
		scope.free()
	else:
		# Invoke the actual HUD clear method, including its remove_child then
		# queue_free ordering; do not synthesize a later tree-removal event.
		var hud := HUDScript.new()
		hud._item_quick_slot_menu_list = holder
		hud.item_quick_slot_candidate_buttons.append(button)
		hud._clear_item_quick_slot_picker()
		check(hud.item_quick_slot_candidate_buttons.is_empty() and holder.get_child_count() == 0,"real HUD clear removes candidates before queued destruction")
		hud.free()
	for frame in 4: await get_tree().process_frame
	check(owned.get_ref() == null,"detached subtree actually destroyed: "+str(delayed))
	check(_dead(guard._functional) == 0 and _dead(guard._modals) == 0 and _dead(guard._scopes) == 0,"dismiss dead identities retire without later input/removal: "+str(delayed))
	check(_dead(support._registered_controls) == 0,"scroll dead identities retire without later input/removal: "+str(delayed))
	holder.queue_free()
	for frame in 3: await get_tree().process_frame

func _layout_lifetimes() -> void:
	var observer := Layout.new()
	var original_registry: Variant = observer.get("_target_tokens")
	var original_size: int = original_registry.size() if original_registry is Dictionary else 0
	var contract := {"schemaVersion":Layout.SCHEMA_VERSION,"profiles":{"inventory":{"logicalDesignSize":[100.0,100.0],
		"nodes":{"BagPanel":{"logicalRect":[20.0,20.0,30.0,30.0],"visible":true}}}}}
	for cycle in 3:
		var owners: Array[Control] = []
		for index in 10:
			var owner := Control.new(); owner.size = Vector2(100,100); add_child(owner)
			var bag := Control.new(); bag.name = "BagPanel"; owner.add_child(bag)
			Layout.apply_profile(owner,"inventory",contract)
			owners.append(owner)
		for frame in 4: await get_tree().process_frame
		var applied := true
		for owner: Control in owners:
			applied = applied and Layout.profile_is_ready(owner,"inventory")
			owner.queue_free()
		check(applied,"real layout applications complete before owner deletion: "+str(cycle))
		owners.clear()
		for frame in 4: await get_tree().process_frame
		var registry: Variant = observer.get("_target_tokens")
		check(not registry is Dictionary or registry.size() <= original_size,"destroyed layout targets leave no process-lifetime token entries: "+str(cycle))

func _dead(refs: Array) -> int:
	var count := 0
	for reference: WeakRef in refs:
		if reference.get_ref() == null: count += 1
	return count

func _contains(refs: Array,target: Node) -> bool:
	for reference: WeakRef in refs:
		if reference.get_ref() == target: return true
	return false

func _identity_count(refs: Array,target: Node) -> int:
	var count := 0
	for reference: WeakRef in refs:
		if reference.get_ref() == target: count += 1
	return count


func _unclaimed_copy_destroy_first(guard: Node,support: Node) -> void:
	# Opposite ordering with the copy still unclaimed: its destruction cannot
	# retire the original identity or disable its later destruction notice.
	for scrolling in [false,true]:
		var original: Control = ScrollContainer.new() if scrolling else Button.new()
		add_child(original)
		if scrolling: Scroll.attach_tree(original)
		for frame in 3: await get_tree().process_frame
		var refs: Array = support._registered_controls if scrolling else guard._functional
		check(_identity_count(refs,original) == 1,"original identity exists before unclaimed-copy-first ordering: "+str(scrolling))
		var copied := original.duplicate() as Control
		check(not copied.is_inside_tree(),"first-destroyed copy has never entered the tree or claimed a registration: "+str(scrolling))
		var copied_ref: WeakRef = weakref(copied)
		copied.free()
		for frame in 4: await get_tree().process_frame
		check(copied_ref.get_ref() == null and is_instance_valid(original),"unclaimed copy is destroyed while original survives: "+str(scrolling))
		check(_identity_count(refs,original) == 1 and _dead(refs) == 0,"copy destruction retains the live original's only registration: "+str(scrolling))
		original.queue_free()
		for frame in 4: await get_tree().process_frame
		check(_dead(refs) == 0,"original subsequently retires without input or another registered target destruction: "+str(scrolling))
