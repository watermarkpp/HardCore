class_name CasterProfessionRegistry
extends RefCounted

const INDEX_PATH := "res://assets/data/vanilla_176/profession_packages/index.json"
const PACKAGE_IDS := {
	"wizard": "profession.package.wizard.v1",
	"taoist": "profession.package.taoist.v1",
}

static var _index_cache: Dictionary = {}


static func create(profession_name_or_id: String) -> CasterProfessionPackage:
	match ProfessionRules.profession_id(profession_name_or_id):
		"wizard": return WizardProfessionPackage.new()
		"taoist": return TaoistProfessionPackage.new()
	return null


static func integration_descriptors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _index().get("packages", []):
		var profession_id := str(entry.get("profession_id", ""))
		var package := create(profession_id)
		if package == null:
			continue
		var descriptor := entry.duplicate(true)
		descriptor.merge({
			"factory": "CasterProfessionRegistry.create",
			"cast_entry": "CasterProfessionPackage.cast",
			"snapshot_entry": "CasterProfessionPackage.snapshot",
			"integration_contract": str(_index().get("registration_contract", "")),
		}, true)
		result.append(descriptor)
	return result


static func _index() -> Dictionary:
	if not _index_cache.is_empty():
		return _index_cache
	var file := FileAccess.open(INDEX_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_index_cache = parsed if parsed is Dictionary else {}
	return _index_cache
