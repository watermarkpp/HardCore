extends RefCounted

const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
var _catalog: Dictionary = {}
var _bundle: Dictionary = {}
var _authority: Dictionary = {}
var last_errors: Array = []
var catalog_publish_count := 0
var loadout_compile_count := 0

func publish(modules: Array, contributions: Array, authority: Dictionary) -> bool:
	var candidate := Compiler.compile_catalog(modules, authority)
	if not bool(candidate.success):
		last_errors = candidate.errors
		return false
	var loadout := Compiler.compile_loadout(candidate.catalog, contributions, authority)
	if not bool(loadout.success):
		last_errors = loadout.errors
		return false
	var owned_authority := Graph.capture(authority)
	if not bool(owned_authority.success):
		last_errors = owned_authority.errors
		return false
	# Publish only after both catalog closure and active combination succeed.
	_catalog = candidate.catalog
	_bundle = loadout.bundle
	_authority = owned_authority.value
	last_errors = []
	catalog_publish_count += 1
	loadout_compile_count += 1
	return true

func recompile_sources(contributions: Array) -> bool:
	if _catalog.is_empty():
		last_errors = ["catalog_not_published"]
		return false
	var candidate := Compiler.compile_loadout(_catalog, contributions, _authority)
	if not bool(candidate.success):
		last_errors = candidate.errors
		return false
	_bundle = candidate.bundle
	last_errors = []
	loadout_compile_count += 1
	return true

func catalog() -> Dictionary:
	return _catalog

func bundle() -> Dictionary:
	return _bundle

func has_active_contributions() -> bool:
	return not _bundle.is_empty() and not _bundle.sources.is_empty()

func bindings_for(event: String, skill_id: String) -> Array:
	if _bundle.is_empty() or _bundle.event_index.is_empty():
		return []
	return _bundle.event_index.get(Compiler.event_index_key(event, skill_id), [])
