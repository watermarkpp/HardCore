extends RefCounted
const View := preload("res://scripts/gameplay/world/world_profile_ui_view.gd")
var _owner := OS.get_thread_caller_id()
var _core: WeakRef
var _profile: WeakRef
var _serial := 0
var _signals: Array[StringName]=[&"profile_changed",&"inventory_changed",&"equipment_changed",&"skills_changed",&"quests_changed"]
func owner_thread_id() -> int: return _owner
func configure_owner(core: RefCounted) -> bool:
	if _core!=null or core.owner_thread_id()!=_owner or _owner==OS.get_main_thread_id(): return false
	_core=weakref(core);_profile=weakref(core.profile)
	for name: StringName in _signals: core.profile.connect(name,publish_actual_view)
	return publish_actual_view()
func publish_actual_view() -> bool:
	var core: RefCounted=_core.get_ref()
	if core==null: return false
	var next_sequence: int=core.original_source_session().next_original_profile_view_sequence()
	var snapshot: Dictionary=View.capture_actual_owner(core,next_sequence)
	if snapshot.is_empty() or not core.emit_original_main_event(&"original_profile_view",[snapshot]): return false
	_serial=next_sequence
	return true
func detach_at_original_world_exit() -> bool:
	var profile: RefCounted=_profile.get_ref()
	if profile!=null:
		for name: StringName in _signals:
			if profile.is_connected(name,publish_actual_view): profile.disconnect(name,publish_actual_view)
	_profile=null;_core=null
	return true
