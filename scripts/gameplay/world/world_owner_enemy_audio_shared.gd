extends RefCounted
## The four original Enemy static audio lookup scalars in one S session.
var _owner := OS.get_thread_caller_id()
var _audio_runtime_service: RefCounted
var _audio_service_retry_after_msec := 0
var _audio_service_lookup_count := 0
var _audio_service_now_override_msec := -1
func owner_thread_id() -> int: return _owner
var _original_handoff_applied := false
func configure_handoff(publication: Dictionary, audio_primitives: RefCounted) -> bool:
	if OS.get_thread_caller_id() != _owner or _original_handoff_applied or publication.size() != 5 or publication.get("contract_id") != "world.enemy.audio_shared.handoff.v1" or not publication.has("_audio_runtime_service"): return false
	for field: String in ["_audio_service_retry_after_msec", "_audio_service_lookup_count", "_audio_service_now_override_msec"]:
		if not publication.get(field) is int: return false
		set(field, publication[field])
	if publication.get("_audio_runtime_service") != null:
		if not publication._audio_runtime_service is Dictionary: return false
		_audio_runtime_service = audio_primitives.adopt_registered_service(publication._audio_runtime_service)
		if _audio_runtime_service == null: return false
	_original_handoff_applied = true
	return true

func original_handoff_applied() -> bool: return _original_handoff_applied
