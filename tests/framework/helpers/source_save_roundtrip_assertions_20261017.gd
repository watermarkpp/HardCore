extends RefCounted
## Pure assertion functions. No Profile owner, writer, admission, or success producer.
static func sha256(bytes: PackedByteArray) -> String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
static func equal(a: Variant,b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		if typeof(a)==typeof(b): return a==b
		var i: int=a if a is int else b
		var f: float=b if b is float else a
		return is_finite(f) and f==float(i) and int(f)==i
	if typeof(a)!=typeof(b): return false
	if a is Dictionary:
		if a.size()!=b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not equal(a[key],b[key]): return false
		return true
	if a is Array:
		if a.size()!=b.size(): return false
		for i: int in a.size():
			if not equal(a[i],b[i]): return false
		return true
	return a==b
static func canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary={};var keys: Array=value.keys();keys.sort()
		for key: Variant in keys: out[key]=canonical(value[key])
		return out
	if value is Array:
		var out: Array=[]
		for item: Variant in value: out.append(canonical(item))
		return out
	if value is float and is_finite(value) and float(int(value))==value: return int(value)
	return value
static func snapshot(fields: Dictionary, document: Dictionary) -> Dictionary:
	var out: Dictionary={}
	for name: String in ["active_profile_id","profession_id","level","experience","gold","learned_skills","inventory","equipment","warehouse_inventory"]:
		if not fields.has(name): return {}
		var v: Variant=fields[name];out[name]=v.duplicate(true) if v is Dictionary or v is Array else v
	if not document.get("skill_progression") is Dictionary: return {}
	out.skill_progression=document.skill_progression.duplicate(true)
	return out
static func progression(snapshot_value: Dictionary) -> Dictionary:
	var out: Dictionary=snapshot_value.duplicate(true)
	for key: String in ["inventory","equipment","warehouse_inventory"]:out.erase(key)
	return out
static func records(snapshot_value: Dictionary) -> Array:
	var result: Array=[]
	for key: String in ["inventory","warehouse_inventory"]:
		for item: Variant in snapshot_value.get(key,[]):
			if item is Dictionary and not item.is_empty():result.append(item)
	for item: Variant in snapshot_value.get("equipment",{}).values():
		if item is Dictionary and not item.is_empty():result.append(item)
	return result
static func ownership(snapshot_value: Dictionary) -> Dictionary:
	var instances: Dictionary={};var attributes: Dictionary={};var quantity:=0;var duplicate:=false;var valid:=true
	for item: Dictionary in records(snapshot_value):
		var count: Variant=item.get("count",1)
		if not (count is float or count is int) or not is_finite(float(count)) or count<1 or int(count)!=count: valid=false;continue
		quantity+=int(count)
		var copy: Dictionary=item.duplicate(true);copy.erase("count")
		var signature: String=JSON.stringify(canonical(copy))
		attributes[signature]=int(attributes.get(signature,0))+int(count)
		var id: String=str(item.get("instance_id",""))
		if not id.is_empty():
			if instances.has(id):duplicate=true
			instances[id]=item.duplicate(true)
	return {"valid":valid,"instances":instances,"has_duplicate_instances":duplicate,"quantity":quantity,"attribute_quantities":attributes}
static func find(bag: Array,instance: String) -> int:
	for index: int in bag.size():
		if bag[index] is Dictionary and bag[index].get("instance_id")==instance:return index
	return -1
static func command_matches(reply: Dictionary,method: String,profile: String,session: int,model: int,after_id: int) -> bool:
	var r: Variant=reply.get("receipt")
	return reply.get("success")==true and r is Dictionary and r.get("contract_id")=="hardcore.profile.ui.command_receipt.v1" and r.get("method")==method and r.get("profile_id")==profile and r.get("post_profile_id")==profile and r.get("owner_session_id")==session and r.get("profile_model_id")==model and r.get("command_id") is int and r.command_id==after_id+1 and r.get("command_sha256") is String and r.command_sha256.length()==64 and r.get("result")==reply.get("result") and r.get("profile_view",{}).get("fields",{}).get("active_profile_id")==profile
static func terminal_matches(publication: Dictionary,terminal: Dictionary,status: Dictionary,host: int,session: int,profile: String,event: Dictionary) -> bool:
	var rng: Dictionary=publication.get("global_random_terminal",{})
	var fields: Dictionary=publication.get("state",{}).get("source_fields",{})
	if publication.get("actual_host_id")!=host or publication.get("owner_session_id")!=session or publication.get("state",{}).get("active_profile_id")!=profile or publication.get("world_context",{}).get("profile_id")!=profile:return false
	if terminal.get("success")!=true or terminal.get("contract_id")!="hardcore.main.application_CHARACTER_SELECT_terminal.v1" or terminal.get("owner_session_id")!=session or terminal.get("actual_Profile_authority_return",{}).get("success")!=true:return false
	for flag: String in ["join_complete","close_quiescent","source_model_close_completed","main_channels_unbound_after_close","original_terminal_gameplay_random_restored"]:
		if status.get(flag)!=true:return false
	if status.get("running")!=false or not str(status.get("fault","")).is_empty() or event.get("journal_event_ordinal",0)<=0 or status.get("original_main_applied_prefix",-1)<event.journal_event_ordinal:return false
	if rng.get("contract_id")!="hardcore.profile.global_random.return.v1" or rng.get("host_object_id")!=host or rng.get("owner_session_id")!=session or rng.get("source_session_object_id")!=publication.get("source_session_object_id") or rng.get("source_runtime_id")!=publication.get("source_runtime_id") or rng.get("event_identity",{}).get("event_ordinal")!=event.journal_event_ordinal:return false
	for key: String in ["source_profile_model_id","source_session_object_id","source_runtime_id"]:
		if not publication.get(key) is int or publication[key]==0:return false
	var retired: Dictionary=terminal.get("actual_Main_channels_retired",{}).get("actual_Native_owner_unbind",{})
	var owners: Dictionary=retired.get("actual_owner_ids",{})
	var keys: Array=owners.keys();keys.sort()
	var required: Array=["admission","claim_feature","claim_origin","live_feature","streaming","caster","closing","map_producer","map_executor"];required.sort()
	if retired.get("success")!=true or retired.get("status")!="UNBOUND_AFTER_CLOSE" or retired.get("host_object_id")!=host or retired.get("bridge_generation")!=publication.get("bridge_generation") or keys!=required or owners.get("claim_feature")!=owners.get("live_feature"):return false
	for value: Variant in owners.values():
		if not value is int or value==0:return false
	for field: String in ["actual_loading_release","actual_Main_Root_exit","actual_old_receiver_retired","actual_startup_producer_retired"]:
		if terminal.get(field,{}).get("success")!=true:return false
	var source_root: Variant=publication.get("intent",{}).get("source_root_id")
	if not source_root is int or source_root==0 or terminal.get("actual_loading_release",{}).get("success")!=true:return false
	if fields.is_empty() or publication.get("state",{}).get("source_witness",{}).get("actual_save_receipt",{}).get("success")!=true:return false
	return true
