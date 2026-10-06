extends Node
func _ready() -> void: _run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = false
	PlayerState.begin_startup_save_upgrade()
	var startup: bool = PlayerState.finish_startup_save_upgrade()
	print("DIAG3 startup=", startup)
	var registry := "res://assets/data/features/validation/resource_natural_registry.json"
	var ok: bool = await ContentLayers.reload_feature_catalog_async(registry)
	print("DIAG3 reload=", ok, " load_errors=", ContentLayers.feature_load_errors)
	var configuration: Dictionary = ContentLayers.feature_configuration()
	print("DIAG3 lease_null=", configuration.get("resource_lease") == null, " enabled=", configuration.get("enabled_modules", []))
	get_tree().quit(0)
