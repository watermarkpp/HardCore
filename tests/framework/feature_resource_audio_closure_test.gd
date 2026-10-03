extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Registry := preload("res://scripts/features/compilation/feature_resource_registry.gd")
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const PACKAGE := "res://assets/data/features/validation/resource_audio_registry.json"
const AUDIO := "res://assets/audio/sfx/client/137__M26-3.wav"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.recalculate_stats(false)
	var old := ContentLayers.feature_configuration()
	var old_bundle := PlayerState.feature_bundle()
	var old_accuracy: int = PlayerState.computed_stats.accuracy
	var icon: String = GameData.get_item_art_path("hc.item.910007", "inventoryIcon")
	check(ResourceLoader.exists(AUDIO, "AudioStream") and not ResourceLoader.has_cached(AUDIO), "existing exact primary fire-sword sound starts as a real uncached engine resource")
	var declared := Registry.declarations()
	check(declared.success and declared.records.has(AUDIO), "exact audited audio identity enters the same trusted resource registry")
	check(not ContentLayers.reload_feature_catalog(PACKAGE), "nonempty audio and icon dependencies cannot publish synchronously without readiness")
	check(is_same(old.catalog, ContentLayers.feature_configuration().catalog) and is_same(old_bundle, PlayerState.feature_bundle()), "unprepared multi-type closure preserves the old player configuration")
	var ready: bool = await ContentLayers.reload_feature_catalog_async(PACKAGE)
	check(ready, "formal async publication prepares parent audio and required child icon as one closure")
	if ready:
		var configuration := ContentLayers.feature_configuration()
		var lease: RefCounted = configuration.resource_lease
		var sound: Resource = lease.resource_at(AUDIO)
		var texture: Resource = lease.resource_at(icon)
		check(sound is AudioStream and sound.resource_path == AUDIO and sound.get_length() > 0, "readiness owns a typed playable stream at the exact declared path")
		check(texture is Texture2D and texture.resource_path == icon and texture.get_width() > 0, "required child owns its real primary texture in the same lease")
		check(configuration.enabled_modules.size() == 2 and int(PlayerState.computed_stats.accuracy) == old_accuracy + 3, "both required modules and real contributions promote atomically")
		var plan := Lease.requirements(configuration.catalog, configuration.enabled_modules)
		check(plan.success and plan.paths.size() == 2 and lease.valid_for(configuration.catalog, configuration.enabled_modules), "dependency closure includes both unique resource types with exact catalog identity")
		var wrong := {AUDIO:texture,icon:texture}
		check(Lease.issue(plan, wrong, ContentLayers._feature_resource_service, {}) == null, "a usable texture cannot substitute for a declared audio stream")
		check(not Lease.requirements(configuration.catalog, ["hc.resource_audio_parent"]).success, "preparation cannot silently omit the parent's required child")
		check(not ContentLayers.set_feature_module_enabled("hc.resource_audio_child", false), "live dependency contract forbids withdrawing a still-required child")
		check(ContentLayers.set_feature_module_enabled("hc.resource_audio_parent", false), "withdrawal retains only the remaining legitimate icon closure")
		var subset: RefCounted = ContentLayers.feature_configuration().resource_lease
		check(subset != null and subset.resource_at(AUDIO) == null and is_same(subset.resource_at(icon), texture), "remaining module neither retains removed audio nor reloads the shared texture")
		check(sound is AudioStream and lease.resource_at(AUDIO) == sound, "old lawful lease still owns audio after future source withdrawal")
		check(Budget.snapshot().open_scopes == 0, "audio preparation and publication leave no shared budget scope across await")
	check(ContentLayers.reload_feature_catalog(), "ordinary empty baseline remains usable after mixed typed resource preparation")
	if not proof.write_receipt("feature_resource_audio_closure_test", checks, failures.size()): failures.append("receipt")
	print("FEATURE_RESOURCE_AUDIO_CLOSURE_%s checks=%d errors=%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(ContentLayers.feature_load_errors),str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
