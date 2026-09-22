extends Node

## MFC-4F Final Gate: Formal Respawn Policy Audit.
##
## Scans every Release-Registry implemented_playable map, loads the formal
## runtime through the production Bridge (registry + approval hash + map key
## validation), enumerates runtime.semantics monster_spawn/boss_spawn, resolves
## each spawn through the real MonsterRespawnPolicy, and asserts:
##   - ordinary spawns carry an explicit respawn_policy_id in the frozen set
##   - ordinary resolution is valid, requires_authored_policy == false,
##     random_seconds == 0, duration in {300, 480, 900}
##   - elite/boss resolution stays canonical (1800/3600) with no downgrade
##   - world respawn slot identity is stable (never "runtime:<gen>:<serial>")
##   - formal ordinary slots requiring authored policy == 0
##
## The test deliberately calls production code (Bridge + GameData + Policy) and
## does not re-implement a second RespawnPolicy algorithm.

const Policy := preload("res://scripts/monster_respawn_policy.gd")
const RuntimeBridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const WorldState := preload("res://scripts/world_monster_respawn_state.gd")

const FROZEN_ORDINARY_SECONDS := [300.0, 480.0, 900.0]
const FROZEN_ORDINARY_POLICIES := {
	Policy.BEGINNER_OUTDOOR: true,
	Policy.NORMAL_CAVE: true,
	Policy.SPECIAL_NORMAL: true,
}

var _failures: Array[String] = []


func _ready() -> void:
	_run_audit()
	if _failures.is_empty():
		print("MFC4_FORMAL_AUDIT_PASS formal ordinary slots requiring authored policy = 0")
		get_tree().quit(0)
		return
	push_error("MFC4_FORMAL_AUDIT_FAILED %s" % ";".join(_failures))
	get_tree().quit(1)


func _run_audit() -> void:
	var released_ids := RuntimeBridge.released_map_ids()
	var stats := {
		"playable_maps_scanned": 0,
		"formal_ordinary_groups": 0,
		"formal_ordinary_slots": 0,
		"beginner_outdoor_groups": 0,
		"beginner_outdoor_slots": 0,
		"normal_cave_groups": 0,
		"normal_cave_slots": 0,
		"special_normal_groups": 0,
		"special_normal_slots": 0,
		"canonical_elite_groups": 0,
		"canonical_elite_slots": 0,
		"canonical_boss_groups": 0,
		"canonical_boss_slots": 0,
		"missing_policy_groups": 0,
		"invalid_policy_groups": 0,
		"unstable_respawn_slots": 0,
	}
	for runtime_map_id: int in released_ids:
		# Formal scope gate: only currently-approved implemented_playable maps.
		if not RuntimeBridge.is_formal_playable(runtime_map_id):
			continue
		var runtime := RuntimeBridge.load_map(runtime_map_id)
		if runtime.is_empty():
			_failures.append("runtime_load_failed:%d" % runtime_map_id)
			continue
		var semantics: Dictionary = runtime.get("semantics", {})
		stats["playable_maps_scanned"] = int(stats["playable_maps_scanned"]) + 1
		_audit_spawn_layer(runtime_map_id, semantics.get("monster_spawn", []), "monster", stats)
		_audit_spawn_layer(runtime_map_id, semantics.get("boss_spawn", []), "boss", stats)
		# Bridge data-chain proof: game_content_for_map() must carry the authored
		# respawn_policy_id from runtime.semantics into the top-level spawn dict
		# that GameRoot consumes (no field loss at the editor-runtime boundary).
		_audit_bridge_runtime_content(runtime_map_id, semantics)
	_stats_dump(stats)
	# Final Gate: zero formal ordinary slots may still require authored policy.
	# Every ordinary slot above resolved with requires_authored_policy == false;
	# a non-zero value here means some ordinary slot still resolved through the
	# legacy_seconds_tier_migration path and MFC-4 must NOT close.
	var needing := int(stats.get("ordinary_requires_authored", 0))
	if needing != 0:
		_failures.append("formal_ordinary_slots_requiring_authored_policy=%d" % needing)


