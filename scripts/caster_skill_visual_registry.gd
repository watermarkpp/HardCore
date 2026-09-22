class_name CasterSkillVisualRegistry
extends RefCounted

const MANIFEST_PATH := "res://assets/data/caster_skill_visuals.json"

const ROLE_PROJECTILE := "projectile"
const ROLE_TARGET_EFFECT := "target_effect"
const ROLE_SELF_EFFECT := "self_effect"
const ROLE_SELF_AREA := "self_area"
const ROLE_AREA_EFFECT := "area_effect"
const ROLE_LINE_EFFECT := "line_effect"
const ROLE_GROUND_EFFECT := "ground_effect"
const ROLE_SUMMON_ACTOR := "summon_actor_visual"

const SCALE_SOURCE_PIXELS := "source_pixels"
const SCALE_FIT_EXTENT := "fit_extent"
const DERIVED_READY := "ready"
const PRIMARY_COMPLETION_GRACE_SECONDS := 0.05

static var _manifest_cache: Dictionary = {}

# ResourceLoader's cache does not retain unreferenced animation frames. Keep
# recently drawn exact textures alive across frame changes and repeated casts.
# Both limits bound this presentation-only ownership; sprites keep their own
# reference when an entry is evicted, so eviction cannot remove a drawn frame.
const TEXTURE_CACHE_BYTES := 32 * 1024 * 1024
const TEXTURE_CACHE_ENTRIES := 512
static var _frame_textures: Dictionary = {}
static var _frame_texture_use: Dictionary = {}
static var _frame_texture_bytes: Dictionary = {}
static var _frame_texture_serial := 0
static var _frame_texture_resident_bytes := 0
static var _frame_texture_loads := 0
static var _frame_texture_hits := 0
## Separated counters (perf-smoothness-r1 Phase A, PERF-08/09 evidence):
## LRU evictions and the synchronous miss path. The Image.load fallback is
## a synchronous decode on the calling thread; its accumulated time is the
## measured "first cast hitch after eviction" cost, not a guess.
static var _frame_texture_evictions := 0
static var _sync_decode_calls := 0
static var _sync_decode_usec := 0

## perf-smoothness-r1 Phase C (audit 20260918): bounded skill workset lease.
## The loading window prewarms a budgeted workset (first-cast skills + fire
## wall) and PINS those frames: a pinned frame is exempt from LRU eviction
## while the pin budget bounds the lease. Outside the loading window
## (combat) a cache miss must never synchronously load/decode on the main
## thread; the path is queued for async warm-up and the frame is skipped.
const WORKSET_PIN_BUDGET_BYTES := 16 * 1024 * 1024
static var _pinned_paths: Dictionary = {}
static var _pinned_bytes := 0
static var _loading_window_active := true
static var _pending_warm_paths: Array[String] = []
## perf-smoothness-r1 C-R1 (PERF-R2 R13): combat-time frame misses. Combat
## miss queues async sequence warm; AnimationPlayer waits without
## logical-frame advancement. The SUCCESS criterion is zero misses on the
## first real cast of every active workset skill.
static var combat_frame_miss_count := 0


## Loading window gate. `true` (default) keeps every pre-existing
## synchronous path; `false` (combat) bans synchronous texture work for
## animation-frame requests.
static func set_loading_window_active(active: bool) -> void:
	_loading_window_active = active


static func is_loading_window_active() -> bool:
	return _loading_window_active


## Combat-safe animation-frame fetch. Loading window: identical to
## load_texture_path(). Combat: cache hit is served, a miss is queued for
## the async warm-up channel and returns null (the animation player skips
## the frame instead of hitching the main thread).
static func request_animation_frame_texture(path: String) -> Texture2D:
	if _loading_window_active:
		return load_texture_path(path)
	if path.is_empty():
		return null
	_frame_texture_serial += 1
	if _frame_textures.has(path):
		_frame_texture_use[path] = _frame_texture_serial
		_frame_texture_hits += 1
		return _frame_textures[path] as Texture2D
	if not _pending_warm_paths.has(path):
		_pending_warm_paths.append(path)
	combat_frame_miss_count += 1
	return null


static func pending_warm_path_count() -> int:
	return _pending_warm_paths.size()


static func take_pending_warm_paths(limit := 4) -> Array[String]:
	var batch: Array[String] = []
	while batch.size() < limit and not _pending_warm_paths.is_empty():
		batch.append(_pending_warm_paths.pop_front())
	return batch


