extends RefCounted
## Main-only boot values from the existing canonical authorities. This produces
## metadata and exact parser bytes, never texture pins, actor births or READY.
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const Identity := preload("res://scripts/monster_identity.gd")
const MonsterInputs := preload("res://scripts/features/contracts/published_monster_inputs.gd")
const LegacyEnemy := preload("res://scripts/enemy.gd")
const StreamPublisher := preload("res://scripts/gameplay/enemy/enemy_main_resource_primitives.gd")
const VisualPublisher := preload("res://scripts/gameplay/enemy/enemy_main_visual_publication.gd")
const TimingPublisher := preload("res://scripts/gameplay/world/world_skill_timing_publication.gd")
const CasterPublisher := preload("res://scripts/gameplay/world/world_caster_visual_publication.gd")
const TargetRing := preload("res://scripts/gameplay/world/world_owner_target_ring.gd")
static func capture(catalog_lease: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not Gate.is_active(catalog_lease) or not GameData.is_loaded() or not ContentLayers.is_loaded(): return _missing("actual_Main_loaded_catalogue_lease_required")
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(Identity.CATALOG_PATH)
	var document: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if raw.is_empty() or not document is Dictionary or document!=Identity._catalog() or not document.get("entries_by_id") is Dictionary: return _missing("actual_canonical_monster_source_cache_mismatch")
	var inputs: Dictionary = {}
	var ids := PackedInt32Array()
	for key: Variant in document.entries_by_id:
		if not key is String: return _missing("canonical_monster_ID_key_type")
		var id: int = Identity.monster_id({"monster_id":key})
		if id <= 0 or str(id)!=key or inputs.has(id): return _missing("canonical_monster_ID_identity_conflict")
		var entry: Variant = document.entries_by_id[key]
		if not entry is Dictionary or not entry.get("runtime_allowed") is bool: return _missing("canonical_monster_runtime_qualification_missing")
		if not entry.runtime_allowed: continue # Exact existing canonical runtime boundary.
		var actual: RefCounted = MonsterInputs.capture(id,LegacyEnemy._attack_range_policy_record_for_id(id),LegacyEnemy._movement_authority_record_for_id(id))
		if actual==null or not actual.valid_for(id): return _missing("actual_original_monster_input_capture",{"monster_id":id})
		inputs[id] = actual.view()
		ids.append(id)
	if ids.is_empty(): return _missing("actual_runtime_monster_catalogue_empty")
	ids.sort()
	# These existing Main leaves read canonical metadata/exists only. They are
	# not configured as a second physical resource owner and acquire no claims.
	var streaming: Dictionary = StreamPublisher.new().capture_catalog(ids)
	var visual: Dictionary = VisualPublisher.new().capture_catalog(ids)
	if streaming.get("monster_data",{}).size()!=ids.size() or visual.get("appearances",{}).size()!=ids.size(): return _missing("actual_complete_monster_metadata_publishers")
	var timing: Dictionary = TimingPublisher.publish(catalog_lease)
	var caster: Dictionary = CasterPublisher.publish(catalog_lease,timing)
	if timing.is_empty() or caster.is_empty(): return _missing("actual_same_catalogue_timing_and_Caster_metadata")
	var documents: Dictionary = {}
	var document_hashes: Dictionary = {}
	# Exact current Source parser consumer. New parser paths must be explicitly
	# added with their real bytes, rather than enabling filesystem access on S.
	for path: String in [TargetRing.DATA_PATH]:
		if not FileAccess.file_exists(path): return _missing("actual_Source_policy_file_missing",{"path":path})
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if bytes.is_empty(): return _missing("actual_Source_policy_file_empty",{"path":path})
		documents[path] = bytes
		document_hashes[path] = FileAccess.get_sha256(path)
	var publication := {"contract_id":"world.original_content_inputs.v1","monster_inputs":{"contract_id":"world.monster_inputs.publication.v1","inputs":inputs},
		"streaming_catalog":streaming,"visual_catalog":visual,"action_timing":timing,"caster_visual":caster,"source_documents":documents,
		"source_witness":{"canonical_monster_path":Identity.CATALOG_PATH,"canonical_monster_sha256":FileAccess.get_sha256(Identity.CATALOG_PATH),"database_revision":GameData.database_revision,"configuration_revision":ContentLayers.configuration_revision,"source_document_sha256":document_hashes}}
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var copied: Dictionary = graph.capture(publication,true,false)
	return {"success":true,"publication":copied.value} if copied.get("success")==true else _missing("actual_World_content_graph_not_values",copied)
static func _missing(code: String,details: Dictionary={}) -> Dictionary: return {"success":false,"status":"MISSING","error":code,"details":details}
