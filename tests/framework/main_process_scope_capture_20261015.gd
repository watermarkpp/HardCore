extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const PATH := "res://scripts/gameplay/source/main_original_process_scope.gd"
var _proof := Proof.new()
var _failed := 0
func check(value: bool, label: String) -> void:
	_proof.record(value,label)
	if not value: _failed += 1
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	check(ResourceLoader.exists(PATH),"actual Main scope/configuration capture implementation exists")
	if not ResourceLoader.exists(PATH): _finish(); return
	var api: Variant=load(PATH)
	var before: RefCounted=PlayerState.get("_model")
	var captured: Dictionary=api.capture_existing(PlayerState)
	check(captured.get("success")==true,"actual existing original PlayerState scope captured on Main")
	if captured.get("success")==true:
		check(captured.node_id==PlayerState.get_instance_id() and captured.scope.parent_scope_id==get_tree().root.get_instance_id(),"actual identity and SceneTree parent are not fabricated")
		check(captured.scope.process_processing_enabled==PlayerState.is_processing() and captured.scope.physics_processing_enabled==PlayerState.is_physics_processing(),"actual enabled callbacks copied separately")
		check(captured.scope.process_priority==PlayerState.process_priority and captured.scope.physics_priority==PlayerState.process_physics_priority,"actual P/H priorities kept separately")
		check(captured.source_path==[PlayerState.get_index(true)],"persistent Source path is actual Main sibling position, not gameplay Root child")
		check(captured.source_sha256==PlayerState.get_script().get_source_code().sha256_text(),"scope is bound to actual current Script bytes")
		check(captured.scope.effective_process_mode in [1,2,3,4],"inheritance resolves to actual ancestor process mode")
		check(captured.process_frame==Engine.get_process_frames() and captured.physics_frame==Engine.get_physics_frames(),"capture records actual Engine domains")
	var detached:=Node2D.new()
	check(api.capture_existing(detached).get("success")!=true,"detached template cannot claim a live callback scope")
	detached.free()
	var parent:=Node2D.new();var child:=Node2D.new()
	parent.process_mode=Node.PROCESS_MODE_ALWAYS
	add_child(parent);parent.add_child(child)
	child.set_process(true);child.set_physics_process(false)
	child.process_priority=7;child.process_physics_priority=9
	var actual: Dictionary=api.capture_existing(child)
	check(actual.get("success")==true,"real nested node scope captured")
	if actual.get("success")==true:
		check(actual.scope.source_entry.is_empty(),"scriptless Node processing flags do not fabricate a Script _process callback")
		check(actual.scope.effective_process_mode==Node.PROCESS_MODE_ALWAYS and actual.scope.process_mode==Node.PROCESS_MODE_INHERIT,"actual ancestor mode retained independently of own INHERIT")
		check(actual.source_path==[get_index(true),parent.get_index(true),child.get_index(true)],"absolute sibling path includes all genuine ancestors")
		check(actual.scope.process_priority==7 and actual.scope.physics_priority==9,"nondefault actual priorities survive capture")
		check(actual.scope.process_processing_enabled and not actual.scope.physics_processing_enabled,"capture does not turn process into physics")
	parent.queue_free()
	check(api.capture_existing(parent).get("success")!=true,"queued-for-deletion node cannot issue a fresh startup scope")
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(parent) and not is_instance_valid(child),"real observed nodes retire without capture retaining them")
	check(PlayerState.get("_model")==before,"configuration capture does not replace Profile owner")
	_finish()
func _finish() -> void:
	var written: bool=_proof.write_receipt("main_process_scope_capture_20261015",_proof.records.size(),_failed)
	print("MAIN_PROCESS_SCOPE_CAPTURE_20261015_", "PASS" if written and _failed==0 else "FAIL", " checks=",_proof.records.size()," failures=",_failed)
	get_tree().quit(0 if written and _failed==0 else 1)
