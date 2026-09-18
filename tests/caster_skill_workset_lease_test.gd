extends Node

## perf-smoothness-r1 Phase C failing-first regressions (audit 20260918):
## caster skill visual workset lease + loading deadline + combat sync-decode
## ban.
##
## T1  Pinned workset lease: fire-wall / first-cast frames pinned during the
##     loading window must survive LRU eviction pressure; over-budget pin
##     requests are rejected instead of pinning without bound.
## T2  Combat sync-decode ban: with the loading window closed, a cache miss
##     must NOT synchronously load/decode a texture; it is queued for async
##     warm-up and the frame is skipped. Inside the loading window the sync
##     path stays available.
## T3  Pending warm-up queue drains with a limit and clears.
## T4  Workset selection: bounded skill count, fire wall always participates
##     last (hottest LRU entries), duplicates collapse.

const Registry := preload(
	"res://scripts/caster_skill_visual_registry.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_t1_pin_lease_survives_eviction()
	_t2_combat_bans_sync_decode()
	_t3_pending_queue_drains()
	_t4_workset_selection_bounded()
	_cleanup()
	print("CASTER_WORKSET_LEASE_PASS pin/combatgate/queue/workset")
	get_tree().quit(0)


func _t1_pin_lease_survives_eviction() -> void:
	Registry.clear_frame_texture_cache()
	var pinned_path := _fire_wall_frame_paths()[0]
	assert(
		Registry.load_texture_path(pinned_path) != null,
		"fire wall frame must load inside the loading window"
	)
	var pin_result: Dictionary = Registry.pin_frame_paths([pinned_path])
	assert(int(pin_result.get("pinned", 0)) == 1, "pin must accept the frame")
	# Eviction pressure: fill the LRU far past its byte budget with churn
	# textures that are never used again.
	var churn := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var churn_texture := ImageTexture.create_from_image(churn)
	for index: int in range(64):
		Registry.retain_loaded_texture(
			"ch://%d" % index,
			churn_texture,
			256 * 256 * 4
		)
	assert(
		Registry.animation_residency("wizard.fire_wall").get(
			"resident_frames", 0
		) > 0,
		"pinned fire wall frame was evicted by churn"
	)
	# Over-budget pin requests are rejected, not silently unbounded. The
	# budget is exactly one oversized frame: the second frame must be rejected.
	Registry.clear_frame_texture_cache()
	Registry.unpin_all_frames()
	var oversize := Image.create(2048, 2048, false, Image.FORMAT_RGBA8)
	var oversize_texture := ImageTexture.create_from_image(oversize)
	var rejected: Dictionary = Registry.pin_frame_paths(
		["ch://oversize_a", "ch://oversize_b"],
		2048 * 2048 * 4,
		2048 * 2048 * 4
	)
	assert(
		int(rejected.get("pinned", -1)) == 1
		and int(rejected.get("rejected", -1)) == 1,
		"pin budget must reject frames beyond the lease budget"
	)
	Registry.unpin_all_frames()


func _t2_combat_bans_sync_decode() -> void:
	Registry.clear_frame_texture_cache()
	var frame_path := _fire_wall_frame_paths()[0]
	# Loading window (default): the sync path must work.
	Registry.set_loading_window_active(true)
	assert(
		Registry.request_animation_frame_texture(frame_path) != null,
		"loading window must keep the synchronous path"
	)
	Registry.clear_frame_texture_cache()
	var loads_before: int = Registry.frame_texture_cache_diagnostics().get(
		"loads", -1
	)
	var sync_before: int = Registry.frame_texture_cache_diagnostics().get(
		"sync_decode_calls", -1
	)
	# Combat: the window is closed; a miss must not synchronously load/decode.
	Registry.set_loading_window_active(false)
	assert(
		Registry.request_animation_frame_texture(frame_path) == null,
		"combat frame request must not synchronously load a miss"
	)
	var diag: Dictionary = Registry.frame_texture_cache_diagnostics()
	assert(
		int(diag.get("loads", 0)) == loads_before,
		"combat miss must not trigger a synchronous load"
	)
	assert(
		int(diag.get("sync_decode_calls", 0)) == sync_before,
		"combat miss must not trigger a synchronous decode"
	)
	assert(
		Registry.pending_warm_path_count() == 1,
		"combat miss must be queued for async warm-up"
	)
	# Back inside the loading window the sync path works again.
	Registry.set_loading_window_active(true)
	assert(
		Registry.request_animation_frame_texture(frame_path) != null,
		"loading window must restore the synchronous path"
	)
	Registry.set_loading_window_active(false)


func _t3_pending_queue_drains() -> void:
	Registry.clear_frame_texture_cache()
	Registry.clear_pending_warm_paths()
	Registry.set_loading_window_active(false)
	for path: String in _fire_wall_frame_paths():
		Registry.request_animation_frame_texture(path)
	assert(
		Registry.pending_warm_path_count() == _fire_wall_frame_paths().size(),
		"every combat miss must be queued"
	)
	var first_batch: Array[String] = Registry.take_pending_warm_paths(2)
	assert(first_batch.size() == 2, "limited take must respect the limit")
	var remaining: Array[String] = Registry.take_pending_warm_paths(16)
	assert(
		first_batch.size() + remaining.size()
			== _fire_wall_frame_paths().size(),
		"queue must drain exactly once"
	)
	assert(Registry.pending_warm_path_count() == 0)
	Registry.clear_pending_warm_paths()
	Registry.set_loading_window_active(true)


func _t4_workset_selection_bounded() -> void:
	# Real catalog ids only (ProfessionRules.skill_id filters unknown names).
	var learned: Array = [
		"wizard.ice_storm", "taoist.poison", "wizard.fire_wall",
		"wizard.ice_storm",
	]
	var workset: Array[String] = Registry.workset_skill_order(learned, 2)
	assert(
		workset.size() == 3,
		"workset must keep the bounded budget plus the fire wall slot"
	)
	assert(
		str(workset[workset.size() - 1]) == "wizard.fire_wall",
		"fire wall must be the hottest (last) workset entry"
	)
	var seen: Dictionary = {}
	for skill_id: String in workset:
		assert(not seen.has(skill_id), "workset must not duplicate skills")
		seen[skill_id] = true
	var without_fw: Array[String] = Registry.workset_skill_order(
		["wizard.ice_storm", "taoist.poison"], 3
	)
	assert(
		without_fw.size() == 2 and not without_fw.has("wizard.fire_wall"),
		"unlearned fire wall must not be injected"
	)


func _fire_wall_frame_paths() -> Array[String]:
	var residency: Dictionary = Registry.animation_residency(
		"wizard.fire_wall"
	)
	assert(bool(residency.get("ready", false)), "fire wall manifest not ready")
	var paths: Array[String] = []
	var animation: Dictionary = Registry.animation_profile(
		"wizard.fire_wall", ""
	)
	for sequence: Variant in animation.get("sequences", []):
		if not sequence is Dictionary:
			continue
		for frame: Variant in sequence.get("frames", []):
			if not frame is Dictionary:
				continue
			var path := "res://%s" % str(frame.get("path", ""))
			if path != "res://" and not paths.has(path):
				paths.append(path)
	assert(paths.size() > 0, "fire wall manifest has no frames")
	return paths


func _cleanup() -> void:
	Registry.clear_frame_texture_cache()
	Registry.unpin_all_frames()
	Registry.clear_pending_warm_paths()
	Registry.set_loading_window_active(true)
