extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Calibration := preload("res://scripts/map_assets/map_asset_calibration_service.gd")
const Catalog := preload("res://scripts/map_assets/map_asset_catalog_service.gd")
const InstanceService := preload("res://scripts/map_editor/map_editor_instance_service.gd")
const Types := preload("res://scripts/map_editor/map_editor_types.gd")
const ASSET_ID := "cave_granite_straight_x_l1_v01"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var proof := Proof.new()
	var path := "user://v109_map_asset_override_%d.json" % Time.get_ticks_usec()
	Catalog.set_override_path_for_test(path)
	var before := Catalog.find_asset(ASSET_ID)
	proof.record(not before.is_empty(), "base catalog asset resolves")
	var valid := {"anchor_px": [77, 88], "footprint_tiles": [2, 2], "collision_policy": "wall_cells_generated", "placeable": true, "calibration_status": "placeable"}
	var saved := Calibration.save_override(ASSET_ID, valid, path)
	proof.record(bool(saved.get("ok", false)), "valid calibration override saves")
	var after := Catalog.find_asset(ASSET_ID)
	var refreshed_anchor: Array = after.get("anchor_px", [])
	var refreshed_footprint: Array = after.get("footprint_tiles", [])
	proof.record(refreshed_anchor.size() == 2 and is_equal_approx(float(refreshed_anchor[0]), 77.0) and is_equal_approx(float(refreshed_anchor[1]), 88.0) and refreshed_footprint.size() == 2 and int(refreshed_footprint[0]) == 2 and int(refreshed_footprint[1]) == 2, "new catalog lookup reads anchor and footprint")
	var document := Types.new_map_from_catalog("v109_recovery", "dungeon_floor", 1, "recovery")
	var placed := InstanceService.create_instance(document, ASSET_ID, "obstacle", Vector2i(4, 4))
	proof.record(bool(placed.get("ok", false)), "new instance resolves refreshed catalog")
	if bool(placed.get("ok", false)):
		proof.record(placed.instance.get("anchor_px", []) == after.get("placement_anchor_px", []), "new instance uses refreshed placement anchor")
		var instance_footprint: Array = placed.instance.get("footprint_tiles", [])
		var instance_policy := str(placed.instance.get("collision_policy", ""))
		print("INSTANCE_POLICY ", instance_policy, " FOOT ", JSON.stringify(instance_footprint))
		proof.record(instance_footprint.size() == 2 and int(instance_footprint[0]) == 2 and int(instance_footprint[1]) == 2 and instance_policy == "wall_cells_generated", "new instance uses refreshed footprint and manual collision authority")
	var bytes_before_failure := FileAccess.get_file_as_bytes(path)
	var failed := Calibration.save_override(ASSET_ID, {"anchor_px": [-1, 0], "footprint_tiles": [0, 2], "collision_policy": "invalid"}, path)
	proof.record(not bool(failed.get("ok", true)), "invalid calibration is rejected")
	proof.record(FileAccess.get_file_as_bytes(path) == bytes_before_failure, "failed calibration preserves previous override")
	var failures := proof.records.filter(func(item: Dictionary) -> bool: return not bool(item.get("passed", false))).size()
	var receipt_ok: bool = proof.write_receipt("v109_map_asset_catalog_recovery_test", proof.records.size(), failures)
	print("V109_MAP_ASSET_CATALOG_RECOVERY_%s" % ("PASS" if receipt_ok else "FAIL"))
	get_tree().quit(0 if receipt_ok else 1)
