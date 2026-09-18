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
	_t5_cache_hard_cap_and_duplicate_accounting()
	_t6_atomic_skill_pin()
	_t7_catch_up_commits_final_frame_only()
	_cleanup()
	print("CASTER_WORKSET_LEASE_PASS pin/combatgate/queue/workset/hardcap/atomic/parity")
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
	# C-R1 (PERF-R2 R7): STRICT bound - the result is at most max_skills, no
	# hidden extra fire-wall slot. Priority order is preserved from candidates.
	var candidates: Array = [
		"wizard.ice_storm", "taoist.poison", "wizard.fire_wall",
		"wizard.ice_storm",
	]
	var workset: Array[String] = Registry.workset_skill_order(candidates, 2)
	assert(
		workset.size() == 2,
		"workset must be STRICTLY at most max_skills entries"
	)
	assert(
		str(workset[0]) == "wizard.ice_storm"
		and str(workset[1]) == "taoist.poison",
		"workset must preserve candidate priority order"
	)
	var seen: Dictionary = {}
	for skill_id: String in workset:
		assert(not seen.has(skill_id), "workset must not duplicate skills")
		seen[skill_id] = true
	# Fire wall participates only when actually bound as a candidate.
	var with_fw: Array[String] = Registry.workset_skill_order(candidates, 3)
	assert(
		with_fw.size() == 3 and str(with_fw[2]) == "wizard.fire_wall",
		"bound fire wall must enter the workset in candidate order"
	)
	var without_fw: Array[String] = Registry.workset_skill_order(
		["wizard.ice_storm", "taoist.poison"], 3
	)
	assert(
		without_fw.size() == 2 and not without_fw.has("wizard.fire_wall"),
		"unbound fire wall must never be injected"
	)
	assert(
		Registry.workset_skill_order(candidates, 0).is_empty(),
		"non-positive budget must yield an empty workset"
	)


## C-R1 (PERF-R2 R6): hard cap + duplicate accounting.
func _t5_cache_hard_cap_and_duplicate_accounting() -> void:
	Registry.clear_frame_texture_cache()
	Registry.unpin_all_frames()
	# Pin half the cache, then push a texture that fits no evictable space:
	# resident_bytes must NEVER exceed TEXTURE_CACHE_BYTES.
	var half := Registry.TEXTURE_CACHE_BYTES / 2
	var big := Image.create(2048, 2048, false, Image.FORMAT_RGBA8)
	var big_texture := ImageTexture.create_from_image(big)
	var big_bytes := 2048 * 2048 * 4
	Registry.retain_loaded_texture("ch://cap_a", big_texture, big_bytes)
	Registry.retain_loaded_texture("ch://cap_b", big_texture, big_bytes)
	Registry.pin_frame_paths(["ch://cap_a"], half + big_bytes, big_bytes)
	var pinned_bytes_before: int = Registry.frame_texture_cache_diagnostics().get(
		"pinned_bytes", -1
	)
	assert(pinned_bytes_before == big_bytes)
	# Incoming texture needs big_bytes; only cap_b is evictable. After that,
	# another big texture cannot fit: it must be rejected, not break the cap.
	Registry.retain_loaded_texture("ch://cap_c", big_texture, big_bytes)
	Registry.retain_loaded_texture("ch://cap_d", big_texture, big_bytes)
	var diag: Dictionary = Registry.frame_texture_cache_diagnostics()
	assert(
		int(diag.get("resident_bytes", 0)) <= Registry.TEXTURE_CACHE_BYTES,
		"resident_bytes must never exceed the hard cap"
	)
	assert(
		int(diag.get("resident_bytes", 0))
			== pinned_bytes_before + big_bytes,
		"cap_c must evict cap_b; cap_d must be rejected by the hard cap"
	)
	# Same-path late async completion must not double-account.
	var before_bytes: int = diag.get("resident_bytes", 0)
	Registry.retain_loaded_texture("ch://cap_a", big_texture, big_bytes)
	var after: Dictionary = Registry.frame_texture_cache_diagnostics()
	assert(
		int(after.get("resident_bytes", 0)) == before_bytes,
		"re-retaining an already resident path must not double-account bytes"
	)
	Registry.unpin_all_frames()


