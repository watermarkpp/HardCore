extends Node

## Player overhead status marker row (R1.1 closure) — focused unit coverage.
## The player health bar must own a PlayerStatusMarkerStrip directly below the
## bar, bound to the player actor, exposing fixed-slot markers (paralysis left,
## poison right) that follow the established overhead dot idiom. The full
## real-boot integration lives in player_poison_presentation_test.

const PlayerHealthBarScript := preload("res://scripts/player_health_bar.gd")
const PlayerStatusMarkerStripScript := preload("res://scripts/player_status_marker_strip.gd")


class StubActor extends Node:
	var control_time := 0.0
	var current_hp := 100
	var poison_time := 0.0
	var monster_source_remaining := 0.0

	func poison_status_remaining() -> float:
		return maxf(poison_time, monster_source_remaining)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures := 0

	# --- 1. Standalone health bar wires the strip below the bar --------------
	var bar: PlayerHealthBar = PlayerHealthBarScript.new()
	add_child(bar)
	await get_tree().process_frame
	var strip: PlayerStatusMarkerStrip = bar.status_marker_strip
	if strip == null or strip.name != "PlayerStatusMarkerStrip":
		push_error("health bar must own a PlayerStatusMarkerStrip child")
		failures += 1
	var expected_position: Vector2 = bar.layout_snapshot()["status_marker_strip_position"]
	if strip.position != expected_position or not is_equal_approx(strip.position.y, bar.BAR_SIZE.y + 5.0):
		push_error("marker row must sit %s below the bar, got %s" % [str(expected_position), str(strip.position)])
		failures += 1
	# No bound source -> no markers, never a crash.
	if not strip.active_status_markers().is_empty():
		push_error("unbound strip must report no markers")
		failures += 1
	# The layout contract publishes the marker row position.
	if not bar.layout_snapshot().has("status_marker_strip_position"):
		push_error("layout_snapshot must publish the marker row contract")
		failures += 1
	bar.queue_free()
	await get_tree().process_frame

	# --- 2. Strip lifecycle against a duck-typed actor -----------------------
	var actor := StubActor.new()
	add_child(actor)
	var strip2: PlayerStatusMarkerStrip = PlayerStatusMarkerStripScript.new()
	add_child(strip2)
	await get_tree().process_frame
	strip2.bind_status_source(actor)
	if not strip2.active_status_markers().is_empty():
		push_error("clean actor must report no markers")
		failures += 1

	actor.poison_time = 8.0
	if ",".join(strip2.active_status_markers()) != "poison":
		push_error("legacy poison must show exactly the poison marker")
		failures += 1
	actor.poison_time = 0.0
	actor.monster_source_remaining = 9.0
	if ",".join(strip2.active_status_markers()) != "poison":
		push_error("monster-source poison must show exactly the poison marker")
		failures += 1
	actor.control_time = 5.0
	if ",".join(strip2.active_status_markers()) != "paralysis,poison":
		push_error("both states must report paralysis first, poison second (fixed order)")
		failures += 1
	# Fixed slots: paralysis left, poison right, never re-centered.
	if not (strip2.marker_slot_center("paralysis").x < 0.0 and strip2.marker_slot_center("poison").x > 0.0):
		push_error("fixed slot geometry violated")
		failures += 1
	if not strip2.marker_slot_center("paralysis").is_equal_approx(Vector2(-5.0, 0.0)):
		push_error("paralysis slot must mirror the monster dot offset (-5, 0)")
		failures += 1
	# Poison ends: paralysis keeps its slot.
	actor.poison_time = 0.0
	actor.monster_source_remaining = 0.0
	if ",".join(strip2.active_status_markers()) != "paralysis":
		push_error("paralysis keeps its own slot after poison ends")
		failures += 1
	# Paralysis ends: row empty.
	actor.control_time = 0.0
	if not strip2.active_status_markers().is_empty():
		push_error("row must empty when both states end")
		failures += 1
	# Death hides every marker without touching gameplay values.
	actor.poison_time = 30.0
	actor.control_time = 5.0
	actor.current_hp = 0
	if not strip2.active_status_markers().is_empty():
		push_error("a dead actor must show no status markers")
		failures += 1
	if actor.poison_time <= 0.0 or actor.control_time <= 0.0:
		push_error("marker presentation must never mutate gameplay timers")
		failures += 1
	strip2.queue_free()
	actor.queue_free()
	await get_tree().process_frame

	# --- 3. Real binding path: health bar under a duck-typed parent ----------
	var actor2 := StubActor.new()
	add_child(actor2)
	var bar2: PlayerHealthBar = PlayerHealthBarScript.new()
	actor2.add_child(bar2)
	await get_tree().process_frame
	await get_tree().process_frame
	var strip3: PlayerStatusMarkerStrip = bar2.status_marker_strip
	if strip3 == null:
		push_error("wired health bar must create the marker strip")
		failures += 1
	else:
		actor2.poison_time = 4.0
		if ",".join(strip3.active_status_markers()) != "poison":
			push_error("health bar must bind the marker strip to its owning actor")
			failures += 1
		actor2.poison_time = 0.0
	bar2.queue_free()
	actor2.queue_free()
	await get_tree().process_frame

	for index in range(failures):
		push_error("failure %d recorded above" % (index + 1))
	print("PLAYER_HEALTH_BAR_STATUS_MARKER_%s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