static func clear_pending_warm_paths() -> void:
	_pending_warm_paths.clear()


## Async warm-up completion: the threaded channel hands the loaded texture
## back here so the cache and diagnostics stay the single accounting point.
static func retain_loaded_texture(path: String, texture: Texture2D, forced_bytes := -1) -> void:
	if texture == null or path.is_empty():
		return
	_retain_frame_texture(path, texture, forced_bytes)


## Pin the given frame paths as the first-cast workset lease. Pins beyond
## the byte budget are REJECTED (bounded lease, audit: no unbounded pin).
static func pin_frame_paths(
	paths: Array[String],
	budget_bytes := WORKSET_PIN_BUDGET_BYTES,
	forced_per_frame_bytes := -1
) -> Dictionary:
	var pinned := 0
	var rejected := 0
	for path: String in paths:
		if path.is_empty() or _pinned_paths.has(path):
			continue
		var bytes := forced_per_frame_bytes
		if bytes < 0:
			var texture := _frame_textures.get(path) as Texture2D
			if texture == null:
				rejected += 1
				continue
			bytes = ceili(
				float(texture.get_width() * texture.get_height() * 4)
					* 4.0 / 3.0
			)
		if _pinned_bytes + bytes > budget_bytes:
			rejected += 1
			continue
		_pinned_paths[path] = bytes
		_pinned_bytes += bytes
		pinned += 1
	return {"pinned": pinned, "rejected": rejected}


static func unpin_all_frames() -> void:
	_pinned_paths.clear()
	_pinned_bytes = 0


## Pin the resident frames of the given workset skills (bounded by the pin
## budget). Loading-window-only: called right after prewarm while frames
## are guaranteed resident. perf-smoothness-r1 C-R1 (PERF-R2 R11): the lease
## granularity is the WHOLE SKILL - every manifest frame of a skill is
## pinned together or the skill is rejected as a whole; a half-pinned skill
## would silently break first-cast completeness while looking like a pin.
## R14-C6: `direction_index >= 0` pins ONLY the selected direction's
## sequence (runtime workset); `direction_index < 0` preserves the legacy
## whole-skill enumeration (test/manual callers).
## Result: {accepted_skills, rejected_skills, pinned_paths, pinned_bytes}.
static func pin_skill_workset(
	skill_ids: Array[String],
	direction_index := -1
) -> Dictionary:
	var accepted_skills: Array[String] = []
	var rejected_skills: Array[String] = []
	var pinned_paths := 0
	var pinned_bytes := 0
	for skill_id: String in skill_ids:
		if skill_id.is_empty() or not is_runtime_ready(skill_id):
			continue
		var paths: Array[String] = (
			animation_sequence_paths(skill_id, direction_index)
			if direction_index >= 0
			else animation_frame_paths(skill_id)
		)
		if paths.is_empty():
			continue
		var frame_bytes: Dictionary = {}
		var all_resident := true
		for path: String in paths:
			var texture := _frame_textures.get(path) as Texture2D
			if texture == null:
				all_resident = false
				break
			frame_bytes[path] = ceili(
				float(texture.get_width() * texture.get_height() * 4)
					* 4.0 / 3.0
			)
		# Atomic granularity: only the NOT-YET-PINNED paths of this skill
		# count against the remaining lease budget.
		var new_bytes := 0
		if all_resident:
			for path: String in paths:
				if not _pinned_paths.has(path):
					new_bytes += int(frame_bytes[path])
		if not all_resident or _pinned_bytes + new_bytes > WORKSET_PIN_BUDGET_BYTES:
			rejected_skills.append(skill_id)
			continue
		for path: String in paths:
			if not _pinned_paths.has(path):
				_pinned_paths[path] = int(frame_bytes[path])
				_pinned_bytes += int(frame_bytes[path])
				pinned_paths += 1
				pinned_bytes += int(frame_bytes[path])
		accepted_skills.append(skill_id)
	return {
		"accepted_skills": accepted_skills,
		"rejected_skills": rejected_skills,
		"pinned_paths": pinned_paths,
		"pinned_bytes": pinned_bytes,
	}


static func pinned_frame_count() -> int:
	return _pinned_paths.size()


