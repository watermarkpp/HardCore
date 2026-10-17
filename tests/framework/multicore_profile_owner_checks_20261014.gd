extends RefCounted

const Factory := preload("res://scripts/gameplay/profile/profile_owner_factory.gd")
const Queries := preload("res://scripts/gameplay/content/content_query_core.gd")
var _fixture: Dictionary
var checks: Array[Dictionary] = []
var done := false
var _thread := OS.get_thread_caller_id()
var _continued := 0
var _started := false
var _mode_seen := false
var _expansion_seen := false
var _database_seen := false
var _before_revision := 0
var _before_layer_revision := 0
var _target_mode := ""
var _target_later := false
var _next_service_sequence := -1

func _check(value: bool, label: String) -> void:
	checks.append({"pass":value,"label":label})

func _init(fixture: Dictionary) -> void:
	_fixture = fixture
	for name: String in ["core","profile","ports","publication","content_snapshot","persistence_budget","player","toggle_mode","toggle_later"]:
		if not fixture.has(name):
			_check(false,"required real S profile fixture:"+name)
			done = true
	if done: return
	_check(_thread != OS.get_main_thread_id(),"ProfileModel/Mode/Expansion/rules/diagnostics instantiated in genuine Host S")
	_check(not Factory.validate_required(null,fixture.publication,fixture.content_snapshot,fixture.persistence_budget).success,
		"missing-domain RED witness refuses configuration before any profile/database write")
	_check(Factory.validate_required(fixture.core,fixture.publication,fixture.content_snapshot,fixture.persistence_budget).success,
		"actual WorldCore services satisfy exact profile owner admission")
	_check(fixture.profile._configured and fixture.profile._runtime_port == fixture.ports.runtime and fixture.profile._feature_port._source == fixture.ports.feature_source,
		"same original ProfileModel uses real owner-local ports and non-Node feature source")
	_check(fixture.profile._rules == fixture.ports.content.rules and fixture.ports.content._source.simulation_owner,
		"unique live content port and ProfileRuleSet own all profile consumers")
	_check(fixture.ports.runtime.profile_is_owned_by_gameplay() and fixture.profile.feature_publication_context().world_active,
		"actual registered S world preserves original old-profile ownership block")
	_check(fixture.profile._json_persistence.owner_context().kind == "simulation" and fixture.profile._world_json_persistence.owner_context().kind == "simulation",
		"both unchanged original persistence coordinators retain S ownership")
	_target_mode = str(fixture.toggle_mode)
	_target_later = bool(fixture.toggle_later)
	_await_original_service()

func _await_original_service() -> void:
	await _fixture.ports.runtime.next_service()
	_continued += 1
	_next_service_sequence = _fixture.ports.runtime._last_service_sequence

func _on_expansion(_id: String, _enabled: bool) -> void:
	_expansion_seen = true
	var profile: RefCounted = _fixture.profile
	_mode_seen = profile.game_mode_id == _target_mode and profile.later_content_enabled == _target_later
	_check(_fixture.ports.content._source.source_revision == _before_revision+1 and _fixture.ports.feature_source.configuration_revision == _before_layer_revision+1,
		"expansion observer runs after original database adopt and layer revision writes")
	_check(_mode_seen,"mode/profile callback commits before expansion observer")

func _on_database() -> void:
	_database_seen = true
	_check(_expansion_seen and _mode_seen,"database reload announcement follows changed-package observers and mode/profile commit")