func _audit_spawn_layer(
	runtime_map_id: int,
	entries: Array,
	layer_kind: String,
	stats: Dictionary
) -> void:
	for raw: Variant in entries:
		if not raw is Dictionary:
			_failures.append("invalid_spawn_entry:%d:%s" % [runtime_map_id, layer_kind])
			continue
		var entry: Dictionary = raw
		var monster_id := int(entry.get("monster_id", -1))
		var monster := GameData.get_monster_by_id(monster_id)
		if monster.is_empty():
			_failures.append("canonical_monster_missing:%d:%d" % [runtime_map_id, monster_id])
			continue
		var classification := str(monster.get("classification", ""))
		var slot_count := maxi(1, int(entry.get("count", 1)))
		var group_id := str(entry.get("semantic_id", ""))
		# Stable world respawn slot identity: formal slots must never use the
		# runtime:<generation>:<serial> fallback that unstable slots produce.
		var slot_key := WorldState.slot_key(runtime_map_id, group_id)
		if slot_key.is_empty():
			stats["unstable_respawn_slots"] = int(stats["unstable_respawn_slots"]) + slot_count
			_failures.append("unstable_respawn_slot:%d:%s" % [runtime_map_id, group_id])
			continue
		var requested_policy := str(entry.get("respawn_policy_id", ""))
		if classification in ["elite", "boss"]:
			var resolved := Policy.resolve("", classification, float(entry.get("respawn_seconds", -1.0)))
			if not bool(resolved.get("valid", false)):
				_failures.append(
					"canonical_resolve_invalid:%d:%d:%s"
					% [runtime_map_id, monster_id, classification]
				)
				continue
			if classification == "elite":
				stats["canonical_elite_groups"] = int(stats["canonical_elite_groups"]) + 1
				stats["canonical_elite_slots"] = int(stats["canonical_elite_slots"]) + slot_count
				if is_equal_approx(float(resolved.seconds), 1800.0) == false:
					_failures.append("elite_duration_downgraded:%d:%d" % [runtime_map_id, monster_id])
			else:
				stats["canonical_boss_groups"] = int(stats["canonical_boss_groups"]) + 1
				stats["canonical_boss_slots"] = int(stats["canonical_boss_slots"]) + slot_count
				if is_equal_approx(float(resolved.seconds), 3600.0) == false:
					_failures.append("boss_duration_downgraded:%d:%d" % [runtime_map_id, monster_id])
			continue
		# Ordinary path.
		if requested_policy.is_empty():
			stats["missing_policy_groups"] = int(stats["missing_policy_groups"]) + 1
			stats["ordinary_requires_authored"] = int(stats.get("ordinary_requires_authored", 0)) + slot_count
			_failures.append("missing_policy:%d:%s" % [runtime_map_id, group_id])
			continue
		if not FROZEN_ORDINARY_POLICIES.has(requested_policy):
			stats["invalid_policy_groups"] = int(stats["invalid_policy_groups"]) + 1
			_failures.append("invalid_policy:%d:%s:%s" % [runtime_map_id, group_id, requested_policy])
			continue
		var resolved := Policy.resolve(
			requested_policy,
			classification,
			float(entry.get("respawn_seconds", -1.0))
		)
		if not bool(resolved.get("valid", false)):
			stats["invalid_policy_groups"] = int(stats["invalid_policy_groups"]) + 1
			_failures.append("resolve_invalid:%d:%s:%s" % [runtime_map_id, group_id, requested_policy])
			continue
		if bool(resolved.get("requires_authored_policy", true)):
			stats["ordinary_requires_authored"] = int(stats.get("ordinary_requires_authored", 0)) + slot_count
			_failures.append("still_requires_authored:%d:%s" % [runtime_map_id, group_id])
			continue
		if int(resolved.get("random_seconds", -1)) != 0:
			_failures.append("random_seconds_not_retired:%d:%s" % [runtime_map_id, group_id])
		var duration := float(resolved.get("seconds", -1.0))
		if duration not in FROZEN_ORDINARY_SECONDS:
			_failures.append("ordinary_duration_not_frozen:%d:%s:%f" % [runtime_map_id, group_id, duration])
			continue
		if str(resolved.get("policy_id", "")) != requested_policy:
			_failures.append("policy_id_mismatch:%d:%s" % [runtime_map_id, group_id])
			continue
		stats["formal_ordinary_groups"] = int(stats["formal_ordinary_groups"]) + 1
		stats["formal_ordinary_slots"] = int(stats["formal_ordinary_slots"]) + slot_count
		if requested_policy == Policy.BEGINNER_OUTDOOR:
			stats["beginner_outdoor_groups"] = int(stats["beginner_outdoor_groups"]) + 1
			stats["beginner_outdoor_slots"] = int(stats["beginner_outdoor_slots"]) + slot_count
		elif requested_policy == Policy.NORMAL_CAVE:
			stats["normal_cave_groups"] = int(stats["normal_cave_groups"]) + 1
			stats["normal_cave_slots"] = int(stats["normal_cave_slots"]) + slot_count
		elif requested_policy == Policy.SPECIAL_NORMAL:
			stats["special_normal_groups"] = int(stats["special_normal_groups"]) + 1
			stats["special_normal_slots"] = int(stats["special_normal_slots"]) + slot_count


