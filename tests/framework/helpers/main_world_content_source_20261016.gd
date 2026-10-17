extends "res://tests/framework/helpers/premap_context_source_20261015.gd"
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const Identity := preload("res://scripts/gameplay/world/world_owner_monster_identity.gd")
const TargetBound := preload("res://scripts/features/adapters/world_target_bound.gd")
var _lease: Dictionary
var _reading := false
func _init(host: Object,boot: Dictionary) -> void:
	super(host,boot)
	_lease = boot.catalog_lease
	_reading = Gate.enter_reader(_lease)
	_check(_reading and Gate.owns_reader(_lease),"actual Source registers its genuine catalogue reader")
	var publication: Dictionary = boot.content.monster_inputs
	var identity := Identity.new(self,publication)
	var targets := TargetBound.new()
	_check(targets.configure_owner_inputs(publication),"real Source target-bound owner accepts the complete original monster input publication")
	for id: int in publication.inputs:
		var original: Dictionary = publication.inputs[id]
		_check(identity.require_catalog_entry(id) == original.entry and identity.appearance_profile(id) == original.appearance and identity.body_profile(id) == original.body,"real Source identity consumes exact canonical entry/appearance/body for monster %d" % id)
	_check(boot.content.streaming_catalog.monster_data.size() == publication.inputs.size() and boot.content.visual_catalog.appearances.size() == publication.inputs.size(),"actual streaming and visual metadata retain the same complete monster set after Native codec")
func close_session() -> bool:
	if _reading:
		if not Gate.leave_reader(_lease): return false
		_reading = false
	return true
