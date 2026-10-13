extends Node
const Publisher := preload("res://tools/map_editor/rebuild_monster_navigation_profiles_v113.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SCENE_ID := "publish_monster_navigation_v113"

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	var publisher := Publisher.new()
	var output_dir := OS.get_environment("HARDCORE_NAVIGATION_OUTPUT_DIR")
	var result := publisher.execute(OS.get_environment("HARDCORE_NAVIGATION_MANIFEST"), int(OS.get_environment("HARDCORE_NAVIGATION_MAP_ID")), output_dir)
	publisher.free()
	var proof := Proof.new()
	proof.record(bool(result.ok), "formal navigation publication and complete preservation: " + str(result.get("reason", "PASS")))
	var receipt_ok := proof.write_receipt(SCENE_ID, 1, 0 if result.ok else 1)
	if not output_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
		FileAccess.open(output_dir.path_join("publication.result.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	print("PUBLISH_MONSTER_NAVIGATION_V113_", "PASS" if result.ok and receipt_ok else "FAIL", " ", JSON.stringify(result))
	get_tree().quit(0 if result.ok and receipt_ok else 1)