func _stats_dump(stats: Dictionary) -> void:
	print("MFC4_FORMAL_AUDIT playable_maps_scanned = %d" % int(stats.playable_maps_scanned))
	print("MFC4_FORMAL_AUDIT formal_ordinary_groups = %d" % int(stats.formal_ordinary_groups))
	print("MFC4_FORMAL_AUDIT formal_ordinary_slots = %d" % int(stats.formal_ordinary_slots))
	print("MFC4_FORMAL_AUDIT beginner_outdoor_groups = %d" % int(stats.beginner_outdoor_groups))
	print("MFC4_FORMAL_AUDIT beginner_outdoor_slots = %d" % int(stats.beginner_outdoor_slots))
	print("MFC4_FORMAL_AUDIT normal_cave_groups = %d" % int(stats.normal_cave_groups))
	print("MFC4_FORMAL_AUDIT normal_cave_slots = %d" % int(stats.normal_cave_slots))
	print("MFC4_FORMAL_AUDIT special_normal_groups = %d" % int(stats.special_normal_groups))
	print("MFC4_FORMAL_AUDIT special_normal_slots = %d" % int(stats.special_normal_slots))
	print("MFC4_FORMAL_AUDIT canonical_elite_groups = %d" % int(stats.canonical_elite_groups))
	print("MFC4_FORMAL_AUDIT canonical_elite_slots = %d" % int(stats.canonical_elite_slots))
	print("MFC4_FORMAL_AUDIT canonical_boss_groups = %d" % int(stats.canonical_boss_groups))
	print("MFC4_FORMAL_AUDIT canonical_boss_slots = %d" % int(stats.canonical_boss_slots))
	print("MFC4_FORMAL_AUDIT missing_policy_groups = %d" % int(stats.missing_policy_groups))
	print("MFC4_FORMAL_AUDIT invalid_policy_groups = %d" % int(stats.invalid_policy_groups))
	print("MFC4_FORMAL_AUDIT unstable_respawn_slots = %d" % int(stats.unstable_respawn_slots))
	print("MFC4_FORMAL_AUDIT ordinary_requires_authored = %d" % int(stats.get("ordinary_requires_authored", 0)))
	print("MFC4_FORMAL_AUDIT formal ordinary slots requiring authored policy = %d" % int(stats.get("ordinary_requires_authored", 0)))


## Bridge data-chain gate: MapEditorRuntimeBridge.game_content_for_map() is the
## editor-runtime boundary consumed by GameRoot._spawn_editor_runtime_content().
## Every ordinary runtime.semantics entry must arrive as a top-level spawn dict
## carrying respawn_policy_id (the MFC-4F Bridge fix). Boss entries may keep an
## empty policy (canonical classification owns boss/elite timing).
func _audit_bridge_runtime_content(runtime_map_id: int, semantics: Dictionary) -> void:
	var content := RuntimeBridge.game_content_for_map(runtime_map_id)
	var runtime_ordinary := {}
	for raw: Variant in semantics.get("monster_spawn", []):
		if raw is Dictionary:
			var entry: Dictionary = raw
			runtime_ordinary[str(entry.get("semantic_id", ""))] = str(
				entry.get("respawn_policy_id", "")
			)
	var mapped := {}
	for raw: Variant in content.get("spawns", []):
		if raw is Dictionary:
			var entry: Dictionary = raw
			var group: Variant = entry.get("spawn_group", {})
			var sid := str(
				(group as Dictionary).get("semantic_id", "")
				if group is Dictionary
				else entry.get("semantic_id", "")
			)
			mapped[sid] = str(entry.get("respawn_policy_id", ""))
	for sid: String in runtime_ordinary:
		if not mapped.has(sid):
			_failures.append("bridge_semantic_missing:%d:%s" % [runtime_map_id, sid])
			continue
		if mapped[sid] != runtime_ordinary[sid]:
			_failures.append(
				"bridge_policy_lost:%d:%s expected=%s got=%s"
				% [runtime_map_id, sid, runtime_ordinary[sid], mapped[sid]]
			)
