extends Node
const BodyCapture := preload("res://scripts/gameplay/world/world_environment_boot_publication.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failed := 0
func check(value: bool, label: String) -> void:
	_proof.record(value,label)
	if not value: _failed += 1
func _ready() -> void:
	var graph: Object = ClassDB.instantiate("HardCoreContentValueGraph")
	var body: Dictionary = BodyCapture._capture_body_templates()
	check(body.get("ok") == true,"actual original body configuration is available")
	if body.get("ok") != true: _finish(); return
	var motion: Dictionary = body.value.motion.duplicate(true)
	motion.footprint_points = body.value.footprints.player.footprint_points
	motion.position_screen_px = Vector2.ZERO
	motion.merge(body.value.filters.player)
	check(typeof(motion.keys()[5]) == TYPE_STRING_NAME,"actual GDScript named assignment produces immutable StringName key")
	var copied: Dictionary = graph.capture(motion,true,false)
	check(copied.get("success") == true,"runtime graph accepts exact real motion fields without rewriting their key types")
	if copied.get("success") == true:
		check(copied.value == motion and copied.value.is_read_only(),"runtime motion values are exact and recursively sealed")
		check(typeof(copied.value.keys()[5]) == TYPE_STRING_NAME and copied.value.footprint_points == motion.footprint_points,"runtime name and 16-vertex geometry types survive capture")
	var ordinary := {"field":7}
	check(graph.capture(ordinary,true).success,"ordinary content/save dictionary remains supported")
	var named: Dictionary = {}
	named.field = 7
	check(not graph.capture(named,true).success and not graph.validate(named).success,"default strict content/save mode still rejects non-String JSON keys")
	check(graph.validate(named,false).success,"runtime validation agrees with runtime capture for exact name keys")
	var shared: Array[int] = [1,2]
	var source: Dictionary = {&"a":shared,&"b":shared,&"other":[1,2]}
	var alias: Dictionary = graph.capture(source,false,false)
	check(alias.success,"runtime StringName graph capture accepts shared typed arrays")
	if alias.success:
		alias.value[&"a"].append(3)
		check(alias.value[&"b"] == [1,2,3] and alias.value[&"other"] == [1,2] and shared == [1,2],"name-key transport preserves aliases without mutating original or equal-distinct arrays")
	var typed: Dictionary[StringName,Vector2] = {&"position":Vector2(3,4)}
	var typed_copy: Dictionary = graph.capture(typed,true,false)
	check(typed_copy.success,"typed runtime StringName dictionary accepted")
	if typed_copy.success: check(typed_copy.value.get_typed_key_builtin() == TYPE_STRING_NAME and typed_copy.value.get_typed_value_builtin() == TYPE_VECTOR2,"typed runtime declarations remain exact")
	check(not graph.capture({true:1},true,false).success,"runtime bool keys remain rejected")
	check(not graph.capture({self:1},true,false).success,"runtime object keys remain rejected")
	check(not graph.capture({&"actor":self},true,false).success,"allowing runtime name keys never allows Node values")
	check(not graph.capture({&"bad":NAN},true,false).success,"runtime nonfinite scalars remain rejected")
	var cycle: Dictionary = {}
	cycle.self = cycle
	check(not graph.capture(cycle,true,false).success,"runtime name-key cycle remains rejected")
	cycle.erase(&"self")
	_finish()
func _finish() -> void:
	var written: bool = _proof.write_receipt("runtime_name_keys_20261015",_proof.records.size(),_failed)
	print("RUNTIME_NAME_KEYS_20261015_", "PASS" if written and _failed == 0 else "FAIL", " checks=",_proof.records.size()," failures=",_failed)
	get_tree().quit(0 if written and _failed == 0 else 1)