func after_phase(name: String, _frame: Dictionary, fixture: Dictionary) -> void:
	if done or name != "P_GROUP": return
	_fixture = fixture
	if not _started:
		_started = true
		var ports: Dictionary = fixture.ports
		var mode: RefCounted = ports.modes
		var source: RefCounted = ports.feature_source
		var content: RefCounted = ports.content._source
		_check(_continued == 1,"next_service resumes at the first original P service signal")
		_check(_next_service_sequence == ports.runtime._last_service_sequence,"continuation observes the exact original process-frame sequence")
		_check(not mode.prepare_mode_configuration("unknown.profile.test").success and not mode.prepare_mode_configuration(_target_mode,1).success,
			"original unknown-mode and non-bool-later guards fail closed")
		var invalid_packages := source.enabled_expansions.duplicate()
		invalid_packages["unknown.profile.test"] = true
		_check(source.prepare_expansion_configuration(invalid_packages) == null,"original package-key/size qualification rejects malformed configuration")
		var prepared: Dictionary = mode.prepare_mode_configuration(_target_mode,_target_later)
		_check(prepared.success,"original Main-canonical package/database snapshot prepares the requested mode")
		if not prepared.success:
			done = true
			return
		_check(not prepared.content.database_candidate.is_empty(),"test seed requires actual changed package/database candidate, never no-op mode")
		if prepared.content.database_candidate.is_empty():
			done = true
			return
		var stale: Dictionary = mode.prepare_mode_configuration(_target_mode,_target_later)
		_before_revision = content.source_revision
		_before_layer_revision = source.configuration_revision
		var content_identity := ports.content.get_instance_id()
		var rules_identity := fixture.profile._rules.get_instance_id()
		var hp: int = fixture.player.model.current_hp
		var life: int = fixture.player.model.current_life()
		source.expansion_state_changed.connect(_on_expansion)
		source.database_reloaded.connect(_on_database)
		_check(mode.apply_prepared_mode_configuration(prepared),"S adopts actual original canonical database and mode transaction")
		_check(_database_seen and _expansion_seen,"genuine reload emits the complete original notification chain")
		_check(ports.content.get_instance_id() == content_identity and fixture.profile._rules.get_instance_id() == rules_identity,
			"adopt keeps same content and rules identities for all live actor/profile consumers")
		_check(fixture.player.model.current_hp == hp and fixture.player.model.current_life() == life,
			"mode/database adoption creates no secondary HP/life mutation")
		_check(not mode.apply_prepared_mode_configuration(prepared),"consumed original preparation cannot commit twice")
		_check(not mode.apply_prepared_mode_configuration(stale),"old database/layer revision preparation is refused after actual commit")
		var fields_before: Dictionary = content._state.read_field("_items_by_name").duplicate(true)
		var rejected := {"contract_id":"profile.database.candidate.v1","validated_canonical":true,"fields":{},"fields_sha256":"invalid"}
		_check(not content.adopt_profile_database_candidate(rejected,content.source_revision) and fields_before == content._state.read_field("_items_by_name"),
			"malformed canonical candidate is refused atomically before any field write")
		var diagnostics: RefCounted = ports.diagnostics.numeric_owner()
		_check(diagnostics.performance_detail_enabled(),"test publication enables original full diagnostic counter path")
		diagnostics.reset_performance_window()
		diagnostics.increment_performance_counter(&"respawn_state_updates",2)
		diagnostics.increment_performance_counter(&"profile_dynamic_observer",7)
		diagnostics.record_performance_max(&"death_save_max_ms",4.0)
		var window: Dictionary = diagnostics.read_performance_window({"producer":"actual_profile_s"})
		_check(window.counters.respawn_state_updates == 2 and window.counters.profile_dynamic_observer == 7,
			"shared original numeric algorithm retains stable schema and dynamic counters")
		_check(window.counters.death_save_max_ms == 4.0 and diagnostics._recent_slow_events.size() == 1,
			"original 3ms threshold/max/slow-event ledger remains owned by S")
		_check(window.frame_count == 0,"S counters never fabricate actual M frame statistics")
		_check(source.feature_configuration().resource_lease == ports.features._source._feature_resource_lease,
			"feature source exposes the same canonical resource entitlement and effective directory")
		done = true

func close() -> void:
	if _fixture.has("ports"):
		var source: RefCounted = _fixture.ports.feature_source
		if source.expansion_state_changed.is_connected(_on_expansion): source.expansion_state_changed.disconnect(_on_expansion)
		if source.database_reloaded.is_connected(_on_database): source.database_reloaded.disconnect(_on_database)
	_fixture.clear()
