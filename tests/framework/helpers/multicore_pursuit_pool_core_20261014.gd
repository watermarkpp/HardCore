extends RefCounted
const CameraOwner := preload("res://scripts/gameplay/world/world_camera_constraint_owner.gd")
var host: Object
var world: Dictionary
var boot: Dictionary
var planner: RefCounted
var descriptor: Dictionary
var ticket: Dictionary = {}
var case_index := 0
var ticks := 0
var valid := true
var done := false
var camera_valid := false
var camera_checks := 0
var rows_checked := 0
var batches: Array[Dictionary] = []
var _retiring: Dictionary = {}
var _cancel_case := false
var _release_usec := 0

func _init(actual_host: Object, actual_boot: Dictionary) -> void:
	host = actual_host
	boot = actual_boot
	world = boot.world_identity
	var camera := CameraOwner.new()
	camera_valid = camera.configure_original_handoff(boot.camera_publication)
	for row: Dictionary in boot.camera_expected:
		var actual: Vector2 = camera.resolve_strict_follow_cached(row.design, row.half, row.zoom, row.center)
		var guarded: Vector2 = camera.apply_player_visibility_guard(row.design, row.half, row.zoom, row.center, row.extent)
		camera_valid = camera_valid and actual == row.strict and guarded == row.guarded
		camera_checks += 2
	valid = camera_valid
	_configure_planner()

func _configure_planner() -> void:
	planner = ClassDB.instantiate("HardCorePursuitPlanning")
	valid = valid and planner.bind_original_completion_host(host)
	var workers := 1 if case_index < 4 else 3
	valid = valid and planner.configure_owner(40, 40, workers, 32, 2)
	var admission := {"contract_id":"hardcore.pursuit.actual_loading_admission.v1", "source_owner_thread_id":host.owner_thread_id(), "source_static_sha256":boot.predicates.source_sha256}
	# This admits actual numeric fixture data only. It deliberately does not
	# claim the game's Root Loading writer/pin barrier or encounter adoption.
	var publication: Dictionary = planner.publish_static_navigation(boot.navigation, boot.predicates, world, 1, admission)
	valid = valid and publication.get("ok", false)
	descriptor = publication.get("descriptor", {})

func on_inputs(_domain: String, _packets: Array) -> bool: return true

func _input_rows(count: int, path_case: bool) -> Dictionary:
	var actors: Array[Dictionary] = []
	var peers: Array[Dictionary] = []
	for index: int in count:
		var position := Vector2(5 + (index % 8) * 2.0, 5 + floori(float(index) / 8.0) * 2.0)
		var target := Vector2(23.5, 23.5)
		if path_case:
			var angle := TAU * float(index) / float(count)
			position = Vector2(15.5 + 10.0 * cos(angle), 15.5 + 10.0 * sin(angle))
			target = Vector2(15.5, 15.5)
		var failed: Array = []
		if path_case:
			var difference := target - position
			var leg := position + Vector2(clampf(difference.x, -1.0, 1.0), clampf(difference.y, -1.0, 1.0))
			failed.append([Vector2i(floori(position.x), floori(position.y)), Vector2i(floori(leg.x), floori(leg.y))])
		actors.append({"runtime_id":index+1,"life":1,"target_runtime_id":1000,"target_life":1,"radius_revision":1,"stable_combat_order":index+1,
			"position":position,"historical_target":target,"radius":float(boot.radius),"target_radius":float(boot.radius),"margin":0.007,"target_margin":0.007,
			"side_retry_due":true,"navigation_key":boot.radius_key,"source_surround_goal":null,"source_flank_waypoint":null,
			"source_route":PackedVector2Array(),"source_route_index":0,"active_failed_edges":failed})
		peers.append({"runtime_id":index+1,"life":1,"radius_revision":1,"stable_combat_order":index+1,"position":position,"radius":float(boot.radius),"margin":0.007,
			"enemy":true,"damage_eligible":true,"world_collision":true})
	return {"actors":actors,"peers":peers}

func on_phase(phase: String, _frame: Dictionary) -> bool:
	if phase == "H_GROUP":
		ticks += 1
		if ticket.is_empty() and not done:
			var kind := case_index % 4
			var count := 30 if kind % 2 == 0 else 40
			var rows := _input_rows(count, kind >= 2)
			var release := Time.get_ticks_usec()
			_release_usec = release
			var snapshot := {"contract_id":"hardcore.pursuit.planning.snapshot.v1","world_context":world,"static_navigation":descriptor,
				"actors":rows.actors,"peers":rows.peers,"released_usec":release,"sequence":case_index+1}
			var admitted: Dictionary = planner.submit_planning_batch(snapshot, release + 300000)
			valid = valid and admitted.get("accepted", false)
			ticket = admitted.get("ticket", {})
			if _cancel_case: valid = valid and planner.cancel_planning_batch(ticket)
	if phase == "PUBLISH":
		if not ticket.is_empty():
			if _retiring.is_empty():
				var completion: Dictionary = planner.poll_planning_batch(ticket)
				valid = valid and completion.get("ok", false)
				if completion.get("ready", false): _retiring = completion
			if not _retiring.is_empty() and planner.retire_planning_batch(ticket):
				if not _cancel_case:
					var count := 30 if case_index % 2 == 0 else 40
					valid = valid and _retiring.rows.size() == count and _retiring.receipt.required_rows == count
					valid = valid and _retiring.receipt.S_worker_joins == 0 and _retiring.receipt.M_worker_joins == 0
					valid = valid and _retiring.receipt.observed_maximum_active_workers <= (1 if case_index < 4 else 3)
					var ids := {}
					for row: Dictionary in _retiring.rows:
						valid = valid and row.life == 1 and row.runtime_id >= 1 and row.runtime_id <= count and not ids.has(row.runtime_id)
						ids[row.runtime_id] = true
						if case_index % 4 >= 2: valid = valid and row.status == "FOUND" and row.expansions > 0
						rows_checked += 1
					batches.append({"case":case_index,"rows":count,"receipt":_retiring.receipt,"released_usec":_release_usec,"all_ready_usec":_retiring.all_ready_usec,"numeric_wall_usec":int(_retiring.all_ready_usec)-_release_usec,"observed_retirement_usec":Time.get_ticks_usec()})
				valid = valid and not planner.has_pending_planning_batches() and planner.close_owner()
				ticket = {}; _retiring = {}; case_index += 1
				if case_index < 8: _configure_planner()
				elif not _cancel_case:
					_cancel_case = true
					_configure_planner()
				else: done = true
		return host.publish_snapshot({"ticks":ticks,"valid":valid,"done":done,"camera_valid":camera_valid,"camera_checks":camera_checks,"rows_checked":rows_checked,"batches":batches}, [])
	return valid

func close_session() -> bool:
	return done and valid and not planner.has_pending_planning_batches()
