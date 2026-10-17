extends RefCounted

var modes: Dictionary:
	get:
		assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
		return GameModes.modes

func prepare_mode_configuration(mode_id: String, later_override: Variant = null) -> Dictionary:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	return GameModes.prepare_mode_configuration(mode_id, later_override)

func apply_prepared_mode_configuration(prepared: Dictionary) -> bool:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	return GameModes.apply_prepared_mode_configuration(prepared)
