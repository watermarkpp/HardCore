extends Node
## Production admission ABI and fail-closed preflight. Positive lease migration
## is checked separately with real leases; this scene never claims S adoption.
const Primitives := preload("res://scripts/features/runtime/feature_resource_main_primitives.gd")
const Admission := preload("res://scripts/gameplay/source/main_source_admission.gd")
const Facade := preload("res://scripts/features/runtime/feature_resource_main_facade.gd")
const Legacy := preload("res://scripts/features/runtime/feature_resource_preparation.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failed := 0
func check(value: bool, label: String) -> void:
	_proof.record(value,label)
	if not value: _failed += 1
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var native_ops := {"unselected":1,"prepare":3,"commit":2,"abort":1,"loading":1,"pins":1,"release_pins":1}
	for name: String in native_ops:
		check(Primitives.OPCODE_ARITY.get("source_admission_"+name,-1) == native_ops[name],"actual Main primitive matches registered Native source-admission opcode: "+name)
	var primitives: RefCounted = Primitives.new()
	check(primitives.has_method("bind_original_main_source_admission"),"same actual Main executor has source-admission provider binding")
	check(primitives.has_method("handoff_original_physical_leases"),"same actual Main executor has physical owner commit endpoint")
	var content: Node = get_tree().root.get_node("ContentLayers")
	var previous: Node = content.get("_feature_resource_service")
	check(content.has_method("install_original_feature_resource_facade"),"ContentLayers has a checked physical facade switch")
	if _failed > 0:
		primitives = null
		_finish()
		return
	check(not primitives.bind_original_main_source_admission(RefCounted.new()),"arbitrary provider cannot bind original admission")
	var admission: RefCounted = Admission.new()
	check(not primitives.bind_original_main_source_admission(admission),"unconfigured actual Script cannot claim a live admission")
	var legacy: Node = Legacy.new()
	var facade: Node = Facade.new()
	add_child(legacy); add_child(facade)
	var refused: Dictionary = primitives.handoff_original_physical_leases(legacy,[],{})
	check(refused.get("success") != true,"no operation/prepared proof means no physical handoff even for empty lease set")
	check(not content.install_original_feature_resource_facade(facade),"real in-tree Node cannot switch ContentLayers without actual commit proof")
	check(content.get("_feature_resource_service") == previous,"rejected installer leaves original service identity unchanged")
	check(not primitives.is_executing_original_primitive(),"preflight does not invent an executing Native request")
	facade.free(); legacy.free(); admission = null; primitives = null
	_finish()
func _finish() -> void:
	var written: bool = _proof.write_receipt("main_source_physical_admission_20261015",_proof.records.size(),_failed)
	print("MAIN_SOURCE_PHYSICAL_ADMISSION_20261015_", "PASS" if written and _failed == 0 else "FAIL", " checks=",_proof.records.size()," failures=",_failed)
	get_tree().quit(0 if written and _failed == 0 else 1)
