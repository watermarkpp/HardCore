extends RefCounted
## Identity is numeric, independent of Dictionary insertion/serialization order.
static func key(identity: Dictionary) -> String:
	if identity.size()!=4: return ""
	for field: String in ["bridge_generation","journal_generation","event_ordinal","transfer_sequence"]:
		if not identity.get(field) is int or identity[field]<=0: return ""
	return "%d:%d:%d:%d" % [identity.bridge_generation,identity.journal_generation,identity.event_ordinal,identity.transfer_sequence]
