extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Diagnostics := preload("res://scripts/runtime_diagnostics.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var proof := Proof.new()
	var enabled := Diagnostics.set_device_lab_performance_enabled(true)
	proof.record(enabled, "debug performance diagnostics gate enabled")
	Diagnostics.set_device_lab_detail_mode(Diagnostics.DEVICE_LAB_DETAIL_FULL)
	Diagnostics.reset_performance_window()
	# These are the public producer keys used by the death/drop/loot prepare
	# slices; invoke the registered API rather than manufacturing the export map.
	Diagnostics.increment_performance_counter(&"death_work_frames", 2)
	Diagnostics.increment_performance_counter(&"death_prepare_usec", 6)
	Diagnostics.increment_performance_counter(&"drop_roll_count", 3)
	Diagnostics.increment_performance_counter(&"drop_roll_slice_count", 7)
	Diagnostics.increment_performance_counter(&"loot_prepare_bucket_2_count", 4)
	Diagnostics.increment_performance_counter(&"loot_commit_bucket_2_count", 5)
	var full := Diagnostics.read_performance_window({"source": "v109_dynamic_counter_export"})
	var counters: Dictionary = full.get("counters", {})
	proof.record(int(full.get("death_prepare_usec", -1)) == 6, "dynamic death preparation counter is exported at window top level")
	proof.record(int(counters.get("death_prepare_usec", -1)) == 6 and Diagnostics.performance_counter(&"death_prepare_usec") == 6, "dynamic death counter agrees across window, counters and getter")
	proof.record(int(counters.get("death_work_frames", -1)) == 2, "stable death counter remains exported")
	proof.record(int(counters.get("drop_roll_count", -1)) == 3, "stable drop counter remains exported")
	proof.record(int(full.get("drop_roll_slice_count", -1)) == 7 and int(counters.get("drop_roll_slice_count", -1)) == 7, "dynamic drop slice counter is exported")
	proof.record(int(counters.get("loot_prepare_bucket_2_count", -1)) == 4, "dynamic loot prepare bucket is exported")
	proof.record(int(counters.get("loot_commit_bucket_2_count", -1)) == 5, "dynamic loot commit bucket is exported")
	proof.record(counters.has("foreground_ai_ticks") and int(counters.get("foreground_ai_ticks", -1)) == 0, "stable schema keeps an unincremented zero-valued field")

	Diagnostics.set_device_lab_detail_mode(Diagnostics.DEVICE_LAB_DETAIL_FRAME_ONLY)
	Diagnostics.reset_performance_window()
	Diagnostics.increment_performance_counter(&"loot_prepare_bucket_2_count", 9)
	var frame_only := Diagnostics.read_performance_window()
	var frame_counters: Dictionary = frame_only.get("counters", {})
	proof.record(not frame_counters.has("loot_prepare_bucket_2_count"), "frame_only rejects detailed dynamic counters")
	proof.record(int(frame_counters.get("death_work_frames", -1)) == 0, "frame_only retains stable zero schema")
	Diagnostics.set_device_lab_detail_mode(Diagnostics.DEVICE_LAB_DETAIL_FULL)
	var failures := proof.records.filter(func(item: Dictionary) -> bool: return not bool(item.get("passed", false))).size()
	var receipt_ok: bool = proof.write_receipt("v109_diagnostics_dynamic_counter_export_test", proof.records.size(), failures)
	print("V109_DIAGNOSTICS_DYNAMIC_COUNTER_%s" % ("PASS" if receipt_ok else "FAIL"))
	get_tree().quit(0 if receipt_ok else 1)
