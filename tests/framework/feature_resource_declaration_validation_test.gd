extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Registry := preload("res://scripts/features/compilation/feature_resource_registry.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value,label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.recalculate_stats(false)
	var cached := Registry.declarations()
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Registry.PATH))
	check(cached.success and Registry.validate(original).success, "the real trusted texture and audio declarations validate through the production parser")
	var invalid: Array = [null,[],{"schema_version":2,"resources":[]},{"schema_version":1,"resources":{}},
		{"schema_version":1,"resources":["invalid"]}]
	for property: String in ["type","path","origin","resource_id"]:
		var value := original.duplicate(true)
		value.resources[1][property] = []
		invalid.append(value)
	for sound_id: Variant in [null,"137",[],137.5,9999]:
		var value := original.duplicate(true)
		value.resources[1].origin.sound_id = sound_id
		invalid.append(value)
	for event_id: Variant in [null,137,"unknown.event","player.skill.slaying"]:
		var value := original.duplicate(true)
		value.resources[1].origin.event_id = event_id
		invalid.append(value)
	for property: String in ["resource_id","path"]:
		var value := original.duplicate(true)
		value.resources[1][property] = value.resources[0][property]
		invalid.append(value)
	for path: String in ["res://scripts/player.gd","res://assets/audio/sfx/client/../client/137__M26-3.wav","user://137.wav"]:
		var value := original.duplicate(true)
		value.resources[1].path = path
		invalid.append(value)
	for index in range(invalid.size()):
		var result := Registry.validate(invalid[index])
		check(not result.success and result.records.is_empty() and not result.errors.is_empty(), "invalid declaration %d rejects the entire candidate without partial grants" % index)
	check(is_same(Registry.declarations(),cached) and Registry.declarations().success,
		"pure candidate validation never poisons or replaces the previously published resource authority")
	if not proof.write_receipt("feature_resource_declaration_validation_test",checks,failures.size()): failures.append("receipt")
	print("FEATURE_RESOURCE_DECLARATION_VALIDATION_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
