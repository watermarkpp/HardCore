extends RefCounted
## S consumes a genuinely admitted Main tree publication; the verifier is Root's
## actual source-bootstrap provenance service. It cannot be a caller ready flag.
var _owner := OS.get_thread_caller_id()
var _publication: Dictionary = {}
func owner_thread_id() -> int: return _owner
func configure_owner(publication: Dictionary, admission: RefCounted) -> bool:
	if OS.get_thread_caller_id()==OS.get_main_thread_id() or not _publication.is_empty() or admission==null or not admission.has_method("verify_original_source_tree_publication"): return false
	return adopt_original_world_root(publication,admission)
func adopt_original_world_root(publication: Dictionary, admission: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=_owner or OS.get_thread_caller_id()==OS.get_main_thread_id() or admission==null or not admission.has_method("verify_original_source_tree_publication"): return false
	if publication.get("contract_id")!="hardcore.source_tree.root_preorder.v1" or not publication.get("ledger") is Array or not publication.get("world_root_ordinal") is int or publication.world_root_ordinal<0: return false
	if not publication.get("generation") is int or publication.generation<=0: return false
	if not _publication.is_empty():
		if publication.generation<=_publication.generation: return false
		if publication.get("world_context")!=_publication.world_context:
			if not admission.has_method("verify_original_source_tree_root_retired") or not admission.verify_original_source_tree_root_retired(_publication): return false
	if not admission.verify_original_source_tree_publication(publication): return false
	var ledger: Array = publication.ledger
	if publication.world_root_ordinal>=ledger.size() or ledger[publication.world_root_ordinal].get("runtime_id")!=publication.get("world_root_id"): return false
	for index: int in range(ledger.size()):
		if not ledger[index] is Dictionary or ledger[index].get("ordinal")!=index or not ledger[index].get("runtime_id") is int or ledger[index].runtime_id<=0: return false
	_publication=publication.duplicate(true)
	return true
func original_source_tree_root_ordinal(world: Dictionary) -> Dictionary:
	assert(OS.get_thread_caller_id()==_owner)
	if _publication.is_empty() or world!=_publication.world_context: return {"ok":false,"errors":["actual_admitted_world_tree_publication_required"]}
	return {"ok":true,"ordinal":_publication.world_root_ordinal,"publication_generation":_publication.generation,"world_root_id":_publication.world_root_id,"source_tree_root_id":_publication.scene_tree_root_id}