## Budgeted workset selection (perf-smoothness-r1 C-R1, PERF-R2 R7): the
## order comes from the player's ACTUAL bound attack slots / attack ring
## (real usage priority), NOT the learned-skills Dictionary whose key order
## is historical. The result is STRICTLY at most `max_skills` entries - no
## hidden extra slot, no unconditional fire-wall injection. A warrior or
## taoist without fire wall bound never pays for fire-wall prewarm.
static func workset_skill_order(
	priority_candidates: Array,
	max_skills := 7
) -> Array[String]:
	var ordered: Array[String] = []
	var seen: Dictionary = {}
	if max_skills <= 0:
		return ordered
	for raw_skill: Variant in priority_candidates:
		var skill_id := ProfessionRules.skill_id(str(raw_skill))
		if skill_id.is_empty() or seen.has(skill_id):
			continue
		seen[skill_id] = true
		ordered.append(skill_id)
		if ordered.size() >= max_skills:
			break
	return ordered


## R14-C2: active-sequence refcount lease. A leased path is exempt from LRU
## eviction while at least one player holds its sequence; the shared refcount
## lets many instances of the same sequence share one lease.
static var _sequence_lease_refcounts: Dictionary = {}


## R14-C2: acquire a refcounted lease over the given sequence paths. Safe to
## call repeatedly for the same sequence from multiple players.
## R14-C-R1 P0-4: returns true ONLY when paths is non-empty AND every path is
## resident. A missing path never receives a phantom lease refcount, so a
## waiter that has not acquired cannot accidentally protect (or later
## release) another owner's frames.
static func acquire_sequence_lease(paths: Array[String]) -> bool:
	if paths.is_empty():
		return false
	for path: String in paths:
		if path.is_empty() or not _frame_textures.has(path):
			return false
	for path: String in paths:
		_sequence_lease_refcounts[path] = (
			int(_sequence_lease_refcounts.get(path, 0)) + 1
		)
	return true


## R14-C2: release one refcount on each path. The path leaves the lease only
## when the last holder releases it.
static func release_sequence_lease(paths: Array[String]) -> void:
	for path: String in paths:
		if path.is_empty() or not _sequence_lease_refcounts.has(path):
			continue
		var remaining := int(_sequence_lease_refcounts[path]) - 1
		if remaining <= 0:
			_sequence_lease_refcounts.erase(path)
		else:
			_sequence_lease_refcounts[path] = remaining


## R14-C2: read-only residency probe for a sequence's paths. Loads nothing.
static func sequence_resident(paths: Array[String]) -> bool:
	for path: String in paths:
		if path.is_empty():
			continue
		if not _frame_textures.has(path):
			return false
	return true


## R14-C-R2 C-R2-4: combat atomicity probe. A sequence is the atomic playback
## unit in combat: whenever the loading window is closed and ANY frame of the
## sequence is missing, the player must wait for the WHOLE sequence instead of
## showing an already-resident frame 0 early. Same residency authority as
## sequence_resident() - no second residency source. Read-only: loads
## nothing, queues nothing.
static func combat_sequence_requires_wait(paths: Array[String]) -> bool:
	return not _loading_window_active and not sequence_resident(paths)


## R14-C2: queue every non-resident path of the sequence for async warm-up
## (combat-safe channel; never loads synchronously).
static func queue_sequence_warm(paths: Array[String]) -> void:
	for path: String in paths:
		if path.is_empty() or _frame_textures.has(path):
			continue
		if not _pending_warm_paths.has(path):
			_pending_warm_paths.append(path)


## R14-C1: enumerate the frame paths of ONE direction's sequence only.
## direction_count==1 returns the unique sequence; direction_count>1 returns
## the sequence selected for the given direction index (same selection rule
## as CasterSkillAnimationPlayer.configure). Read-only: loads nothing.
static func animation_sequence_paths(
	skill_name_or_id: String,
	direction_index: int,
	phase_id := ""
) -> Array[String]:
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
	var result: Array[String] = []
	if skill_id.is_empty() or not is_runtime_ready(skill_id):
		return result
	var animation := animation_profile(skill_id, phase_id)
	if str(animation.get("contract", "")) != "caster_skill_animation.v1":
		return result
	var sequences: Array = animation.get("sequences", [])
	if sequences.is_empty():
		return result
	var selected: Dictionary
	if int(animation.get("direction_count", 1)) <= 1:
		selected = sequences[0]
	else:
		selected = sequences[
			sequence_index(posmod(direction_index, 16), sequences)
		]
	for frame: Variant in selected.get("frames", []):
		if not frame is Dictionary:
			continue
		var path := "res://%s" % str(frame.get("path", ""))
		if path != "res://" and not result.has(path):
			result.append(path)
	return result


