extends Node

const AudioService := preload("res://scripts/audio_runtime_service.gd")
const RootScript := preload("res://scripts/game_root.gd")
const EntityRegistry := preload("res://scripts/identity/entity_registry.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.active_profile_id = "audio_canonical_consumable_test"
	PlayerState.reset_progress(false)
	var service := AudioService.new()
	add_child(service)
	var game := RootScript.new()
	game._audio_runtime_service = service
	PlayerState.item_audio_committed.connect(game._on_item_audio_committed)
	var starts: Array[Dictionary] = []
	service.event_started.connect(func(event: Dictionary): starts.append(event))
	var checked := 0
	var aliases := 0
	for record: Dictionary in EntityRegistry.document().records:
		if record.kind != "service_item" or not record.has("canonical_id"):
			continue
		var canonical_record: Dictionary = EntityRegistry.resolve(record.canonical_id, "item")
		var canonical_key := "item:%d" % int(canonical_record.legacy_id)
		var service_key := "service:%d" % int(record.legacy_id)
		assert(service._item_event_routes.has(canonical_key), "every registered canonical alias requires an explicit route, even when silent")
		assert(service._item_event_routes[canonical_key].events == service._item_event_routes[service_key].events,
			"canonical aliases must preserve exactly the audited service sound/silence policy")
		aliases += 1
		var item := GameData.get_entity_record(record.canonical_id)
		if item.get("kind") != "consumable" or item.get("category") != "药品" \
			or item.get("useEffect") not in ["delayed_restore", "restore_both"]:
			continue
		service.stop_all_events()
		starts.clear()
		PlayerState.inventory = [{"item_id": int(item.itemId), "count": 1}]
		PlayerState.quick_item_slots = [record.canonical_id, "", "", ""]
		var result := PlayerState.use_quick_item_slot(0, record.canonical_id)
		assert(result.ok and PlayerState.item_count_by_entity_id(record.canonical_id) == 0,
			"canonical potion must be consumed once: %s" % record.canonical_id)
		assert(starts.size() == 1 and starts[0].event_id == "item.use.drug.success",
			"successful canonical potion must reach actual audio player once: %s, %s" % [record.canonical_id, service.state_snapshot().last_event])
		assert(starts[0].context.stable_item_key == "item:%d" % int(item.itemId))
		checked += 1
	assert(checked >= 5, "must cover registered ordinary potion identities")
	assert(aliases == 49, "cover the entire currently registered canonical alias set")
	starts.clear()
	assert(not PlayerState.use_quick_item_slot(0).ok and starts.is_empty(), "failed use must stay silent")
	assert(service.metrics_snapshot().stream_cache_misses == 0, "consumption must never load audio synchronously")
	PlayerState.item_audio_committed.disconnect(game._on_item_audio_committed)
	game.free()
	service.queue_free()
	print("AUDIO_CANONICAL_CONSUMABLE_PASS identities=%d aliases=%d" % [checked, aliases])
	get_tree().quit(0)
