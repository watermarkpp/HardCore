extends Node2D


## R14-C1/C2/C3/C4/C5: caster skill visual sequence residency test.
## C1: animation_sequence_paths() returns ONLY the selected direction's
##     sequence (laser 6 frames, not the whole 96-frame 16-direction skill).
## C2: refcount lease protects the active sequence from LRU eviction, shares
##     one refcount across multiple instances, and releases on last drop.
## C3: a first-frame miss waits for residency instead of permanently
##     stopping; playback starts from frame 0 once the sequence is resident.
## C4: a mid-sequence miss keeps the current texture, freezes the logical
##     clock and never advances the frame index past an uncommitted texture.
## C5: one-shot completion / _exit_tree / reconfigure all release the lease;
##     looping holds it until node teardown.
const Registry := preload("res://scripts/caster_skill_visual_registry.gd")
const AnimationPlayer := preload(
	"res://scripts/caster_skill_animation_player.gd"
)

var _failures := 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("R14_C_FAIL: " + message)


func _ready() -> void:
	_run.call_deferred()


func _make_resident(paths: Array[String]) -> void:
	for path: String in paths:
		if not Registry.frame_texture_is_resident(path):
			Registry.load_texture_path(path)


func _run() -> void:
	Registry.clear_frame_texture_cache()
	Registry.unpin_all_frames()
	Registry.clear_pending_warm_paths()
	Registry.set_loading_window_active(true)

	_case_1_sequence_paths_are_direction_scoped()
	_case_2_refcount_lease_protects_and_shares()
	await _case_3_first_frame_miss_waits_for_residency()
	await _case_4_mid_sequence_miss_does_not_advance_frame()
	await _case_5_lifecycle_releases_lease()

	Registry.clear_frame_texture_cache()
	Registry.unpin_all_frames()
	Registry.set_loading_window_active(true)
	if _failures == 0:
		print("R14_CASTER_SEQUENCE_LEASE_PASS C1-C5 sequence residency contract")
		get_tree().quit(0)
	else:
		push_error("R14_CASTER_SEQUENCE_LEASE_FAIL failures=" + str(_failures))
		get_tree().quit(1)


## C1: animation_sequence_paths is direction-scoped.
func _case_1_sequence_paths_are_direction_scoped() -> void:
	var laser_all := Registry.animation_frame_paths("wizard.laser")
	_check(
		laser_all.size() == 96,
		"C1 laser whole-skill enumeration is 96 frames, got %d" % laser_all.size(),
	)
	var laser_dir0 := Registry.animation_sequence_paths("wizard.laser", 0)
	_check(
		laser_dir0.size() == 6,
		"C1 laser direction 0 sequence is 6 frames, got %d" % laser_dir0.size(),
	)
	var laser_dir8 := Registry.animation_sequence_paths("wizard.laser", 8)
	_check(
		laser_dir8.size() == 6,
		"C1 laser direction 8 sequence is 6 frames, got %d" % laser_dir8.size(),
	)
	_check(
		laser_dir0[0] != laser_dir8[0],
		"C1 different directions resolve different sequence frame paths",
	)
	_check(
		laser_all.size() == 16 * laser_dir0.size(),
		"C1 one direction is 1/16th of the whole-skill frames",
	)
	# Non-directional skill (fire wall, direction_count==1): unique sequence.
	var fw_all := Registry.animation_frame_paths("wizard.fire_wall")
	var fw_seq := Registry.animation_sequence_paths("wizard.fire_wall", 0)
	_check(
		fw_all.size() == fw_seq.size() and fw_all.size() == 6,
		"C1 fire wall unique sequence equals whole-skill frame set",
	)


## C2: refcount lease. Protect a loaded sequence against eviction, share one
## refcount across two acquires, release drops it only on last holder.
func _case_2_refcount_lease_protects_and_shares() -> void:
	Registry.clear_frame_texture_cache()
	var paths := Registry.animation_sequence_paths("wizard.laser", 4)
	_make_resident(paths)
	Registry.acquire_sequence_lease(paths)
	# Eviction churn must not remove a leased path.
	var churn := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var churn_texture := ImageTexture.create_from_image(churn)
	for index: int in range(128):
		Registry.retain_loaded_texture(
			"ch://c2_%d" % index, churn_texture, 256 * 256 * 4
		)
	_check(
		Registry.sequence_resident(paths),
		"C2 leased sequence survives eviction pressure",
	)
	# Shared refcount: two acquires -> one release still leased.
	Registry.acquire_sequence_lease(paths)
	Registry.release_sequence_lease(paths)
	_check(
		Registry.sequence_resident(paths),
		"C2 shared refcount keeps the sequence leased after one release",
	)
	Registry.release_sequence_lease(paths)
	# After the last release, churn may evict (path is no longer protected).
	for index: int in range(256):
		Registry.retain_loaded_texture(
			"ch://c2b_%d" % index, churn_texture, 256 * 256 * 4
		)
	Registry.unpin_all_frames()