## Enumerate every manifest frame path of a skill's animations (default
## phase plus all declared phases). Read-only: loads nothing.
static func animation_frame_paths(
	skill_name_or_id: String
) -> Array[String]:
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
	var result: Array[String] = []
	if skill_id.is_empty() or not is_runtime_ready(skill_id):
		return result
	var phase_ids: Array[String] = [""]
	for phase_id: String in profile(skill_id).get("animation_phases", {}):
		phase_ids.append(phase_id)
	for resolved_phase: String in phase_ids:
		var animation := animation_profile(skill_id, resolved_phase)
		if str(animation.get("contract", "")) != "caster_skill_animation.v1":
			continue
		for sequence: Variant in animation.get("sequences", []):
			if not sequence is Dictionary:
				continue
			for frame: Variant in sequence.get("frames", []):
				if not frame is Dictionary:
					continue
				var path := "res://%s" % str(frame.get("path", ""))
				if path != "res://" and not result.has(path):
					result.append(path)
	return result


static func frame_texture_is_resident(path: String) -> bool:
	return _frame_textures.has(path)


static func profile(skill_name_or_id: String) -> Dictionary:
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
	if skill_id.is_empty():
		return {}
	var coverage: Dictionary = _manifest().get("skillCoverage", {}).get(skill_id, {})
	if coverage.is_empty():
		# Skill not in runtime manifest — fall back to presentation profile
		# for visual_type routing (sky_strike, beam, impact_area).
		var fallback := _cached_visual_profile_entry(skill_id)
		if not fallback.is_empty():
			var result := fallback.duplicate(true)
			result["skill_id"] = skill_id
			result["render"] = _default_render_policy(result)
			return result
		return {}
	var result := coverage.duplicate(true)
	result["skill_id"] = skill_id
	var asset_id := str(result.get("asset_id", ""))
	if not asset_id.is_empty():
		result.merge(_manifest().get("assets", {}).get(asset_id, {}), true)
		result["asset_id"] = asset_id
		result["resource_path"] = "res://%s" % str(result.get("path", ""))
	var render := _default_render_policy(result)
	var declared_render: Variant = result.get("render", {})
	if declared_render is Dictionary:
		render.merge(declared_render, true)
	result["render"] = render
	# Enrich with presentation-layer fields (visual_type, enable_beam_visual)
	# so downstream consumers always have a single source of truth.
	var presentation := _cached_visual_profile_entry(skill_id)
	if not presentation.is_empty():
		for key: String in ["visual_type", "enable_beam_visual", "decoration_alpha"]:
			var value: Variant = presentation.get(key)
			if value != null and not result.has(key):
				result[key] = value
	return result


static func visual_role(skill_name_or_id: String) -> String:
	return str(profile(skill_name_or_id).get("role", ""))


static func render_policy(skill_name_or_id: String, phase_id := "") -> Dictionary:
	var entry := profile(skill_name_or_id)
	if not phase_id.is_empty():
		var phase: Dictionary = entry.get("animation_phases", {}).get(phase_id, {})
		if phase.get("render") is Dictionary:
			var phase_render: Dictionary = entry.get("render", {}).duplicate(true)
			phase_render.merge(phase.render, true)
			return phase_render
	return entry.get("render", {}).duplicate(true)


static func animation_profile(skill_name_or_id: String, phase_id := "") -> Dictionary:
	var entry := profile(skill_name_or_id)
	if phase_id.is_empty():
		return entry.get("animation", {})
	var phases: Dictionary = entry.get("animation_phases", {})
	return phases.get(phase_id, {})


static func is_runtime_ready(skill_name_or_id: String) -> bool:
	var entry := profile(skill_name_or_id)
	return (
		entry.get("status", "") == "formal_primary_client_animation"
		and entry.get("animation", {}).get("contract", "") == "caster_skill_animation.v1"
		and str(entry.get("derived_status", DERIVED_READY)) == DERIVED_READY
	)


static func runtime_readiness_reason(skill_name_or_id: String) -> String:
	var entry := profile(skill_name_or_id)
	if entry.is_empty():
		return "missing_visual_profile"
	if entry.get("status", "") != "formal_primary_client_animation":
		return str(entry.get("reason", "not_formal_primary_client_animation"))
	if entry.get("animation", {}).get("contract", "") != "caster_skill_animation.v1":
		return "missing_animation_contract"
	var status := str(entry.get("derived_status", DERIVED_READY))
	return "" if status == DERIVED_READY else status


