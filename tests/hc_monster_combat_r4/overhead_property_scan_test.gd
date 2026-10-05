extends Node

const Formatter := preload("res://scripts/monster_display_formatter.gd")

class CountingEnemy extends EnemyActor:
	var property_list_requests := 0

	func _get_property_list() -> Array[Dictionary]:
		property_list_requests += 1
		return []

class GenericActor extends Node:
	var monster_id := "39"
	var display_name := "半兽勇士1"
	var monster_data := {"classification": "ordinary"}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	player.position = Vector2(2000, 2000)
	add_child(player)
	player.set_physics_process(false)
	var failures: Array[String] = []
	var measurements: Array[Dictionary] = []
	for id: int in [39, 41, 199]:
		var enemy := CountingEnemy.new()
		enemy.setup(GameData.get_monster_by_id(id), player)
		add_child(enemy)
		enemy.set_physics_process(false)
		var expected_name := Formatter.display_name(enemy.display_name, id)
		var expected_rank := Formatter.rank_for_context(id)
		enemy.property_list_requests = 0
		# Call the actual overhead path, rather than a test implementation.
		enemy.overhead._refresh_rank_visuals()
		var native_scans := enemy.property_list_requests
		if native_scans != 0:
			failures.append("native_overhead_property_enumerations:%d:%d" % [id, native_scans])
		if enemy.overhead.name_label.text != expected_name or enemy.overhead.marker_rank() != expected_rank.rank:
			failures.append("native_overhead_presentation:%d" % id)
		enemy.property_list_requests = 0
		var started := Time.get_ticks_usec()
		for iteration in range(200):
			if Formatter.display_name_for_actor(enemy) != expected_name or Formatter.rank_for_actor(enemy).rank != expected_rank.rank:
				failures.append("repeated_presentation:%d:%d" % [id, iteration])
		var elapsed := Time.get_ticks_usec() - started
		measurements.append({"monster_id": id, "iterations": 200, "elapsed_usec": elapsed,
			"native_overhead_scans": native_scans, "repeated_scans": enemy.property_list_requests})
		if enemy.property_list_requests != 0:
			failures.append("repeated_property_enumerations:%d:%d" % [id, enemy.property_list_requests])
		enemy.queue_free()
	var generic := GenericActor.new()
	if Formatter.display_name_for_actor(generic) != "半兽勇士" or Formatter.rank_for_actor(generic).rank != "ordinary":
		failures.append("generic_actor_compatibility")
	generic.free()
	var unknown := Node.new()
	if Formatter.display_name_for_actor(unknown) != "" or Formatter.rank_for_actor(unknown, true).rank != "boss":
		failures.append("unknown_actor_compatibility")
	unknown.free()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("OVERHEAD_PROPERTY_SCAN_MEASUREMENTS ", JSON.stringify(measurements))
	print("OVERHEAD_PROPERTY_SCAN_PASS" if failures.is_empty() else "OVERHEAD_PROPERTY_SCAN_FAIL " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
