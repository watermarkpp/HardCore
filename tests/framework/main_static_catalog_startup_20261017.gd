extends Node
## Actual production preparation, freeze and Native-proven abort restoration.
## The unchanged fresh-seal comparison has its own earlier16check receipt;
## this scene concentrates on the newly connected static catalogue owner.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Producer := preload("res://scripts/gameplay/source/main_startup_application_producer.gd")
const Published := preload("res://scripts/gameplay/content/published_static_catalogs.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
var _proof := Proof.new()
var _failed := 0
func check(ok: bool,label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1; print("MAIN_STATIC_CATALOG_FAILED ",label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	check(OS.get_user_data_dir().replace("\\","/").contains("/.godot/runtime_appdata/"),"actual production preparation uses isolated original data")
	var facade: Node = get_tree().root.get_node("PlayerState")
	var original_model: RefCounted = facade.get("_model")
	var original_profile: String = facade.get("active_profile_id")
	var producer := Producer.new()
	var prepared: Dictionary = await producer.prepare_main(facade,Producer.original_phone_host_policy())
	check(prepared.get("success") == true,"actual production Main graph and static catalogue prepare: "+str(prepared))
	if prepared.get("success") == true:
		var host: Object = producer.actual_host()
		var lease: Dictionary = producer.get("_catalog_lease")
		check(not Published._main_fields.is_empty() and Published._lease == lease and Gate.is_active(lease),"same actual original static publisher owns the unique reader lease")
		var originals: Array = Published._main_fields.duplicate(false)
		var frozen := true
		for catalogue: Array in Published.CATALOGS:
			for field: String in catalogue[1]:
				var value: Variant = catalogue[0].get(field)
				if value is Dictionary or value is Array: frozen = frozen and value.is_read_only()
		check(frozen,"every actual shared rules/catalogue container is frozen before Source admission")
		check(host.status().get("started") == false and host.status().get("main_channels_prepared") == true,"Native channels are real and no Source/physics owner has started")
		check(not producer.actual_application().actual_original_sealed_profile_publication().is_empty(),"actual canonical Profile seal is available under the same static lease")
		var retired: Dictionary = producer.retire_actual_unstarted_preparation()
		check(retired.get("success") == true,"actual Native unbinding precedes original static publication release: "+str(retired))
		check(host.status().get("main_channels_aborted") == true and host.status().get("started") == false,"Native proves genuine unstarted owner retirement")
		check(Published._lease.is_empty() and Published._main_fields.is_empty() and Gate.write_allowed(),"actual static publication and its reader gate retire together")
		var restored := originals.size() == Published.CATALOGS.size()
		for index: int in range(originals.size()):
			var catalogue: Array = Published.CATALOGS[index]
			for field: String in catalogue[1]:
				var value: Variant = catalogue[0].get(field)
				var original: Variant = originals[index][field]
				restored = restored and (is_same(value,original) if value is Dictionary or value is Array else value == original)
		check(restored,"all actual pre-publication catalogue objects and values are restored exactly")
	check(facade.get("_model") == original_model and facade.get("active_profile_id") == original_profile and facade.get("_source_domain_gate") == null,"original Profile authority and selected save remain unchanged")
	var written: bool = _proof.write_receipt("main_static_catalog_startup_20261017",_proof.records.size(),_failed)
	print("MAIN_STATIC_CATALOG_STARTUP_20261017_","PASS" if written and _failed == 0 else "FAIL")
	get_tree().quit(0 if written and _failed == 0 else 1)