## C-R1 (PERF-R2 R11): atomic per-skill pin - a skill is pinned as a whole
## or rejected as a whole, and the report names accepted/rejected skills.
func _t6_atomic_skill_pin() -> void:
	Registry.clear_frame_texture_cache()
	Registry.unpin_all_frames()
	var fw_paths := _fire_wall_frame_paths()
	# Prewarm all fire-wall frames so they are resident and pin-eligible.
	for path: String in fw_paths:
		assert(Registry.load_texture_path(path) != null)
	var pin_result: Dictionary = Registry.pin_skill_workset(
		["wizard.fire_wall"]
	)
	assert(
		(pin_result.get("accepted_skills", []) as Array).has("wizard.fire_wall"),
		"fully resident skill must be accepted atomically"
	)
	assert(
		int(pin_result.get("pinned_paths", -1)) == fw_paths.size(),
		"accepted skill must pin EVERY manifest frame, not a subset"
	)
	# Eviction pressure must not remove any pinned frame.
	var churn := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var churn_texture := ImageTexture.create_from_image(churn)
	for index: int in range(64):
		Registry.retain_loaded_texture(
			"ch://atomic_%d" % index, churn_texture, 256 * 256 * 4
		)
	assert(
		Registry.animation_residency("wizard.fire_wall").get(
			"resident_frames", 0
		) == fw_paths.size(),
		"atomic pin must keep the whole skill resident"
	)
	Registry.unpin_all_frames()


## C-R1 (PERF-R2 R19 / Phase D first item): catch-up commits ONLY the final
## frame; index parity with small-delta playback; identical completion.
func _t7_catch_up_commits_final_frame_only() -> void:
	# Combat mode: no synchronous decode on these synthetic paths; the frame
	# index/complete logic under test stays isolated from texture loading.
	Registry.set_loading_window_active(false)
	var Player := preload("res://scripts/caster_skill_animation_player.gd")
	var frame_time := 0.05
	var frame_count := 5
	# Once (non-loop): many small steps vs one big catch-up step. Signal
	# counts are captured through an array (GDScript lambdas capture scalars
	# by value, arrays by reference).
	var log_a: Array[String] = []
	var player_a := Player.new()
	player_a.visual_loaded = true
	var frames_a: Array[Dictionary] = []
	for index: int in range(frame_count):
		frames_a.append({"path": ""})
	player_a._frames = frames_a
	player_a._frame_time_seconds = frame_time
	player_a._loop = false
	player_a.animation_finished.connect(
		func(_skill: String) -> void: log_a.append(_skill)
	)
	for step: int in range(30):
		player_a._process(1.0 / 60.0)
	assert(
		player_a.current_frame_index == frame_count - 1
		and player_a.playback_complete
		and log_a.size() == 1,
		"small-delta playback must end at the final frame exactly once"
	)
	var log_b: Array[String] = []
	var player_b := Player.new()
	player_b.visual_loaded = true
	var frames_b: Array[Dictionary] = []
	for index: int in range(frame_count):
		frames_b.append({"path": ""})
	player_b._frames = frames_b
	player_b._frame_time_seconds = frame_time
	player_b._loop = false
	player_b.animation_finished.connect(
		func(_skill: String) -> void: log_b.append(_skill)
	)
	player_b._process(0.4)
	assert(
		player_b.current_frame_index == frame_count - 1
		and player_b.playback_complete
		and log_b.size() == 1,
		"large-delta catch-up must land on the same final frame and signal once"
	)
	# Loop: same total elapsed time must land on the same frame index.
	var player_c := Player.new()
	player_c.visual_loaded = true
	var frames_c: Array[Dictionary] = []
	for index: int in range(frame_count):
		frames_c.append({"path": ""})
	player_c._frames = frames_c
	player_c._frame_time_seconds = frame_time
	player_c._loop = true
	for step: int in range(60):
		player_c._process(1.0 / 60.0)
	var player_d := Player.new()
	player_d.visual_loaded = true
	var frames_d: Array[Dictionary] = []
	for index: int in range(frame_count):
		frames_d.append({"path": ""})
	player_d._frames = frames_d
	player_d._frame_time_seconds = frame_time
	player_d._loop = true
	player_d._process(1.0)
	assert(
		player_c.current_frame_index == player_d.current_frame_index,
		"loop catch-up must reach the same frame index as small steps"
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
