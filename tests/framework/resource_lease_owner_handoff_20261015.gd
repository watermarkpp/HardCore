extends Node
## Real registered Texture and FeatureResourceLease ownership. This verifies
## physical reference routing only, not Native Source admission or fullworld.
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const Registry := preload("res://scripts/features/compilation/feature_resource_registry.gd")
const Legacy := preload("res://scripts/features/runtime/feature_resource_preparation.gd")
const Facade := preload("res://scripts/features/runtime/feature_resource_main_facade.gd")
const Primitives := preload("res://scripts/features/runtime/feature_resource_main_primitives.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failed := 0
var _returned_roots: Array[Dictionary] = []
func check(value: bool, label: String) -> void:
	_proof.record(value,label)
	if not value: _failed += 1
func _ready() -> void: _run.call_deferred()
func _retain_physical_return(method: StringName, arguments: Array) -> bool:
	# A real in-memory transport sink retaining exact roots for this component.
	# No claim of S/FIFO acceptance is made by this receiver.
	if method != &"retire_resources" or arguments.size()!=1 or not arguments[0] is Dictionary: return false
	_returned_roots.append(arguments[0])
	return true
func _run() -> void:
	var declared: Dictionary = Registry.declarations()
	check(declared.get("success") == true,"actual production resource declaration registry loaded")
	var path := ""
	if declared.get("success") == true:
		for key: String in declared.records:
			if declared.records[key].type == "Texture2D": path = key; break
	check(not path.is_empty(),"component selects a genuinely declared Texture, not an invented path")
	if path.is_empty(): _finish(); return
	var texture: Resource = load(path)
	check(Registry.valid_resource(path,texture),"actual loaded Texture satisfies the original declaration")
	var legacy: Node = Legacy.new()
	var next_owner: Node = Facade.new()
	add_child(legacy); add_child(next_owner)
	var primitives: RefCounted = Primitives.new()
	check(next_owner.configure_main(primitives,Callable(self,"_retain_physical_return")),"real non-scheduling Main facade configured with retaining component transport")
	var catalog := {"revision":"resource_owner_handoff_component","modules":{"hc.test.physical_owner":{"requires":[],"resource_dependencies":[path]}}}
	var plan: Dictionary = Lease.requirements(catalog,["hc.test.physical_owner"])
	var first: RefCounted = Lease.issue(plan,{path:texture},legacy,{"requested":0,"cache_hits":1})
	check(first!=null,"actual original lease issued for declared resource")
	if first==null:
		legacy.free(); next_owner.free(); _finish(); return
	check(first.has_method("capture_original_physical_owner_leases"),"canonical lease exposes complete weak physical-owner enumeration")
	if not first.has_method("capture_original_physical_owner_leases"):
		first=null;legacy.free();next_owner.free();_finish();return
	var second: RefCounted = first.retain_subset(catalog,["hc.test.physical_owner"])
	check(second!=null,"original subset produces a second independently owned real lease")
	var api: Variant = Lease
	var held: Array = api.capture_original_physical_owner_leases(legacy)
	check(held.size()==2 and held.has(first) and held.has(second),"owner capture includes both original and subset, without manually supplied omissions")
	check(not api.rebind_original_physical_owner(legacy,next_owner,[first]),"partial list cannot abandon the other original lease")
	check(not api.rebind_original_physical_owner(legacy,next_owner,[first,first]),"duplicate list cannot replace complete responsibility")
	check(first._owner.get_ref()==legacy and second._owner.get_ref()==legacy,"rejected handoffs mutate neither owner")
	check(api.rebind_original_physical_owner(legacy,next_owner,held),"one Main transaction rebinds the complete existing physical lease set")
	check(first.resource_at(path)==texture and second.resource_at(path)==texture,"no reload or replacement resource introduced")
	check(first.valid_for(catalog,["hc.test.physical_owner"]) and second.valid_for(catalog,["hc.test.physical_owner"]),"original signature and subset validity unchanged")
	check(api.capture_original_physical_owner_leases(legacy).is_empty(),"old owner has no hidden physical lease after handoff")
	check(api.capture_original_physical_owner_leases(next_owner).size()==2,"new physical endpoint owns both exact existing leases")
	check(not api.rebind_original_physical_owner(legacy,next_owner,held),"old owner cannot replay the transfer")
	held.clear(); first=null;second=null
	check(_returned_roots.size()==2,"each original PREDELETE returns its roots once to the new physical endpoint")
	check(legacy.get("_retirements").is_empty(),"retired legacy scheduler receives no new cleanup work")
	check(api.capture_original_physical_owner_leases(next_owner).is_empty(),"weak enumeration itself does not pin dead leases")
	for roots: Dictionary in _returned_roots: check(roots.get(path)==texture,"physical return preserves the actual Texture object")
	_returned_roots.clear();texture=null
	legacy.free();next_owner.free();primitives=null
	_finish()
func _finish() -> void:
	var written: bool = _proof.write_receipt("resource_lease_owner_handoff_20261015",_proof.records.size(),_failed)
	print("RESOURCE_LEASE_OWNER_HANDOFF_20261015_", "PASS" if written and _failed==0 else "FAIL", " checks=",_proof.records.size()," failures=",_failed)
	get_tree().quit(0 if written and _failed==0 else 1)
