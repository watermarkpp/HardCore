extends Node
## Unconfigured constructor/owner ABI only. Null unused dependencies do not
## stand in for an admitted Core, Registry, actor or running physics session.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const BasePorts := preload("res://scripts/gameplay/actors/actor_runtime_ports.gd")
const EnemyPorts := preload("res://scripts/gameplay/world/world_enemy_runtime_ports.gd")
var _proof := Proof.new()
var _failed := 0
func check(ok: bool, label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1
func _ready() -> void: _run.call_deferred()
func _construct() -> Dictionary:
	var base := BasePorts.new(null,null,null,null,null,Callable(),0.0,false,false)
	var enemy := EnemyPorts.new(null,null,null,null,null,Callable(),0.0,false,false)
	return {"base":base,"enemy":enemy,"owner":OS.get_thread_caller_id(),"base_stored":base.get("_owner"),"enemy_stored":enemy.get("_owner")}
func _run() -> void:
	var worker := Thread.new()
	check(worker.start(Callable(self,"_construct")) == OK,"real separate constructor thread starts")
	while worker.is_alive(): await get_tree().process_frame
	var created: Dictionary = worker.wait_to_finish()
	check(created.owner != OS.get_main_thread_id() and created.owner == created.base_stored and created.owner == created.enemy_stored,"production constructors preserve actual non-Main owner")
	for key: String in ["base","enemy"]:
		var port: RefCounted = created[key]
		var exists: bool = port.has_method("owner_thread_id")
		check(exists,"actual " + key + " port exposes owner identity required by Enemy.configure_ports")
		if exists: check(port.owner_thread_id() == created.owner and port.owner_thread_id() != OS.get_thread_caller_id(),"owner identity reports construction owner, never impersonates the current Main caller: " + key)
	var enemy: RefCounted = created.enemy
	var bindings: Dictionary = enemy.bindings(null)
	for role: String in ["lifetime","metadata","phase_scheduler","presentation","feature_damage","navigation"]:
		check(is_same(bindings[role],enemy),"original shared port identity remains singular for " + role)
	var written: bool = _proof.write_receipt("actor_port_owner_identity_20261017",_proof.records.size(),_failed)
	print("ACTOR_PORT_OWNER_IDENTITY_", "PASS" if written and _failed == 0 else "FAIL")
	get_tree().quit(0 if written and _failed == 0 else 1)
