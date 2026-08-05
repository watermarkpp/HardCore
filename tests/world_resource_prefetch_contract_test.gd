extends Node

func _ready() -> void:
	var coord := WorldBootstrapCoordinator.new()
	coord.begin_initial_world(0)
	coord.collect_map_resources({})

	# Register resources
	coord._register_resource("res://monsters/orc.tscn", "monster_scene", true, "monster_001")
	coord._register_resource("res://monsters/orc.tscn", "monster_scene", true, "monster_002")
	coord._register_resource("res://npc/merchant.tscn", "npc_scene", true, "npc_001")
	coord._register_resource("res://decor/rock.tscn", "decor", false, "decor_001")

	# Verify dedup: orc.tscn registered once with 2 owners, rock is optional
	assert(coord.resource_manifest.size() == 3)
	var orc: Dictionary = coord.resource_manifest["res://monsters/orc.tscn"]
	assert(orc.owners.size() == 2)
	assert(orc.required)

	var rock: Dictionary = coord.resource_manifest["res://decor/rock.tscn"]
	assert(not rock.required)
	assert(rock.kind == "decor")

	# Verify sync load counter
	assert(coord._synchronous_load_during_spawn == 0)
	coord.record_sync_load()
	assert(coord._synchronous_load_during_spawn == 1)

	print("WORLD_RESOURCE_PREFETCH_CONTRACT_TEST_PASS")
	get_tree().quit(0)
