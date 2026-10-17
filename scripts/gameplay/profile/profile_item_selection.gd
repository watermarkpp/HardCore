extends RefCounted
## Immutable UI intent. The existing reliable command owns session admission;
## the actual Model checks the record again after its original save barriers.
## UID-less fungible records are compared by complete value, including count.
const CONTRACT := "hardcore.profile.item_selection.v1"
static func capture(profile_id: String, session_id: int, container: String, slot: Variant, record: Dictionary) -> Dictionary:
	return {"contract_id":CONTRACT,"profile_id":profile_id,"session_id":session_id,"container":container,"slot":slot,"record":record.duplicate(true)}
static func valid(value: Variant) -> bool:
	return value is Dictionary and value.size()==6 and value.get("contract_id")==CONTRACT and value.get("profile_id") is String and value.get("session_id") is int and value.get("container") in ["inventory","warehouse","equipment"] and value.get("record") is Dictionary and (value.get("slot") is int or value.get("slot") is String)
static func matches(profile_id: String, container: String, records: Variant, slot: Variant, selection: Dictionary) -> bool:
	if not valid(selection) or selection.profile_id!=profile_id or selection.container!=container or selection.slot!=slot or selection.record.is_empty(): return false
	var current: Variant = records.get(slot,{}) if records is Dictionary else (records[slot] if slot is int and slot>=0 and slot<records.size() else {})
	if not current is Dictionary or current!=selection.record: return false
	var uid := str(selection.record.get("instance_id",""))
	if uid.is_empty(): return true
	var count := 0
	var values: Array = records.values() if records is Dictionary else records
	for value: Variant in values:
		if value is Dictionary and str(value.get("instance_id",""))==uid: count+=1
	return count==1