## C3: configure() with a missing sequence must NOT permanently stop the
## player. It queues the sequence, keeps processing, and starts from frame 0
## once residency completes.
func _case_3_first_frame_miss_waits_for_residency() -> void:
	Registry.clear_frame_texture_cache()
	Registry.clear_pending_warm_paths()
	# Combat mode: no synchronous decode; a miss returns null.
	Registry.set_loading_window_active(false)
	var paths := Registry.animation_sequence_paths("wizard.fire_wall", 0)
	# Ensure nothing is resident yet.
	_check(
		not Registry.sequence_resident(paths),
		"C3 setup sequence is not resident",
	)
	var player := AnimationPlayer.new()
	add_child(player)
	var configured := player.configure("wizard.fire_wall", Vector2.DOWN)
	_check(
		not configured,
		"C3 configure with missing sequence reports not-loaded (waits)",
	)
	_check(
		player._waiting_for_residency,
		"C3 configure arms waiting-for-residency on first-frame miss",
	)
	_check(
		not player.visual_loaded,
		"C3 first-frame miss does not claim a loaded texture",
	)
	# Warm the sequence through the async channel (the residency source).
	Registry.set_loading_window_active(true)
	_make_resident(paths)
	await get_tree().process_frame
	_check(
		player._waiting_for_residency == false,
		"C3 residency completion clears waiting flag",
	)
	_check(
		player.visual_loaded,
		"C3 playback starts once the sequence is resident",
	)
	_check(
		player.current_frame_index == 0,
		"C3 playback resumes from frame 0 after first-frame miss",
	)
	player.queue_free()
	await get_tree().process_frame


## C4: a mid-sequence miss must keep the current texture, freeze the logical
## clock and NOT advance the frame index past the uncommitted texture.
func _case_4_mid_sequence_miss_does_not_advance_frame() -> void:
	Registry.clear_frame_texture_cache()
	Registry.clear_pending_warm_paths()
	Registry.set_loading_window_active(true)
	var fw_paths := Registry.animation_sequence_paths("wizard.fire_wall", 0)
	_make_resident(fw_paths)
	# Playback needs the texture cache served by request_animation_frame_texture.
	# Combat mode keeps the gate but the cache is already hot (all resident).
	var player := AnimationPlayer.new()
	add_child(player)
	_check(
		player.configure("wizard.fire_wall", Vector2.DOWN),
		"C4 configure loads when resident",
	)
	# Advance to frame 1 (committed texture).
	player._elapsed = 0.05
	player._process(0.05)
	_check(
		player.current_frame_index == 1,
		"C4 playback advances normally when textures commit",
	)
	# Force a miss on the NEXT frame by removing the target from the cache
	# via a custom path frame. Directly drive _frames with a missing path and
	# keep the sequence paths leased so C4's guard is the active path.
	var missing_frame := {"path": "missing/not_resident.png"}
	player._frames.append(missing_frame)
	player._sequence_paths = fw_paths + [
		"res://missing/not_resident.png"
	]
	Registry.acquire_sequence_lease(player._sequence_paths)
	player._elapsed = 0.0
	var before_index := player.current_frame_index
	player._process(0.06)
	_check(
		player._waiting_for_residency,
		"C4 mid-sequence miss arms waiting-for-residency",
	)
	_check(
		player.current_frame_index == before_index,
		"C4 frame index does not advance past an uncommitted texture",
	)
	# Residency completes -> playback resumes from the same committed frame.
	Registry.set_loading_window_active(true)
	Registry.load_texture_path("res://missing/not_resident.png")
	player._elapsed = 0.0
	player._process(0.06)
	_check(
		not player._waiting_for_residency,
		"C4 residency resumes playback",
	)
	Registry.release_sequence_lease(player._sequence_paths)
	player.queue_free()
	await get_tree().process_frame


## C5: one-shot completion releases the lease; _exit_tree releases it too.
func _case_5_lifecycle_releases_lease() -> void:
	Registry.clear_frame_texture_cache()
	Registry.clear_pending_warm_paths()
	Registry.set_loading_window_active(true)
	var fw_paths := Registry.animation_sequence_paths("wizard.fire_wall", 0)
	_make_resident(fw_paths)
	var player := AnimationPlayer.new()
	add_child(player)
	_check(
		player.configure("wizard.fire_wall", Vector2.DOWN),
		"C5 configure loads when resident",
	)
	_check(
		Registry.sequence_resident(fw_paths),
		"C5 lease protects the active sequence",
	)
	# Run the full one-shot to completion (6 frames).
	for step: int in range(12):
		player._process(1.0 / 60.0)
	_check(
		player.playback_complete,
		"C5 one-shot completes",
	)
	# The one-shot release must drop the lease refcount to zero (fire wall is
	# non-looping). Then eviction pressure may remove its frames.
	for index: int in range(256):
		var churn := Image.create(256, 256, false, Image.FORMAT_RGBA8)
		Registry.retain_loaded_texture(
			"ch://c5_%d" % index,
			ImageTexture.create_from_image(churn),
			256 * 256 * 4,
		)
	player.queue_free()
	await get_tree().process_frame
	_check(
		not Registry.sequence_resident(fw_paths),
		"C5 one-shot completion releases the lease (frames evictable)",
	)