static func texture(skill_name_or_id: String) -> Texture2D:
	if not is_runtime_ready(skill_name_or_id):
		return null
	var entry := profile(skill_name_or_id)
	var path := str(entry.get("resource_path", ""))
	return load_texture_path(path)


static func icon_texture(skill_name_or_id: String) -> Texture2D:
	var entry := profile(skill_name_or_id)
	if entry.get("status", "") != "formal_primary_client_animation":
		return null
	var icon: Dictionary = entry.get("icon", {})
	var path := "res://%s" % str(icon.get("path", entry.get("icon_path", "")))
	return load_texture_path(path)


static func load_texture_path(path: String) -> Texture2D:
	if path.is_empty():
		return null
	_frame_texture_serial += 1
	if _frame_textures.has(path):
		_frame_texture_use[path] = _frame_texture_serial
		_frame_texture_hits += 1
		return _frame_textures[path] as Texture2D
	_frame_texture_loads += 1
	if ResourceLoader.exists(path):
		var imported := load(path) as Texture2D
		if imported != null:
			_retain_frame_texture(path, imported)
			return imported
	# Clean worktrees can run the safe headless test runner before Godot has
	# imported newly generated PNGs. Decode the exact source PNG directly so
	# tests and runtime use the same pixels; exports still use normal imports.
	if not FileAccess.file_exists(path):
		return null
	_sync_decode_calls += 1
	var decode_started_usec := Time.get_ticks_usec()
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK or image.is_empty():
		_sync_decode_usec += Time.get_ticks_usec() - decode_started_usec
		return null
	_sync_decode_usec += Time.get_ticks_usec() - decode_started_usec
	var decoded := ImageTexture.create_from_image(image)
	_retain_frame_texture(path, decoded)
	return decoded


## perf-smoothness-r1 C-R1 (PERF-R2 R6): hard-cap retention with duplicate
## accounting protection. Returns true when the texture is resident.
static func _retain_frame_texture(path: String, loaded: Texture2D, forced_bytes := -1) -> bool:
	if loaded == null or path.is_empty():
		return false
	# Late async completion of an already resident path must not
	# double-account the same key: touch and return.
	if _frame_textures.has(path):
		_frame_texture_serial += 1
		_frame_texture_use[path] = _frame_texture_serial
		return true
	# RGBA plus a complete mip chain is a conservative bound for these 2D
	# source/imported textures. Oversized textures still draw without retention.
	var bytes := forced_bytes
	if bytes < 0:
		bytes = ceili(float(loaded.get_width() * loaded.get_height() * 4) * 4.0 / 3.0)
	if bytes > TEXTURE_CACHE_BYTES:
		return false
	while (
		_frame_texture_resident_bytes + bytes > TEXTURE_CACHE_BYTES
		or _frame_textures.size() >= TEXTURE_CACHE_ENTRIES
	):
		var oldest := ""
		var oldest_serial := _frame_texture_serial + 1
		for key: String in _frame_texture_use:
			# Pinned workset lease (perf-smoothness-r1 Phase C): a pinned
			# first-cast frame is exempt from eviction while its budget holds.
			# R14-C2: an active-sequence leased frame is exempt the same way.
			if _pinned_paths.has(key) or _sequence_lease_refcounts.has(key):
				continue
			if int(_frame_texture_use[key]) < oldest_serial:
				oldest = key
				oldest_serial = int(_frame_texture_use[key])
		# Hard cap means hard cap: with no evictable entry the incoming
		# texture is drawn but NOT retained (audit: pinned lease + oversized
		# tail must never push the cache past TEXTURE_CACHE_BYTES).
		if oldest.is_empty():
			return false
		_frame_texture_resident_bytes -= int(_frame_texture_bytes[oldest])
		_frame_textures.erase(oldest)
		_frame_texture_use.erase(oldest)
		_frame_texture_bytes.erase(oldest)
		_frame_texture_evictions += 1
	_frame_textures[path] = loaded
	_frame_texture_use[path] = _frame_texture_serial
	_frame_texture_bytes[path] = bytes
	_frame_texture_resident_bytes += bytes
	return true


