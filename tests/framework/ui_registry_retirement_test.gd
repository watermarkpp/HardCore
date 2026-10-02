extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Guard := preload("res://scripts/ui_selection_dismiss_guard.gd")
const Scroll := preload("res://scripts/touch_scroll_support.gd")
const Layout := preload("res://scripts/ui_runtime_layout_overrides.gd")
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
	var survivor := Scope.new(); add_child(survivor)
	var survivor_button := Button.new(); survivor.add_child(survivor_button)
	var survivor_scroll := ScrollContainer.new(); survivor.add_child(survivor_scroll)
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
	survivor.queue_free()
	for frame in 4: await get_tree().process_frame
	check(guard._functional.is_empty() and guard._modals.is_empty() and guard._scopes.is_empty() and support._registered_controls.is_empty(),"all owned registration containers drain after final destruction")
	await _layout_lifetimes()
	if not proof.write_receipt("ui_registry_retirement_test",checks,failures.size()): failures.append("receipt")
	print("UI_REGISTRY_RETIREMENT_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)

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
