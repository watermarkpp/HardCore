extends Node

const ProbeScript := preload("res://scripts/wall_runtime_perf_probe.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")

var proof := Proof.new()
var errors: Array[String] = []
var checks := 0
var zone_name := "wall-test-a"
var _staged_generation := 7
var _staged_build_complete := true
var map_id := 101
var _editor_runtime_bridge_commands: Array = []

func _ready() -> void:
	_run.call_deferred()

func _active_map_id() -> int:
	return map_id

func check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value, label)
	if not value:
		errors.append(label)

func _run() -> void:
	var scan_root := Node2D.new()
	add_child(scan_root)
	var wrapper := Node2D.new()
	wrapper.set_meta("editor_runtime_actor_occluder", true)
	scan_root.add_child(wrapper)
	var base := _sprite(Color(0.9, 0.1, 0.1), true, 1)
	var front := _sprite(Color(0.1, 0.9, 0.1), false, 2)
	var bridge := _sprite(Color(0.1, 0.1, 0.9), true, -1)
	bridge.set_meta("static_authored_wall_bridge", true)
	wrapper.add_child(base)
	wrapper.add_child(front)
	wrapper.add_child(bridge)
	var probe := ProbeScript.new()
	add_child(probe)
	probe.configure(self, scan_root, false)

	var counts: Dictionary = probe._collect_counts()
	check(int(counts["wrapper_dynamic_children"]) == 2, "dynamic total excludes bridge")
	check(int(counts["visible_dynamic_children"]) == 1, "visible dynamic counts each visible child")
	check(int(counts["visible_bridge_overlay_count"]) == 1, "bridge count is independent")
	check(int(counts["visible_wrappers"]) == 1, "bridge or dynamic visibility marks wrapper")

	base.visible = false
	bridge.visible = true
	counts = probe._collect_counts()
	check(int(counts["visible_dynamic_children"]) == 0, "bridge-only wrapper has zero visible dynamic children")
	check(int(counts["visible_wrappers"]) == 1, "bridge-only wrapper remains visible")

	probe.start_window("wall-test-a", 10.0)
	probe._process(0.016)
	map_id = 202
	_staged_generation = 8
	zone_name = "wall-test-b"
	probe._process(0.016)
	check(not bool(probe._active), "identity change cancels active sample")
	check(probe._frame_deltas.is_empty(), "cancel discards old frame samples")
	check(int(probe._window_identity.get("map_id", -1)) == 202, "restart identity binds new map")
	check(int(probe._window_identity.get("generation", -1)) == 8, "restart identity binds new generation")
	check(str(probe._window_identity.get("zone", "")) == "wall-test-b", "restart identity binds new zone")

	print("B28_WALL_PROBE_PASS checks=%d" % checks)
	if not proof.write_receipt("wall_runtime_perf_probe_contract_test", checks, errors.size()):
		errors.append("receipt write failed")
	get_tree().quit(0 if errors.is_empty() else 1)

func _sprite(color: Color, visible: bool, pass_index: int) -> Sprite2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(color)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.visible = visible
	sprite.set_meta("editor_runtime_image_pass", pass_index)
	return sprite