static func clear_frame_texture_cache() -> void:
	_frame_textures.clear()
	_frame_texture_use.clear()
	_frame_texture_bytes.clear()
	_frame_texture_resident_bytes = 0
	_frame_texture_serial = 0
	_frame_texture_loads = 0
	_frame_texture_hits = 0
	_frame_texture_evictions = 0
	_sync_decode_calls = 0
	_sync_decode_usec = 0
	_sequence_lease_refcounts.clear()


static func frame_texture_cache_diagnostics() -> Dictionary:
	return {
		"entries": _frame_textures.size(),
		"resident_bytes": _frame_texture_resident_bytes,
		"loads": _frame_texture_loads,
		"hits": _frame_texture_hits,
		"evictions": _frame_texture_evictions,
		"sync_decode_calls": _sync_decode_calls,
		"sync_decode_usec": _sync_decode_usec,
		# perf-smoothness-r1 Phase C workset lease + combat gate accounting.
		"pinned_count": _pinned_paths.size(),
		"pinned_bytes": _pinned_bytes,
		# R14-C2: active-sequence lease accounting. P0-8: unique leased paths
		# plus the sum of every path's refcount (multiple players on the same
		# sequence inflate the total without changing the unique count).
		"leased_sequence_paths": _sequence_lease_refcounts.size(),
		"leased_sequence_refcount_total": _sequence_lease_refcounts.values().reduce(
			func(acc: int, count: Variant) -> int: return acc + int(count),
			0,
		),
		"loading_window_active": _loading_window_active,
		"pending_warm_count": _pending_warm_paths.size(),
		"combat_frame_miss_count": combat_frame_miss_count,
	}


## FW-COLD (GPT audit 2026-09-16): the first real cast of a learned skill
## must not synchronously load animation frames on the main thread. Resolve
## the manifest animation(s) for the skill and load every frame of every
## direction sequence through load_texture_path(), so the first real cast
## is a pure cache hit. Loading-phase work only. With an empty phase_id the
## default animation AND every declared animation phase are prewarmed; with
## an explicit phase_id only that phase is prewarmed.
static func prewarm_animation(
	skill_name_or_id: String,
	phase_id := ""
) -> Dictionary:
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
	if skill_id.is_empty() or not is_runtime_ready(skill_id):
		return {"ready": false, "sequences": 0, "frames": 0}
	var phase_ids: Array[String] = []
	if phase_id.is_empty():
		# The unphased default animation ALWAYS participates: skills without
		# animation_phases (fire wall) declare their frames there.
		phase_ids.append("")
		var phases: Dictionary = profile(skill_id).get(
			"animation_phases", {}
		)
		for key: String in phases:
			phase_ids.append(key)
	else:
		phase_ids.append(phase_id)
	var sequence_count := 0
	var frame_count := 0
	for resolved_phase: String in phase_ids:
		var animation := animation_profile(skill_id, resolved_phase)
		if str(animation.get("contract", "")) != "caster_skill_animation.v1":
			continue
		var sequences: Variant = animation.get("sequences", [])
		if not sequences is Array:
			continue
		for sequence: Variant in sequences:
			if not sequence is Dictionary:
				continue
			var frames: Variant = sequence.get("frames", [])
			if not frames is Array or frames.is_empty():
				continue
			sequence_count += 1
			for frame: Variant in frames:
				if not frame is Dictionary:
					continue
				var path := "res://%s" % str(frame.get("path", ""))
				if path == "res://":
					continue
				if load_texture_path(path) != null:
					frame_count += 1
	return {
		"ready": true,
		"sequences": sequence_count,
		"frames": frame_count,
	}


