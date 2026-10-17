extends Node
## Real Main preparation and Native bindings only; World/Source admission is
## deliberately separate and cannot be inferred from this receipt.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Producer := preload("res://scripts/gameplay/source/main_startup_application_producer.gd")
const Published := preload("res://scripts/gameplay/content/published_static_catalogs.gd")
class ObservedProducer extends Producer:
	func _set_stage(value: String) -> void:
		super._set_stage(value)
		print("ACTUAL_MAIN_STARTUP_PHASE ",value)
var _proof := Proof.new()
var _failed := 0
var _producer: RefCounted
func check(ok: bool, label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1; print("MAIN_STARTUP_PRODUCER_FAILED ",label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var original_model: RefCounted = PlayerState.get("_model")
	var original_profile: String = PlayerState.active_profile_id
	var policy: Dictionary = {"bridge_generation":115171,"primitive_request_capacity":65536,"primitive_result_capacity":65536,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":32,"live_primitive_capacity":2}
	_producer = ObservedProducer.new()
	var actual: Dictionary = await _producer.prepare_main(PlayerState,policy)
	check(actual.get("success") == true,"the real producer composes all Main Native owners: "+str(actual))
	if actual.get("success") != true and _producer.get("_canonical").get("success") == true: _record_actual_seal_failure()
	var host: Object = _producer.actual_host()
	var application: RefCounted = _producer.actual_application()
	if actual.get("success") == true:
		check(Published._lease == _producer.get("_catalog_lease") and not Published._main_fields.is_empty(),"actual original static catalogue publisher owns the same production reader lease")
		var frozen := true
		for catalogue: Array in Published.CATALOGS:
			for field: String in catalogue[1]:
				var value: Variant = catalogue[0].get(field)
				if value is Dictionary or value is Array: frozen = frozen and value.is_read_only()
		check(frozen,"all actual shared rule/catalogue containers are frozen before Source can read them")
		check(application != null and get_tree().root.get_meta(application.ENTRY_META,null) == application,"same actual Main application is installed as the sole entry")
		check(host.status().get("main_channels_prepared") == true and host.status().get("started") != true,"real Native channels are prepared without claiming Source physics")
		var composition: RefCounted = application.get("_main_composition")
		check(composition.get("_stage") == "CHANNELS_BOUND","actual Native Feature/claim/origin/Caster/closing/channel bindings complete")
		check(composition.get("_pump") == application.get("_transport").get("_main_pump"),"actual Driver and Transport retain the same resource pump")
		var sealed: Dictionary = application.actual_original_sealed_profile_publication()
		check(not sealed.is_empty() and sealed.is_read_only() and is_same(sealed,application.actual_original_sealed_profile_publication()),"same actual immutable Main Profile seal is retained and reused")
		var canonical: Dictionary = _producer.get("_canonical")
		var services: Dictionary = application.get("_services")
		var original: Dictionary = preload("res://scripts/gameplay/profile/profile_publication.gd").seal(canonical,services.catalog_lease,services.feature_publication)
		check(var_to_bytes(original) == var_to_bytes(sealed),"retained seal exactly matches a fresh original production seal")
		check(not canonical.publication.features.has("resource_publication") and not canonical.publication.has("catalog_lease"),"sealing never mutates canonical preparation inputs")
	if actual.get("success") == true:
		var retired: Dictionary = _producer.retire_actual_unstarted_preparation()
		check(retired.get("success") == true,"actual Native unbinding precedes unstarted graph retirement: "+str(retired))
		check(application.actual_original_sealed_profile_publication().is_empty(),"actual unstarted retirement releases the retained seal")
		check(host.status().get("main_channels_aborted") == true and host.status().get("started") == false,"actual Host proves there was no Source/physics claim during retirement")
		check(PlayerState.get("_source_domain_gate") == null and not get_tree().root.has_meta(application.ENTRY_META),"only the exact unstarted gate and entry are removed")
		for name: String in ["HardCoreSourceMainLifecycle","HardCoreMainSessionTransport","HardCoreOriginalCloseProcessFrame"]:
			check(get_tree().root.get_node_or_null(NodePath(name)) == null,"actual unstarted Main listener retired:"+name)
	check(PlayerState.get("_model") == original_model and PlayerState.active_profile_id == original_profile,"the original loaded Profile authority is unchanged during Main preparation")
	var written: bool = _proof.write_receipt("main_startup_application_producer_20261016",_proof.records.size(),_failed)
	print("MAIN_STARTUP_APPLICATION_PRODUCER_20261016_","PASS" if written and _failed == 0 else "FAIL")
	get_tree().quit(0 if written and _failed == 0 else 1)

func _record_actual_seal_failure() -> void:
	var canonical: Dictionary = _producer.get("_canonical")
	var token: Dictionary = _producer.get("_catalog_lease")
	var base: Dictionary = canonical.publication.duplicate(true)
	var configuration: Dictionary = ContentLayers.feature_configuration()
	var publication: Dictionary = {}
	for row: Dictionary in _producer.get("_feature").get("_publications").values():
		if row.lease.get_ref() == configuration.get("resource_lease"): publication = row.publication
	var plan: Dictionary = preload("res://scripts/features/contracts/feature_resource_lease.gd").requirements(base.features.catalog,base.features.enabled_modules)
	base["catalog_lease"] = token; base.features["resource_publication"] = publication
	var graph: Dictionary = preload("res://scripts/gameplay/content/content_value_graph.gd").capture(base)
	print("ACTUAL_MAIN_CANONICAL_SEAL_FACTS ",{"token_active":preload("res://scripts/gameplay/content/catalog_publication_gate.gd").is_active(token),"plan":plan,"publication":publication,"graph_success":graph.get("success"),"graph_errors":graph.get("errors",[])})
