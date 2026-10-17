extends RefCounted
const Observe:=preload("res://scripts/gameplay/source/main_boot_source_observations.gd")
var _caster: RefCounted
var _physical: RefCounted
func owner_thread_id() -> int:return OS.get_main_thread_id()
func configure_main(actual_caster: RefCounted,actual_physical_closure: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _caster!=null or actual_caster==null or not actual_caster.has_method("inspect_actual_original_loading_pins") or not actual_caster.has_method("release_original_loading_pin_closure"):return false
	if actual_physical_closure==null or not actual_physical_closure.has_method("inspect_actual_original_world_loading_pins") or not actual_physical_closure.has_method("release_actual_original_world_loading_pins"):return false
	_caster=actual_caster;_physical=actual_physical_closure;return true
func inspect_actual_original_loading_pins(closure: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _caster==null or not closure.get("caster_closure") is Dictionary:return Observe.missing("actual_world_and_caster_pin_closure")
	var caster: Dictionary=_caster.inspect_actual_original_loading_pins(closure.caster_closure)
	if caster.get("success")!=true or caster.get("actual_closure")!=closure.caster_closure:return Observe.missing("actual_Caster_Loading_pin_inspection",caster)
	var physical: Dictionary=_physical.inspect_actual_original_world_loading_pins(closure)
	if physical.get("success")!=true or physical.get("closure")!=closure:return Observe.missing("actual_full_world_resource_pin_inspection",physical)
	return {"success":true,"closure":closure,"caster_receipt":caster,"physical_receipt":physical}
func release_original_loading_pin_closure(id: int) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _physical==null or id<=0:return Observe.missing("actual_Main_pin_owner_and_closure_required")
	# Actual physical owner orders all real claims/retentions, including Caster.
	# Do not call a second speculative Caster release after a partial mutation.
	return _physical.release_actual_original_world_loading_pins(id,_caster)
