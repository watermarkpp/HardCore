extends Node
const Codec := preload("res://scripts/gameplay/source/source_path_object_codec.gd")
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
const Nav := preload("res://scripts/map_editor/polygon/poly_nav_graph.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failed := 0
func check(ok: bool,label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1; print("PATH_OBJECT_HANDOFF_FAILED ",label)
func _ready() -> void:
	var index := Index.new()
	check(index.setup(Vector2i(12,12),[[[5.0,5.0],[7.0,5.0],[7.0,7.0],[5.0,7.0]]]),"original real polygon index setup")
	var nav := Nav.new()
	var radius := 0.35
	var setup: Dictionary = nav.setup({"radius_key":Nav.key_for_radius(radius),"radius_gu":radius,"vertices_ground_gu":[[0.0,0.0],[12.0,0.0],[12.0,12.0],[0.0,12.0]],"faces":[[0,1,2],[0,2,3]]},Vector2i(12,12))
	check(setup.get("ok") == true,"original real navigation graph setup")
	var graphs := {nav.radius_key:nav}; graphs.make_read_only()
	var snapshot := {"poly_index":index,"poly_graphs":graphs}
	var collision := {"parts":index.parts}; collision.make_read_only()
	var runtime := {"collision":collision}
	var loaded: Array[Dictionary] = [{"runtime":runtime,"collision":collision,"snapshot":snapshot},{"runtime":runtime,"collision":collision,"snapshot":snapshot}]
	var roots := {"polygon_state":{"_loaded":loaded,"_pending":loaded[0]},"terrain_state":{"cached_index":index,"cached_nav":nav,"buckets":index.buckets},"equal_but_distinct":{},"other_empty":{}}
	var distinct_indices: Array = []
	for ordinal: int in range(64):
		var another := Index.new()
		check(another.setup(Vector2i(12+ordinal,12+ordinal),[]),"real distinct cached index setup %d" % ordinal)
		distinct_indices.append(another)
	roots["distinct_indices"] = distinct_indices
	var encoded: Dictionary = Codec.capture(roots)
	check(encoded.get("ok") == true,"nonempty joint-root polygon cache transfers as plain values: "+str(encoded.get("errors",[])))
	if encoded.get("ok") == true:
		var native: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
		check(native.validate(encoded.value,false).get("success") == true,"wire contains no live Object")
		check(encoded.value.objects.size() == 66,"one descriptor per original object identity")
		var envelope := {"path":encoded.value,"state":encoded.value.roots}
		var draft: Dictionary = envelope.duplicate(false); draft["additional_world"] = {}
		var owned: Dictionary = native.capture(draft,true,false)
		check(owned.get("success") == true and is_same(owned.value.path.roots,owned.value.state),"final production Native capture preserves descriptor and state root alias")
		var thread := Thread.new()
		check(thread.start(_restore_on_owner.bind(owned.value.path)) == OK,"actual background owner starts")
		var result: Dictionary = thread.wait_to_finish()
		check(result.get("owner") != OS.get_main_thread_id() and result.get("ok") == true,"actual receiving thread restores object graph: "+str(result.get("errors",[])))
		if result.get("ok") == true:
			for key: String in result.checks: check(result.checks[key],key)
		var bad: Dictionary = native.capture(encoded.value,false,false).value
		bad.objects[0].source_sha256 = "0".repeat(64)
		check(Codec.restore(bad).get("ok") == false,"changed object source rejected")
		bad = native.capture(encoded.value,false,false).value; bad.object_slots[0].path = ["roots","missing"]
		check(Codec.restore(bad).get("ok") == false,"invalid object slot rejected")
	check(Codec.capture({"bad":self}).get("ok") == false,"arbitrary Node remains rejected")
	check(Codec.capture({"bad":RefCounted.new()}).get("ok") == false,"unknown RefCounted remains rejected")
	var cycle: Dictionary = {}; cycle["self"] = cycle
	check(Codec.capture(cycle).get("ok") == false,"container cycle remains rejected"); cycle.erase("self")
	check(is_same(roots.polygon_state._loaded[0].snapshot.poly_index,index) and not loaded.is_read_only() and collision.is_read_only(),"Main cache and original mutability unchanged")
	var written: bool = _proof.write_receipt("path_object_handoff_20261017",_proof.records.size(),_failed)
	print("PATH_OBJECT_HANDOFF_20261017_","PASS" if written and _failed == 0 else "FAIL")
	get_tree().quit(0 if written and _failed == 0 else 1)
func _restore_on_owner(wire: Dictionary) -> Dictionary:
	var actual: Dictionary = Codec.restore(wire)
	if actual.get("ok") != true: return actual
	var roots: Dictionary = actual.value
	var loaded: Array = roots.polygon_state._loaded
	var index: RefCounted = loaded[0].snapshot.poly_index
	var nav: RefCounted = loaded[0].snapshot.poly_graphs.values()[0]
	var distinct_ok := true
	var ids: Dictionary = {}
	for ordinal: int in range(roots.distinct_indices.size()):
		var another: RefCounted = roots.distinct_indices[ordinal]
		distinct_ok = distinct_ok and another.design_size == Vector2i(12+ordinal,12+ordinal) and another.ready and not ids.has(another.get_instance_id())
		ids[another.get_instance_id()] = true
	var checks := {
		"distinct descriptor envelopes retain their own fields without allocator reuse":distinct_ok and ids.size() == 64,
		"same object aliases across cache and terrain roots":is_same(index,roots.terrain_state.cached_index) and is_same(nav,roots.terrain_state.cached_nav),
		"same container aliases across object fields and cache roots":is_same(index.buckets,roots.terrain_state.buckets) and is_same(index.parts,loaded[0].collision.parts),
		"cache release and pending identities preserved":is_same(loaded[0],roots.polygon_state._pending) and is_same(loaded[0].snapshot,loaded[1].snapshot),
		"mutable cache and sealed geometry modes preserved":not loaded.is_read_only() and loaded[0].collision.is_read_only() and index.buckets.is_read_only() and loaded[0].snapshot.poly_graphs.is_read_only(),
		"typed numeric polygon arrays preserved":index.parts.get_typed_builtin() == TYPE_PACKED_VECTOR2_ARRAY and index.boxes.get_typed_builtin() == TYPE_RECT2,
		"equal distinct containers stay distinct":not is_same(roots.equal_but_distinct,roots.other_empty),
		"real original collision queries work on restored owner":index.point_blocked(Vector2(6,6)) and not index.point_blocked(Vector2(2,2)) and index.capsule_blocked(Vector2(2,6),Vector2(10,6),0.35),
		"real original navigation queries work on restored owner":nav.ready and nav.locate(Vector2(2,2)) >= 0 and nav.attach(Vector2(2,2),index,0.35).has("face")}
	return {"ok":true,"owner":OS.get_thread_caller_id(),"checks":checks}