## FW-COLD2 Phase A (remote review 2026-09-16): read-only residency probe.
## Walks the same manifest structure as prewarm_animation (default animation
## plus every declared phase, every direction sequence, every frame) and
## reports how many of those frame textures are currently resident in the
## LRU cache. Read-only diagnostics: loads nothing, evicts nothing.
static func animation_residency(skill_name_or_id: String) -> Dictionary:
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
	if skill_id.is_empty() or not is_runtime_ready(skill_id):
		return {
			"ready": false,
			"expected_frames": 0,
			"resident_frames": 0,
			"missing_paths": [] as Array[String],
		}
	var phase_ids: Array[String] = [""]
	var phases: Dictionary = profile(skill_id).get(
		"animation_phases", {}
	)
	for key: String in phases:
		phase_ids.append(key)
	var expected := 0
	var resident := 0
	var missing: Array[String] = []
	for resolved_phase: String in phase_ids:
		var animation := animation_profile(skill_id, resolved_phase)
		if str(animation.get("contract", "")) != "caster_skill_animation.v1":
			continue
		var sequences: Variant = animation.get("sequences", [])
		if not sequences is Array:
			continue
		for sequence: Variant in sequences:
			if not sequence is Dictionary:
				continue
			var frames: Variant = sequence.get("frames", [])
			if not frames is Array or frames.is_empty():
				continue
			for frame: Variant in frames:
				if not frame is Dictionary:
					continue
				var path := "res://%s" % str(frame.get("path", ""))
				if path == "res://":
					continue
				expected += 1
				if _frame_textures.has(path):
					resident += 1
				elif not missing.has(path):
					missing.append(path)
	return {
		"ready": true,
		"expected_frames": expected,
		"resident_frames": resident,
		"missing_paths": missing,
	}


static func animation_duration(skill_name_or_id: String, phase_id := "") -> float:
	if not is_runtime_ready(skill_name_or_id):
		return 0.0
	var animation := animation_profile(skill_name_or_id, phase_id)
	return (
		float(animation.get("frame_count", 0))
		* float(animation.get("frame_time_ms", 0))
		/ 1000.0
	)


static func primary_action_completion_seconds(
	skill_name_or_id: String,
	phase_id := ""
) -> float:
	var render := render_policy(skill_name_or_id, phase_id)
	if not bool(render.get("movement_lock_to_primary_visual", false)):
		return 0.0
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
	var animation := animation_profile(skill_id, phase_id)
	if str(render.get("playback_strategy", "frame_sequence")) == "firegun_trail":
		var frame_count := maxi(1, int(animation.get("frame_count", 1)))
		var step_seconds := maxf(
			0.001,
			float(render.get("trajectory_step_ms", 50)) / 1000.0
		)
		var step_distance := maxf(
			0.001,
			float(render.get(
				"trajectory_dominant_axis_pixels_per_second", 500.0 / 0.9
			)) * step_seconds
		)
		var maximum_dominant_distance := maxf(
			step_distance,
			float(render.get("trajectory_max_dominant_axis_pixels", 0.0))
		)
		var emission_count := maxi(
			1,
			ceili(maximum_dominant_distance / step_distance)
		)
		# The first trail sample is emitted immediately. The final sample disappears after
		# advancing through all source frames, so neither cooldown nor recovery
		# time is included in this presentation boundary.
		return float(emission_count + frame_count - 1) * step_seconds
	return animation_duration(skill_id, phase_id) + PRIMARY_COMPLETION_GRACE_SECONDS


static func direction_index(direction: Vector2) -> int:
	if direction.length_squared() <= 0.0:
		return 8
	# Exact port of MirClient/ClFunc.pas GetFlyDirection16. Its four strict
	# slope thresholds are intentionally asymmetric with angle rounding.
	var fx := direction.x
	var fy := direction.y
	if fx == 0.0:
		return 0 if fy < 0.0 else 8
	if fy == 0.0:
		return 12 if fx < 0.0 else 4
	var result := 4 if fx > 0.0 else 12
	var absolute_y := absf(fy)
	var absolute_x := absf(fx)
	if absolute_y > absolute_x / 4.0:
		result = 3 if fy < 0.0 and fx > 0.0 else (
			5 if fy > 0.0 and fx > 0.0 else (
				11 if fy > 0.0 else 13
			)
		)
	if absolute_y > absolute_x / 1.9:
		result = 2 if fy < 0.0 and fx > 0.0 else (
			6 if fy > 0.0 and fx > 0.0 else (
				10 if fy > 0.0 else 14
			)
		)
	if absolute_y > absolute_x * 1.4:
		result = 1 if fy < 0.0 and fx > 0.0 else (
			7 if fy > 0.0 and fx > 0.0 else (
				9 if fy > 0.0 else 15
			)
		)
	if absolute_y > absolute_x * 4.0:
		result = 0 if fy < 0.0 else 8
	return result


