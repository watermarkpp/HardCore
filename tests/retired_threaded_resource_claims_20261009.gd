extends Node

const CLAIM_PATH := "res://scripts/features/runtime/feature_resource_preparation.gd"
const MISSING_PATH := "res://scripts/features/runtime/__retired_claim_missing__.gd"

func _ready() -> void:
	_run.call_deferred()

func _handoff_owner_claim(path: String) -> void:
	assert(ContentLayers.retire_threaded_resource_claims(path, 1), "scene owner exit transferred its accepted claim")

func _run() -> void:
	var before: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	var first_error := ResourceLoader.load_threaded_request(CLAIM_PATH, "Script", false)
	var second_error := ResourceLoader.load_threaded_request(CLAIM_PATH, "Script", false)
	assert(first_error == OK and second_error == OK, "same path accepted two engine user claims")
	var scene_owner := Node.new()
	scene_owner.tree_exiting.connect(_handoff_owner_claim.bind(CLAIM_PATH))
	add_child(scene_owner)
	scene_owner.queue_free()
	await get_tree().process_frame
	var max_get_delta := 0
	var observed_get := int(before.get("get", 0))
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var snapshot: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
		var current_get := int(snapshot.get("get", 0))
		max_get_delta = maxi(max_get_delta, current_get - observed_get)
		observed_get = current_get
		if current_get >= int(before.get("get", 0)) + 1:
			break
	var adopted: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	assert(int(adopted.get("accepted", 0)) >= int(before.get("accepted", 0)) + 1, "accepted handoff was recorded")
	assert(int(adopted.get("transferred", 0)) >= int(before.get("transferred", 0)) + 1, "transferred handoff was recorded")
	assert(int(adopted.get("get", 0)) == int(before.get("get", 0)) + 1, "one terminal claim was joined")
	assert(max_get_delta <= 1, "a retirement quantum joined more than one claim")
	var status := ResourceLoader.load_threaded_get_status(CLAIM_PATH)
	assert(status == ResourceLoader.THREAD_LOAD_LOADED, "the second owner claim remains available")
	var retained: Resource = ResourceLoader.load_threaded_get(CLAIM_PATH)
	assert(retained != null, "the other owner retained its claim")

	# A separate pair has no foreign owner. Both accepted claims are transferred
	# and must be joined over two service quanta, never in one burst.
	var pair_before: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	var pair_first_error := ResourceLoader.load_threaded_request(CLAIM_PATH, "Script", false)
	var pair_second_error := ResourceLoader.load_threaded_request(CLAIM_PATH, "Script", false)
	assert(pair_first_error == OK and pair_second_error == OK, "second same-path pair was accepted")
	assert(ContentLayers.retire_threaded_resource_claims(CLAIM_PATH, 2), "two accepted claims transferred")
	var pair_start_get := int(pair_before.get("get", 0))
	var pair_last_get := pair_start_get
	var pair_max_delta := 0
	deadline = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var pair_snapshot: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
		var pair_get := int(pair_snapshot.get("get", 0))
		pair_max_delta = maxi(pair_max_delta, pair_get - pair_last_get)
		pair_last_get = pair_get
		if pair_get >= pair_start_get + 2:
			break
	var pair_after: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	assert(int(pair_after.get("transferred", 0)) >= int(pair_before.get("transferred", 0)) + 2, "both claims were transferred")
	assert(int(pair_after.get("get", 0)) == pair_start_get + 2, "both transferred claims were eventually joined")
	assert(pair_max_delta <= 1, "two transferred claims were not split across quanta")

	var invalid_before: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	assert(ContentLayers.retire_threaded_resource_claims(MISSING_PATH, 1), "invalid handoff is accepted for diagnostics")
	deadline = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if int(ContentLayers.threaded_resource_claim_diagnostics().get("missing", 0)) > int(invalid_before.get("missing", 0)):
			break
	var invalid_after: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	assert(int(invalid_after.get("missing", 0)) == int(invalid_before.get("missing", 0)) + 1, "INVALID claim is recorded as missing")
	assert(int(invalid_after.get("get", 0)) == int(invalid_before.get("get", 0)), "INVALID claim never calls get")
	assert(int(invalid_after.get("pending", 0)) == 0, "terminal handoffs leave no pending claims")

	print("RETIRED_THREADED_RESOURCE_CLAIMS_PASS: transferred claim bounded, second owner retained, INVALID recorded")
	get_tree().quit(0)
