extends RefCounted
## S token for a genuine Main reference. Never a Resource or Node.
var descriptor: Dictionary
var _endpoint: WeakRef
func _init(value: Dictionary, endpoint: RefCounted) -> void:
	descriptor = value.duplicate(true)
	descriptor.native_types.make_read_only()
	descriptor.make_read_only()
	_endpoint = weakref(endpoint)
func _get(property: StringName) -> Variant:
	return _endpoint.get_ref().object_property(self,str(property))
func is_valid() -> bool:
	return _endpoint.get_ref().object_is_valid(self)
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _endpoint != null:
		var endpoint: RefCounted = _endpoint.get_ref()
		if endpoint != null: endpoint.release_reference(descriptor)
func get_length() -> Variant:
	return _endpoint.get_ref().object_call(self,"get_length",[])
func get_position() -> Variant:
	return _endpoint.get_ref().object_call(self,"get_position",[])
func get_buffer(length: Variant) -> Variant:
	return _endpoint.get_ref().object_call(self,"get_buffer",[length])
func close() -> Variant:
	return _endpoint.get_ref().object_call(self,"close",[])
func valid_for(consumer: Variant,generation: Variant) -> Variant:
	return _endpoint.get_ref().object_call(self,"valid_for",[consumer,generation])
func is_verified() -> Variant:
	return _endpoint.get_ref().object_call(self,"is_verified",[])
func step() -> Variant:
	return _endpoint.get_ref().object_call(self,"step",[])
func verify_next_source() -> Variant:
	return _endpoint.get_ref().object_call(self,"verify_next_source",[])
func paths() -> Variant:
	return _endpoint.get_ref().object_call(self,"paths",[])
func signature() -> Variant:
	return _endpoint.get_ref().object_call(self,"signature",[])
func target_path() -> Variant:
	return _endpoint.get_ref().object_call(self,"target_path",[])
func revalidate_admission_sources() -> Variant:
	return _endpoint.get_ref().object_call(self,"revalidate_admission_sources",[])
func valid_asset(path: Variant,resource: Variant) -> Variant:
	return _endpoint.get_ref().object_call(self,"valid_asset",[path,resource])
func valid_target(resource: Variant) -> Variant:
	return _endpoint.get_ref().object_call(self,"valid_target",[resource])
func valid_for_code(plan: Variant) -> Variant:
	return _endpoint.get_ref().object_call(self,"valid_for_code",[plan])
func attach_loaded_code_resource(plan: Variant,resource: Variant,consumer: Variant,service: Variant) -> Variant:
	return _endpoint.get_ref().object_call(self,"attach_loaded_code_resource",[plan,resource,consumer,service])
func loaded_code_retention_current(resource: Variant,consumer: Variant,service: Variant) -> Variant:
	return _endpoint.get_ref().object_call(self,"loaded_code_retention_current",[resource,consumer,service])
func transfer_loaded_code_retention(resource: Variant,previous: Variant,next_consumer: Variant,service: Variant) -> Variant:
	return _endpoint.get_ref().object_call(self,"transfer_loaded_code_retention",[resource,previous,next_consumer,service])
func cancel() -> Variant:
	return _endpoint.get_ref().object_call(self,"cancel",[])
func get_node_or_null(path: Variant) -> Variant:
	return _endpoint.get_ref().object_call(self,"get_node_or_null",[path])
func get_parent() -> Variant:
	return _endpoint.get_ref().object_call(self,"get_parent",[])
func get_node_count() -> Variant:
	return _endpoint.get_ref().object_call(self,"get_node_count",[])
func get_node_property_count(index: Variant) -> Variant:
	return _endpoint.get_ref().object_call(self,"get_node_property_count",[index])
func get_node_property_name(index: Variant,property_index: Variant) -> Variant:
	return _endpoint.get_ref().object_call(self,"get_node_property_name",[index,property_index])
func get_node_property_value(index: Variant,property_index: Variant) -> Variant:
	return _endpoint.get_ref().object_call(self,"get_node_property_value",[index,property_index])
func change_scene_to_packed(scene: Variant) -> Variant:
	return _endpoint.get_ref().object_call(self,"change_scene_to_packed",[scene])
func is_inside_tree() -> Variant:
	return _endpoint.get_ref().object_call(self,"is_inside_tree",[])
func original_main_is_queued_for_deletion() -> bool:
	return bool(_endpoint.get_ref().object_call(self,"is_queued_for_deletion",[]))
func is_internal_code_publication_boundary_current(sequence: Variant) -> Variant:
	return _endpoint.get_ref().object_call(self,"is_internal_code_publication_boundary_current",[sequence])
func code_preparation_export_contract() -> Variant:
	return _endpoint.get_ref().object_call(self,"code_preparation_export_contract",[])
func code_preparation_export_seal_sha256() -> Variant:
	return _endpoint.get_ref().object_call(self,"code_preparation_export_seal_sha256",[])
func is_code_preparation_generation_current(generation: Variant) -> Variant:
	return _endpoint.get_ref().object_call(self,"is_code_preparation_generation_current",[generation])
func is_code_preparation_loading_phase_current(generation: Variant) -> Variant:
	return _endpoint.get_ref().object_call(self,"is_code_preparation_loading_phase_current",[generation])
func code_preparation_cover_receipt() -> Variant:
	return _endpoint.get_ref().object_call(self,"code_preparation_cover_receipt",[])
func _feature_resources() -> Variant:
	return _endpoint.get_ref().object_call(self,"_feature_resources",[])
func get_object() -> Variant:
	return _endpoint.get_ref().object_call(self,"get_object",[])
func get_method() -> Variant:
	return _endpoint.get_ref().object_call(self,"get_method",[])
