extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _checks := 0
var _failures := 0
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var digest: String = preload("res://scripts/gameplay/source/source_command_digest.gd").bytes_sha256("abc".to_utf8_buffer())
	_checks += 1
	var digest_valid: bool = digest=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
	_proof.record(digest_valid,"original command raw bytes SHA256 matches known abc vector")
	if not digest_valid: _failures += 1
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://outputs/v115_multicore/root_integration_20261014/SEMANTIC_SOURCE_INPUTS.json"))
	if not manifest is Dictionary or not manifest.get("targets") is Array:
		_checks += 1; _failures += 1; _proof.record(false,"actual fixed semantic source manifest exists")
	else:
		# Inspect fixed source text against the actual registered native names
		# before loading dependency graphs; grammar-only checks miss this case.
		var names: PackedStringArray = ClassDB.get_class_list()
		var declarations := RegEx.new()
		declarations.compile("(?m)^(?:const|var|class) ([A-Za-z_][A-Za-z0-9_]*)")
		var declaration_failures := 0
		for row: Dictionary in manifest.targets:
			for found: RegExMatch in declarations.search_all(FileAccess.get_file_as_string("res://"+row.path)):
				if found.get_string(1) not in names: continue
				_checks += 1; _failures += 1; declaration_failures += 1
				_proof.record(false,"source declaration shadows actual native class "+found.get_string(1)+" in "+row.path)
		if declaration_failures>0:
			_finish()
			return
		for row: Dictionary in manifest.targets:
			_checks += 1
			var exact: bool = FileAccess.get_sha256("res://"+row.path)==row.sha256
			var code: Script = load("res://"+row.path) as Script if exact else null
			var valid: bool = exact and code!=null and code.can_instantiate()
			_proof.record(valid,"actual Godot semantic compiler accepts fixed source "+row.path)
			if not valid: _failures += 1
	_finish()
func _finish() -> void:
	var written: bool = _proof.write_receipt("multicore_v115_script_semantic_20261015",_checks,_failures)
	print("MULTICORE_V115_SCRIPT_SEMANTIC_", "PASS" if _failures==0 and written else "FAIL", " checks=",_checks," failures=",_failures)
	get_tree().quit(0 if _failures==0 and written else 1)
