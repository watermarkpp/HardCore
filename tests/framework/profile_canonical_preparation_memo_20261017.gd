extends Node
## Compare every actual package configuration against the retained original
## parser path. This is startup data preparation, not Source/World acceptance.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Original := preload("res://tests/framework/helpers/profile_publication_original_20261017.gd")
const Current := preload("res://scripts/gameplay/profile/profile_publication.gd")
var _proof := Proof.new()
var _failed := 0
func check(ok: bool,label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1; print("CANONICAL_MEMO_FAILED ",label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	print("CANONICAL_MEMO_PHASE original_parser_begin ",Time.get_ticks_usec())
	var stamp: int = Time.get_ticks_usec()
	var before: Dictionary = Original.prepare_canonical()
	var original_usec: int = Time.get_ticks_usec()-stamp
	print("CANONICAL_MEMO_PHASE candidate_begin original_usec=",original_usec)
	stamp = Time.get_ticks_usec()
	var after: Dictionary = Current.prepare_canonical()
	var candidate_usec: int = Time.get_ticks_usec()-stamp
	print("CANONICAL_MEMO_PHASE equivalence_begin candidate_usec=",candidate_usec)
	check(before.get("success") == true and after.get("success") == true,"original and candidate prepare all actual authoring configurations")
	if before.get("success") == true and after.get("success") == true:
		var old: Dictionary = before.publication.expansion_candidates
		var now: Dictionary = after.publication.expansion_candidates
		check(old.keys() == now.keys() and old.size() == (1 << ContentLayers.enabled_expansions.size()),"exhaustive exact Boolean configuration set is retained")
		for key: String in old:
			check(var_to_bytes(old[key]) == var_to_bytes(now[key]),"full merge metadata, diagnostics, all parsed query fields and exact hashes match: "+key)
			if now[key].get("success") == true:
				check(now[key].database_candidate.fields.is_read_only() and now[key].merged_database.is_read_only(),"candidate inputs and query fields remain sealed: "+key)
		var keys: Array = now.keys()
		for index: int in range(1,keys.size()):
			if now[keys[0]].get("success") == true and now[keys[index]].get("success") == true:
				check(not is_same(now[keys[0]].database_candidate.fields,now[keys[index]].database_candidate.fields),"separate configurations keep separate field graphs: "+str(index))
		check(var_to_bytes(before.publication) == var_to_bytes(after.publication),"entire publication is exactly equal including current metadata, modes and features")
	check(candidate_usec < original_usec*0.70,"actual redundant parsing is removed under identical complete load")
	print("CANONICAL_PREPARATION_TIMING ",JSON.stringify({"original_usec":original_usec,"candidate_usec":candidate_usec}))
	var written: bool = _proof.write_receipt("profile_canonical_preparation_memo_20261017",_proof.records.size(),_failed)
	print("PROFILE_CANONICAL_PREPARATION_MEMO_20261017_","PASS" if written and _failed == 0 else "FAIL")
	get_tree().quit(0 if written and _failed == 0 else 1)
