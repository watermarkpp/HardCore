extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Scope := preload("res://scripts/features/contracts/loading_preparation_scope.gd")
var _proof := Proof.new()
var _failed := 0
func check(ok: bool,label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1; print("CHARACTER_COVER_CAMERA_FAILED ",label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	check(OS.get_user_data_dir().replace("\\","/").contains("/.godot/runtime_appdata/"),"actual CharacterSelect uses isolated original user data")
	var launcher: Control = load("res://scenes/character_select.tscn").instantiate()
	add_child(launcher)
	var overlay: Control = launcher.get("launch_loading_overlay")
	overlay.begin_loading("actual_character_cover_camera")
	await overlay.transition_covered
	var receipt: Dictionary = overlay.code_preparation_cover_receipt()
	check(not receipt.is_empty(),"actual original CharacterSelect overlay has a physically presented full viewport receipt")
	var prior: Transform2D = get_viewport().get_canvas_transform()
	var camera := Camera2D.new()
	camera.position = Vector2(173,91); camera.zoom = Vector2(1.37,1.37)
	add_child(camera); camera.make_current(); camera.force_update_scroll()
	check(get_viewport().get_camera_2d() == camera and get_viewport().get_canvas_transform() != prior,"actual new World camera changes the viewport world transform")
	check(overlay.code_preparation_cover_current(receipt),"same genuine launch cover remains valid while actual World camera is constructed")
	check(overlay.shade.get_global_transform_with_canvas() == Transform2D.IDENTITY,"opaque cover stays in screen coordinates independently of world zoom and position")
	check(Scope._same_cover_owner(overlay,launcher),"actual CharacterSelect owns the same original cover through its precise screen carrier")
	check(Scope.issue(overlay,launcher,int(launcher.get("_launch_code_generation"))) == null,"screen carrier never grants a permit outside the actual launch phase")
	var foreign := CanvasLayer.new(); add_child(foreign)
	overlay.reparent(foreign)
	check(not Scope._same_cover_owner(overlay,launcher),"a foreign screen layer cannot impersonate the CharacterSelect-owned carrier")
	# This continuation resumes inside the real overlay's transition signal.
	# Do not destroy its sender before that original signal has returned.
	launcher.queue_free(); camera.queue_free(); foreign.queue_free()
	await get_tree().process_frame
	var written: bool = _proof.write_receipt("character_launch_cover_camera_20261017",_proof.records.size(),_failed)
	print("CHARACTER_LAUNCH_COVER_CAMERA_20261017_","PASS" if written and _failed == 0 else "FAIL")
	get_tree().quit(0 if written and _failed == 0 else 1)
