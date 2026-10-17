extends RefCounted

func performance_detail_enabled() -> bool:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	return RuntimeDiagnostics.performance_detail_enabled()

func increment_performance_counter(category: StringName, amount := 1) -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	RuntimeDiagnostics.increment_performance_counter(category, amount)

func record_performance_max(category: StringName, value: float) -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	RuntimeDiagnostics.record_performance_max(category, value)