static func sequence_index(direction_16: int, sequences_or_count: Variant) -> int:
	var normalized := posmod(direction_16, 16)
	if sequences_or_count is int:
		var count := int(sequences_or_count)
		if count <= 1:
			return 0
		var scaled := float(normalized) * float(count) / 16.0
		return posmod(int(floor(scaled + 0.5)), count)
	if not sequences_or_count is Array or sequences_or_count.is_empty():
		return 0
	var sequences: Array = sequences_or_count
	var best_index := 0
	var best_distance := 17
	var best_clockwise_delta := 17
	for index: int in range(sequences.size()):
		var candidate := posmod(int(sequences[index].get("direction_index", 0)), 16)
		var clockwise_delta := posmod(candidate - normalized, 16)
		var counterclockwise_delta := posmod(normalized - candidate, 16)
		var distance := mini(clockwise_delta, counterclockwise_delta)
		if distance < best_distance or (
			distance == best_distance and clockwise_delta < best_clockwise_delta
		):
			best_index = index
			best_distance = distance
			best_clockwise_delta = clockwise_delta
	return best_index


static func has_formal_visual(skill_name_or_id: String) -> bool:
	return (
		is_runtime_ready(skill_name_or_id)
		and texture(skill_name_or_id) != null
		and icon_texture(skill_name_or_id) != null
	)


static func active_skill_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for skill_id: String in _manifest().get("skillCoverage", {}):
		if _manifest().skillCoverage[skill_id].get("status", "") == "formal_primary_client_animation":
			result.append(skill_id)
	return result


static func runtime_ready_skill_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for skill_id: String in active_skill_ids():
		if is_runtime_ready(skill_id):
			result.append(skill_id)
	return result


static func _default_render_policy(entry: Dictionary) -> Dictionary:
	var role := str(entry.get("role", ""))
	var attachment := "world_anchor"
	match role:
		ROLE_PROJECTILE:
			attachment = "world_projectile"
		ROLE_TARGET_EFFECT:
			attachment = "target_actor"
		ROLE_SELF_EFFECT, ROLE_SELF_AREA, ROLE_LINE_EFFECT:
			attachment = "caster_actor"
		ROLE_SUMMON_ACTOR:
			attachment = "summon_actor"
	var skill_id := str(entry.get("skill_id", ""))
	if skill_id in ["wizard.lightning", "wizard.hellfire", "wizard.teleport"]:
		attachment = "world_anchor"
	return {
		"contract": "caster_skill_render.v2",
		"scale_mode": SCALE_FIT_EXTENT if role == ROLE_PROJECTILE else SCALE_SOURCE_PIXELS,
		"source_scale": 1.0,
		"fit_extent": 34.0 if role == ROLE_PROJECTILE else 0.0,
		"anchor_policy": "top_left_from_world_anchor",
		"attachment_policy": attachment,
		"playback_strategy": "firegun_trail" if skill_id == "wizard.hellfire" else "frame_sequence",
		"pixel_snap": true,
	}


static func _manifest() -> Dictionary:
	if not _manifest_cache.is_empty():
		return _manifest_cache
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_manifest_cache = parsed if parsed is Dictionary else {}
	return _manifest_cache

const VISUAL_PROFILE_PATH := "res://assets/data/skill_visual_profiles.json"
static var _visual_profile_cache: Dictionary = {}


static func visual_type(skill_name_or_id: String) -> String:
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
	if skill_id.is_empty():
		return ""
	return str(_cached_visual_profile_entry(skill_id).get("visual_type", ""))


static func visual_profile(skill_name_or_id: String) -> Dictionary:
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
	if skill_id.is_empty():
		return {}
	var nested: Variant = _cached_visual_profile_entry(skill_id).get("visual_profile", {})
	if nested is Dictionary and not nested.is_empty():
		return (nested as Dictionary).duplicate(true)
	return {}


static func _cached_visual_profile_entry(skill_id: String) -> Dictionary:
	if _visual_profile_cache.has(skill_id):
		return _visual_profile_cache[skill_id]
	if not FileAccess.file_exists(VISUAL_PROFILE_PATH):
		return {}
	var file := FileAccess.open(VISUAL_PROFILE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var raw_text := file.get_as_text()
	file.close()
	var json_parser := JSON.new()
	if json_parser.parse(raw_text) != OK:
		return {}
	var data: Variant = json_parser.get_data()
	if not data is Dictionary:
		return {}
	var profiles: Variant = (data as Dictionary).get("skill_profiles", {})
	if not profiles is Dictionary:
		return {}
	var entry: Variant = (profiles as Dictionary).get(skill_id, {})
	if entry is Dictionary:
		_visual_profile_cache[skill_id] = (entry as Dictionary).duplicate(true)
	return _visual_profile_cache.get(skill_id, {})
