extends RefCounted

## Test fixture controls actual HP writes. The observer never knows this mode.
var mode := ""
var source_id := 0
var target_id := 0
var injected := 0
var foreign_writes := 0
var nested := false
var first_release := ""
var facts: Array = []

func write_count(victim: PlayerCharacter, identity: Variant, amount: int) -> int:
	if nested or not identity is Dictionary or int(identity.get("source_instance_id", -1)) != source_id or victim.get_instance_id() != target_id:
		return 1
	if first_release.is_empty():
		first_release = str(identity.release_id)
	var selected := str(identity.release_id) == first_release or mode == "all_damage_lost"
	if not selected:
		return 1
	facts.append({"source": identity.duplicate(true), "amount": amount, "physics_tick": Engine.get_physics_frames(), "mode": mode})
	match mode:
		"lost_damage_substituted", "nested_unknown", "nested_foreign":
			injected += 1
			nested = true
			var other: Variant = null
			if mode != "nested_unknown":
				other = identity.duplicate(true)
				other.source_instance_id = -999
				other.release_id = "foreign:" + str(identity.release_id)
				other.admission_release_id = other.release_id
			# Equal resolved amount and same physics tick at the actual write
			# owner. No damage/RNG roll is truncated or ledger line removed.
			victim._apply_resolved_damage(amount, false, "physical", {}, false, other)
			foreign_writes += 1
			nested = false
			return 0 if mode == "lost_damage_substituted" else 1
		"duplicate_apply":
			injected += 1
			return 2
		"all_damage_lost":
			injected += 1
			return 0
	return 1
