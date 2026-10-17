extends Node
## Real imported texture, original physical Lease and actual FeatureMain vault.
## No Source command, admission or complete application is asserted here.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Feature := preload("res://scripts/features/runtime/feature_resource_main_primitives.gd")
const Facade := preload("res://scripts/features/runtime/feature_resource_main_facade.gd")
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
var proof := Proof.new()
var failures := 0
func check(ok: bool,label: String) -> void:
	proof.record(ok,label)
	if not ok: failures += 1; print("ACTUAL_LEASE_PUBLICATION_FAILED ",label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var host: Object = ClassDB.instantiate("HardCoreSimulationHost")
	var main: RefCounted = Feature.new()
	var facade: Node = Facade.new()
	add_child(facade)
	check(main.configure_original_source_owned_main(facade,ClassDB.instantiate("HardCoreResourceObservation"),Callable(host,"validate_original_primitive_ticket"),115166),"Source-owned vault uses its genuine registrar without an invented nonissued claim callback")
	var declared: Dictionary = preload("res://scripts/features/compilation/feature_resource_registry.gd").record_by_id("hc.resource.item.healing.inventory")
	var path: String = str(declared.get("path",""))
	var catalog := {"revision":"isolated.actual.publication.20261016","modules":{"fixture.actual.texture":{"requires":[],"resource_dependencies":[path]}}}
	var plan: Dictionary = Lease.requirements(catalog,["fixture.actual.texture"])
	var texture: Texture2D = load(path)
	var physical_owner: Node = ContentLayers._feature_resources()
	check(texture != null and physical_owner != null and physical_owner.is_inside_tree(),"actual original physical owner and exact imported Texture exist")
	if texture == null or physical_owner == null: _finish(); return
	var lease: RefCounted = Lease.issue(plan,{path:texture},physical_owner,{"scope":"actual_publication_test"})
	check(lease != null and Lease.capture_original_physical_owner_leases(physical_owner).has(lease),"original Lease.issue records the actual physical owner")
	if lease == null: facade.free(); _finish(); return
	var published: Dictionary = main.publish_actual_resource_lease(lease,plan)
	check(not published.is_empty() and published.get("paths") == plan.paths and published.get("signature") == plan.signature,"actual publication reflects exactly the real lease resources")
	if published.is_empty(): lease = null; facade.free(); _finish(); return
	check(main.get("_publications").get(published.get("publication_id"),{}).get("lease").get_ref() == lease,"same Feature vault retains the original weak physical lease provenance")
	check(main.publish_actual_resource_lease(lease,plan) == published and main.get("_publications").size() == 1,"repeated publication reuses its identity instead of creating another owner")
	var bad: Dictionary = plan.duplicate(true)
	bad.signature = "foreign"
	check(main.publish_actual_resource_lease(lease,bad).is_empty(),"mismatched signature cannot publish an otherwise real texture")
	check(main.publish_actual_resource_lease(null,plan).is_empty(),"nonempty plan cannot promote a missing lease")
	var another: RefCounted = Lease.issue(plan,{path:texture},physical_owner,{})
	var second: Dictionary = main.publish_actual_resource_lease(another,plan)
	check(not second.is_empty() and second.publication_id != published.publication_id,"a distinct real lease gets its own publication even for identical physical texture")
	lease = null; another = null
	await get_tree().process_frame
	check(main.get("_publications")[published.publication_id].lease.get_ref() == null,"publication provenance adds no independent strong lease lifetime")
	facade.free()
	_finish()
func _finish() -> void:
	var written: bool = proof.write_receipt("feature_actual_lease_publication_20261016",proof.records.size(),failures)
	print("FEATURE_ACTUAL_LEASE_PUBLICATION_20261016_","PASS" if written and failures == 0 else "FAIL")
	get_tree().quit(0 if written and failures == 0 else 1)
