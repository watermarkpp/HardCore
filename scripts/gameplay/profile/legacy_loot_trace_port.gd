extends RefCounted

func write_trace(trace: Dictionary) -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	var path := "user://dpv2_v5_trace.jsonl"
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(JSON.stringify(trace))
