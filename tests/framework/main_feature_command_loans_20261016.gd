extends Node
## Actual Main vault custody only; this is not a Source/world completion test.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Feature := preload("res://scripts/features/runtime/feature_resource_main_primitives.gd")
const Facade := preload("res://scripts/features/runtime/feature_resource_main_facade.gd")
var proof := Proof.new()
var failures := 0
func check(ok: bool, label: String) -> void:
	proof.record(ok,label)
	if not ok: failures += 1; print("MAIN_FEATURE_COMMAND_LOANS_FAILED ",label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var host: Object = ClassDB.instantiate("HardCoreSimulationHost")
	var main: RefCounted = Feature.new()
	var facade: Node = Facade.new()
	add_child(facade)
	check(main.configure_original_source_owned_main(facade,ClassDB.instantiate("HardCoreResourceObservation"),Callable(host,"validate_original_primitive_ticket"),115169),"actual Native observer and original Main vault configured")
	var cache_miss: Variant = ResourceLoader.get_cached_ref("res://tests/framework/__actual_uncached_resource__.tres")
	check(cache_miss == null and typeof(cache_miss) == TYPE_OBJECT,"actual Native cache miss preserves its typed-null Object distinction")
	check(typeof(main.export_boot_value(cache_miss)) == TYPE_NIL,"actual typed-null resource encodes to plain NIL before Native validation")
	check(typeof(main.export_boot_value({"miss":cache_miss}).miss) == TYPE_NIL,"nested actual cache miss also normalizes without a physical token")
	var null_loan: Dictionary = main._actual_owned_reference_value({"miss":cache_miss},[],0)
	check(null_loan.get("success") == true and typeof(null_loan.value.miss) == TYPE_NIL,"nullable original command arguments use the same plain NIL representation")
	var resource: Resource = Resource.new()
	var scene: Node = get_tree().current_scene
	check(scene != null and scene.is_inside_tree(),"command scene is the actual SceneTree current scene")
	var stable: Dictionary = main.encode_original_source_value(resource)
	main.capture_retirement({"actual_same_resource":resource})
	var retirement: Dictionary = main.get("_retirements").back().actual_same_resource
	check(retirement != stable and retirement.object_id == stable.object_id,"retirement owns a fresh reference to the same actual physical Resource")
	main.get("_retirements").clear() # This unit has published no Native ticket or side fact.
	check(main._release_encoded_reference(stable) and main.decode_original_source_value(retirement) == resource,"an older reference release preserves the new actual retirement owner")
	var later: Dictionary = main.encode_original_source_value(resource)
	check(later != retirement and later.object_id == retirement.object_id,"a later cached Resource result receives an independent release obligation")
	check(main._release_encoded_reference(retirement),"the independent retirement reference releases exactly once")
	stable = later
	var callback: Callable = Callable(self,"_identity")
	var first: Dictionary = main.capture_original_feature_command_loans(1,[resource,resource,callback,callback,scene],scene)
	check(first.get("success") == true,"actual Objects and callback captured without crossing threads")
	if first.get("success") != true: facade.free(); _finish(); return
	check(first.arguments[0] == first.arguments[1] and first.arguments[2] == first.arguments[3] and first.arguments[4] == first.scene,"one command reuses each physical Object or callback loan")
	check(first.arguments[0] != stable and main.decode_original_source_value(first.arguments[0]) == resource,"fresh command token resolves the actual existing Resource")
	check(not main.retire_actual_feature_command_loan_association(1),"unimported command cannot retire custody")
	check(not main.acknowledge_actual_feature_command_import(1,[],first.scene),"different argument receipt cannot acknowledge original import")
	check(main.acknowledge_actual_feature_command_import(1,first.arguments,first.scene),"matching actual import acknowledges the same captured packet")
	check(main.retire_actual_feature_command_loan_association(1),"consumed command association retires after import")
	check(main.get("_vault").has(first.arguments[0].token_id),"retiring command association preserves Source-owned physical token")
	var second: Dictionary = main.capture_original_feature_command_loans(2,[resource],scene)
	check(second.get("success") == true and second.arguments[0] != first.arguments[0],"later command receives an independent token for the same physical Resource")
	check(main._release_encoded_reference(first.arguments[0]),"original reference retirement consumes only the first fresh token")
	check(main.decode_original_source_value(stable) == resource and main.decode_original_source_value(second.arguments[0]) == resource,"late first release preserves stable publication and later command token")
	var before: int = main.get("_vault").size()
	check(main.capture_original_feature_command_loans(3,[resource,actual_signal()],scene).get("success") != true,"unsupported Signal rejects the original graph")
	check(main.get("_vault").size() == before and main.get("_last_command_loan_id") == 2,"rejected graph rolls back only unpublished fresh tokens and preserves sequence")
	var third: Dictionary = main.capture_original_feature_command_loans(3,[Callable()],scene)
	check(third.get("success") == true and main.decode_original_source_value(third.arguments[0]) == Callable(),"invalid callback remains an actual value for the original callback validity check")
	check(main.capture_original_feature_command_loans(5,[],scene).get("success") != true,"a skipped command identity cannot create custody")
	for row: Dictionary in [first,second,third]:
		var seen: Dictionary = {}
		var descriptors: Array = row.arguments.duplicate()
		descriptors.append(row.scene)
		for value: Variant in descriptors:
			if not value is Dictionary or seen.has(value.token_id): continue
			seen[value.token_id] = true
			if main.get("_vault").has(value.token_id): check(main._release_encoded_reference(value),"actual loan releases through original vault retirement")
	for row: Dictionary in [second,third]:
		check(main.acknowledge_actual_feature_command_import(row.loan_id,row.arguments,row.scene) and main.retire_actual_feature_command_loan_association(row.loan_id),"remaining actual command association closes once")
	check(main._release_encoded_reference(stable) and main.get("_vault").is_empty() and main.get("_command_reference_loans").is_empty(),"all exact physical tokens and command associations drain")
	facade.free()
	_finish()
signal original_signal
func actual_signal() -> Signal: return original_signal
func _identity(value: Variant) -> Variant: return value
func _finish() -> void:
	var written: bool = proof.write_receipt("main_feature_command_loans_20261016",proof.records.size(),failures)
	print("MAIN_FEATURE_COMMAND_LOANS_20261016_","PASS" if written and failures == 0 else "FAIL")
	get_tree().quit(0 if written and failures == 0 else 1)
