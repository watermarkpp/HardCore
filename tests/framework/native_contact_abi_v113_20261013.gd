extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Reference := preload("res://scripts/monster_crowd_attack_position_policy.gd")
const Neighbor := preload("res://scripts/monster_neighbor_step_policy.gd")
const GU := preload("res://scripts/ground_unit_space.gd")
const SCENE_ID := "native_contact_abi_v113_20261013"
const EXTENSION := "res://research/native/crowd_batch_v113/crowd_batch_v113.gdextension"
const DLL := "res://research/native/crowd_batch_v113/bin/crowd_batch_v113.windows.template_debug.x86_64.dll"
var proof := Proof.new()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if FileAccess.file_exists(DLL):
		var status := GDExtensionManager.load_extension(ProjectSettings.globalize_path(EXTENSION))
		proof.record(status in [GDExtensionManager.LOAD_STATUS_OK, GDExtensionManager.LOAD_STATUS_ALREADY_LOADED], "official_extension_loaded")
	var available := ClassDB.class_exists("HardCoreV113CrowdBatchKernel")
	proof.record(available, "native_contact_interface_exists")
	if not available:
		print("EXPECTED_RED_NATIVE_CONTACT_INTERFACE_MISSING")
		_finish()
		return
	var kernel: Variant = ClassDB.instantiate("HardCoreV113CrowdBatchKernel")
	proof.record(int(kernel.get_abi_version()) == 11301, "abi_version")
	var directions := PackedVector2Array()
	for delta: Vector2i in Neighbor.NEIGHBOR_DELTAS: directions.append(Vector2(delta))
	var cases: Array[Dictionary] = [
		{"origin": Vector2.ZERO, "centers": PackedVector2Array(), "radii": PackedFloat64Array(), "target": false},
		{"origin": Vector2.ZERO, "centers": PackedVector2Array([Vector2.ZERO]), "radii": PackedFloat64Array([0.7]), "target": false},
		{"origin": Vector2(-3, -5), "centers": PackedVector2Array([Vector2(-2.3, -5), Vector2(-3, -4.3)]), "radii": PackedFloat64Array([0.7, 0.7]), "target": true},
		{"origin": Vector2.ZERO, "centers": PackedVector2Array([Vector2(0.7, 0), Vector2(2, 2), Vector2(-0.7, 0)]), "radii": PackedFloat64Array([0.7, 0.0, 0.7]), "target": false}]
	seed(20261013)
	# Preserve GDScript float (double) until the final Vector2 operation.
	# These straddle the EPSILON cutoff and expose early real_t rounding.
	for offset in [-5e-12, 0.0, 5e-12]:
		for origin: Vector2 in [Vector2.ZERO, Vector2(-3, -5)]:
			cases.append({"origin": origin,
				"centers": PackedVector2Array([origin + Vector2.RIGHT]),
				"radii": PackedFloat64Array([1.0 - 2.0 * GU.EPSILON_GU + offset]), "target": false})
	for serial in range(200):
		var centers := PackedVector2Array()
		var radii := PackedFloat64Array()
		var origin := Vector2(randf_range(-10, 10), randf_range(-10, 10))
		for peer in range(serial % 35):
			centers.append(origin + Vector2(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5)))
			radii.append(randf_range(0.0, 1.2))
		cases.append({"origin": origin, "centers": centers, "radii": radii, "target": serial % 2 == 0})
	for serial in range(cases.size()):
		var record: Dictionary = cases[serial]
		var target := Vector2(record.origin) + Vector2(0.5, -0.75)
		var expected := _reference(record.origin, directions, record.centers, record.radii, record.target, target, 0.65)
		var actual: PackedVector2Array = kernel.contact_rays(record.origin, directions, record.centers, record.radii, record.target, target, 0.65, GU.EPSILON_GU)
		proof.record(actual == expected, "exact_original_geometry:%d" % serial)
	var invalid: PackedVector2Array = kernel.contact_rays(Vector2.ZERO, PackedVector2Array([Vector2.ZERO]), PackedVector2Array(), PackedFloat64Array(), false, Vector2.ZERO, 0.0, GU.EPSILON_GU)
	proof.record(invalid.is_empty(), "invalid_direction_count_rejected")
	invalid = kernel.contact_rays(Vector2.INF, directions, PackedVector2Array(), PackedFloat64Array(), false, Vector2.ZERO, 0.0, GU.EPSILON_GU)
	proof.record(invalid.is_empty(), "infinite_origin_rejected")
	invalid = kernel.contact_rays(Vector2.ZERO, directions, PackedVector2Array([Vector2.ZERO]), PackedFloat64Array([-1.0]), false, Vector2.ZERO, 0.0, GU.EPSILON_GU)
	proof.record(invalid.is_empty(), "negative_radius_rejected")
	invalid = kernel.contact_rays(Vector2.ZERO, directions, PackedVector2Array([Vector2.ZERO]), PackedFloat64Array(), false, Vector2.ZERO, 0.0, GU.EPSILON_GU)
	proof.record(invalid.is_empty(), "length_mismatch_rejected")
	invalid = kernel.contact_rays(Vector2.ZERO, directions, PackedVector2Array([Vector2(NAN, 0)]), PackedFloat64Array([0.5]), false, Vector2.ZERO, 0.0, GU.EPSILON_GU)
	proof.record(invalid.is_empty(), "nan_peer_rejected")
	var changed_centers := PackedVector2Array([Vector2.RIGHT])
	var changed_radii := PackedFloat64Array([0.8])
	var first: PackedVector2Array = kernel.contact_rays(Vector2.ZERO, directions, changed_centers, changed_radii, false, Vector2.ZERO, 0.0, GU.EPSILON_GU)
	changed_centers[0] = Vector2.LEFT
	var second: PackedVector2Array = kernel.contact_rays(Vector2.ZERO, directions, changed_centers, changed_radii, false, Vector2.ZERO, 0.0, GU.EPSILON_GU)
	proof.record(first != second and second == _reference(Vector2.ZERO, directions, changed_centers, changed_radii, false, Vector2.ZERO, 0.0), "changed_input_consumed_synchronously")
	proof.record(changed_centers == PackedVector2Array([Vector2.LEFT]) and changed_radii == PackedFloat64Array([0.8]), "packed_inputs_not_mutated")
	var stats: Dictionary = kernel.get_statistics()
	proof.record(int(stats.get("calls", 0)) >= cases.size(), "real_native_entries")
	kernel = null
	_finish()

func _reference(origin: Vector2, directions: PackedVector2Array, centers: PackedVector2Array, radii: PackedFloat64Array, has_target: bool, target: Vector2, target_radius: float) -> PackedVector2Array:
	var output := PackedVector2Array()
	for direction: Vector2 in directions:
		var extent := 1.0
		for index in range(centers.size()):
			extent = Reference._free_ray_extent(origin, direction, centers[index], radii[index], extent)
			if extent <= GU.EPSILON_GU: break
		if extent > GU.EPSILON_GU and has_target:
			extent = Reference._free_ray_extent(origin, direction, target, target_radius, extent)
		output.append(origin + direction * extent if extent > GU.EPSILON_GU else Vector2.INF)
	return output

func _finish() -> void:
	var failed := 0
	for record: Dictionary in proof.records:
		if not bool(record.get("passed", false)): failed += 1
	var ok := proof.write_receipt(SCENE_ID, proof.records.size(), failed)
	print("NATIVE_CONTACT_ABI_", "PASS" if failed == 0 and ok else "FAIL")
	get_tree().quit(0 if failed == 0 and ok else 1)
