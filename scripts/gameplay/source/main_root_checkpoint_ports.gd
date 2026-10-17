extends RefCounted
const Router := preload("res://scripts/gameplay/source/main_root_checkpoint_router.gd")
const Admission := preload("res://scripts/gameplay/source/main_source_admission.gd")
const TreePublication := preload("res://scripts/gameplay/source/main_source_tree_publication.gd")
const Driver := preload("res://scripts/gameplay/source/main_source_lifecycle_driver.gd")
static func create_main_ports(host: Object, tree: SceneTree, facade: Node, content: Node, legacy_resources: Node, primitive_facade: Node, primitives: RefCounted, transport: RefCounted, fatal: RefCounted, pin_inspector: RefCounted, receiver_manifest: Dictionary, prefix_consumer: RefCounted, caster_executor: RefCounted, actual_launch_loading: RefCounted) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or host==null or tree==null: return _fail("actual_Main_once_required")
	if tree.root.get_node_or_null("HardCoreSourceMainLifecycle")!=null: return _fail("actual_single_source_lifecycle_required")
	if not host.has_method("bind_original_source_admission_producer"): return _fail("MISSING:actual_Native_Main_admission")
	var router: RefCounted = Router.new()
	var configured: Dictionary = router.configure_main(tree,facade,transport,fatal,receiver_manifest)
	if configured.get("success")!=true: return configured
	if not router.bind_actual_original_launch_loading(actual_launch_loading): return _fail("actual_same_launch_Loading_producer_required")
	var deferred: RefCounted = ClassDB.instantiate("HardCoreMainSourceDeferred")
	if deferred==null: return _fail("MISSING:actual_Native_Main_CallQueue_provider")
	if not deferred.configure_original_checkpoint_producer(router,router.get_script().resource_path,router.get_script().get_source_code().sha256_text()): return _fail("actual_Main_checkpoint_script_provenance_rejected")
	var admission: RefCounted = Admission.new()
	configured=admission.configure_main(facade,content,legacy_resources,primitive_facade,primitives,deferred,router,pin_inspector)
	if configured.get("success")!=true: return configured
	if not primitives.bind_original_main_source_admission(admission): return _fail("actual_same_Main_admission_endpoint_binding_rejected")
	if not host.bind_original_source_admission_producer(admission,admission.get_script().get_source_code().sha256_text()): return _fail("actual_Main_admission_script_provenance_rejected")
	if not admission.bind_actual_original_native_host(host): return _fail("actual_same_Main_admission_Host_binding_rejected")
	var publication: RefCounted = TreePublication.new()
	if not publication.configure_main(tree,router): return _fail("actual_source_tree_publisher_rejected")
	var driver: Node = Driver.new()
	configured=driver.configure_main(router,admission,transport,host,prefix_consumer,caster_executor)
	if configured.get("success")!=true:
		driver.free()
		return configured
	driver.name="HardCoreSourceMainLifecycle"
	tree.root.add_child(driver)
	return {"success":true,"router":router,"admission":admission,"source_deferred":deferred,"source_tree_publication":publication,"lifecycle":driver}
static func _fail(code: String) -> Dictionary: return {"success":false,"errors":[code]}

static func create_original_boot_provider_assembly(host: Object, facade: Node, actual_producers: Dictionary) -> Dictionary:
	return preload("res://scripts/gameplay/source/main_original_boot_provider_factory.gd").create_main(host,facade,actual_producers)
