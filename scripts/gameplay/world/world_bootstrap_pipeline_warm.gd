extends RefCounted
## Composes the existing travel owner; only four original warm leaves are new.
var _owner := OS.get_thread_caller_id()
var _travel: RefCounted
var _warm: RefCounted
func configure_owner(original_travel: RefCounted, actual_warm: RefCounted) -> bool:
	if _travel != null or original_travel == null or actual_warm == null or OS.get_thread_caller_id() == OS.get_main_thread_id(): return false
	if original_travel.owner_thread_id() != _owner or actual_warm.owner_thread_id() != _owner: return false
	_travel = original_travel; _warm = actual_warm
	return true
func owner_thread_id() -> int: return _owner
func travel_to_service_home(force: bool, staged: bool, region: String) -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	return _travel.travel_to_service_home(force,staged,region)
func pump_pending_warm_textures() -> void: _warm.pump_pending_warm_textures()
func retire_pending_warm_textures() -> bool: return _warm.retire_pending_warm_textures()
func retire_loading_texture_claims() -> bool: return _warm.retire_loading_texture_claims()
func set_loading_window_active(active: bool) -> bool: return _warm.set_loading_window_active(active)
func original_frame_texture_claim_facts() -> Dictionary: return _warm.original_frame_texture_claim_facts()
func actual_original_warm_owner_quiescent() -> bool: return _warm.actual_original_warm_owner_quiescent()
