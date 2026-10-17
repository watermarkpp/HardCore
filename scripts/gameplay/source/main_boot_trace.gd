extends RefCounted
## Optional Main-only startup diagnostics. No queue, state owner or clock.
## Test override records whether tracing is active in its source fingerprint.
static func mark(owner: Object, stage: String) -> void:
	if not ProjectSettings.get_setting("hardcore/diagnostics/main_boot_trace",false): return
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	var code: Script = owner.get_script()
	print("HC_MAIN_BOOT_TRACE ",JSON.stringify({"stage":stage,"script":code.resource_path,"owner":owner.get_instance_id(),"thread":OS.get_thread_caller_id(),"frame":Engine.get_process_frames(),"usec":Time.get_ticks_usec()}))
