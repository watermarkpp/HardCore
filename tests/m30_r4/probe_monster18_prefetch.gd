extends Node

const MonsterVisualStreamingCoordinator := preload(
	"res://scripts/monster_visual_streaming_coordinator.gd"
)

var _coordinator


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_coordinator = MonsterVisualStreamingCoordinator.new()
	MonsterVisual.set_streaming_coordinator(_coordinator)
	MonsterVisual.reset_client_resource_cache()
	MonsterVisual.set_synchronous_loading_for_tests(false)
	var prefetch = _coordinator.begin_map_prefetch([18])
	var deadline_msec := Time.get_ticks_msec() + 25000
	while not bool(prefetch.complete) and Time.get_ticks_msec() < deadline_msec:
		prefetch = _coordinator.poll_once(Engine.get_process_frames())
		await get_tree().process_frame
	print("M30PROBE complete=", bool(prefetch.complete), " failed=", int(prefetch.failed))
	print("M30PROBE prefetch=", JSON.stringify(prefetch))
	var catalog_file := FileAccess.open("res://assets/data/runtime/monster_animation_catalog.json", FileAccess.READ)
	var catalog: Variant = JSON.parse_string(catalog_file.get_as_text())
	for row: Dictionary in catalog.get("monsters", []):
		if int(row.monster_id) == 18:
			print("M30PROBE row18=", JSON.stringify(row))
	# Also probe a few other spiders/monsters for comparison.
	var probe_ids: Array = [11, 14, 18, 19, 20, 64]
	var prefetch2 = _coordinator.begin_map_prefetch(probe_ids)
	deadline_msec = Time.get_ticks_msec() + 40000
	while not bool(prefetch2.complete) and Time.get_ticks_msec() < deadline_msec:
		prefetch2 = _coordinator.poll_once(Engine.get_process_frames())
		await get_tree().process_frame
	print("M30PROBE batch complete=", bool(prefetch2.complete), " failed=", int(prefetch2.failed))
	print("M30PROBE batch=", JSON.stringify(prefetch2))
	get_tree().quit(0)
