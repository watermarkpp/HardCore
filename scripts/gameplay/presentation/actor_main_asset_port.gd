extends RefCounted

## This facade has no loader/cache authority. Every resident Resource is
## obtained from the actual existing Main vault with an exact owner pin.
var _vault: RefCounted
var _loading: RefCounted
var _owner: Dictionary
var _scope: Dictionary
var _fault: Dictionary = {}
var _retire_started := false

func configure_main(actual_vault: RefCounted, actual_loading: RefCounted, owner: Dictionary, scope: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _vault != null or actual_vault == null or actual_loading == null: return false
	for method: String in ["lookup_original_actor_renderer_asset","inspect_original_actor_renderer_pin","texture_for_renderer","audio_for_renderer","begin_original_actor_renderer_retirement","poll_original_actor_renderer_retirement"]:
		if not actual_vault.has_method(method): return false
	if not actual_loading.has_method("verify_actual_original_loading_scope"): return false
	if actual_loading.verify_actual_original_loading_scope(scope).get("success") != true and (not actual_vault.has_method("verify_accepted_original_actor_template_lease") or not actual_vault.verify_accepted_original_actor_template_lease(owner,scope)): return false
	if owner.size() != 4 or owner.get("contract_id") != "hardcore.actor.renderer_owner.v1" or not owner.get("actor_identity") is Dictionary or not owner.get("renderer_registry_id") is int or owner.renderer_registry_id == 0 or owner.get("kind") not in ["player","enemy"]: return false
	var contract: Script = preload("res://scripts/gameplay/presentation/actor_visual_projection_contract.gd")
	if not contract.valid_identity(owner.actor_identity) and not (owner.kind == "player" and contract.valid_premap_player_identity(owner.actor_identity)): return false
	# Inputs are real before construction. The actual materials/fonts and Node
	# relationships are separately certified after the original renderer binds.
	var proof: Dictionary = actual_vault.inspect_original_actor_renderer_pin(owner,{"asset_key":"closure"},scope)
	if proof.get("success") != true or proof.get("phase") not in ["INPUTS_PINNED","INSTANCE_BOUND"] or proof.get("owner_descriptor") != owner or proof.get("loading_scope") != scope: return false
	_vault = actual_vault; _loading = actual_loading; _owner = owner.duplicate(true); _scope = scope.duplicate(true)
	return true

func owner_descriptor() -> Dictionary: return _owner.duplicate(true)
func rehome_actual_original_player_identity(identity: Dictionary, transaction: Dictionary) -> Dictionary:
	if not is_actual_loading_bound() or _owner.get("kind") != "player": return {"success":false,"status":"INVALID"}
	var next: Dictionary = _owner.duplicate(true)
	next.actor_identity = identity.duplicate(true)
	var actual: Dictionary = _vault.prepare_original_player_identity_rehome(_owner,next,_scope,transaction)
	if actual.get("success") != true: return actual
	var before: Dictionary = _owner
	_owner = next
	return {"success":true,"before":before,"after":next,"actual_instance_id":actual.actual_instance_id}
func finish_actual_original_player_identity_rehome(before: Dictionary, view: Node2D) -> bool:
	if not is_actual_loading_bound(): return false
	return _vault.finish_original_player_identity_rehome(before,_owner,_scope,view).get("success") == true
func is_actual_loading_bound() -> bool: return OS.get_thread_caller_id() == OS.get_main_thread_id() and _vault != null and _fault.is_empty() and not _retire_started
func is_faulted() -> bool: return not _fault.is_empty()
func failure() -> Dictionary: return _fault.duplicate(true)
func bind_actual_original_instance(view: Node2D) -> bool:
	if not is_actual_loading_bound() or not _vault.has_method("bind_original_actor_renderer_instance"): return false
	var actual: Dictionary = _vault.bind_original_actor_renderer_instance(_owner,_scope,view)
	return actual.get("success") == true and actual.get("phase") == "INSTANCE_BOUND" and actual.get("owner_descriptor") == _owner and actual.get("loading_scope") == _scope
func _fail(reason: String, key: String) -> void: _fault = {"status":"MISSING","error":reason,"asset_key":key}

func _lookup(key: String, expected_class: String) -> Resource:
	if not is_actual_loading_bound(): _fail("actual_renderer_owner_not_active",key); return null
	var fact: Dictionary = _vault.lookup_original_actor_renderer_asset(_owner,key,_scope)
	if fact.get("success") != true or fact.get("asset_key") != key or fact.get("owner_descriptor") != _owner or fact.get("loading_scope") != _scope or not fact.get("exists") is bool:
		_fail("actual_asset_fact_missing",key); return null
	if not fact.exists:
		# Explicit original absence is an observable fact, never a fallback
		# for a failed/loading/unpinned required resource.
		if fact.get("originally_absent") != true: _fail("asset_absence_not_proven",key)
		return null
	if not fact.get("resource_token") is int or fact.resource_token == 0:
		_fail("actual_resource_token_missing",key); return null
	var proof: Dictionary = _vault.inspect_original_actor_renderer_pin(_owner,fact,_scope)
	if proof.get("success") != true or proof.get("owner_descriptor") != _owner or proof.get("loading_scope") != _scope or proof.get("asset_fact") != fact:
		_fail("actual_resource_pin_missing",key); return null
	var resource: Resource = _vault.texture_for_renderer(fact.resource_token) if expected_class == "Texture2D" else _vault.audio_for_renderer(fact.resource_token)
	if resource == null or not resource.is_class(expected_class) or resource.get_instance_id() != fact.resource_token:
		_fail("actual_vault_resource_identity_mismatch",key); return null
	return resource

func texture_path(path: String) -> Texture2D: return _lookup("path:"+path,"Texture2D") as Texture2D
func texture_path_exists(path: String) -> bool: return texture_path(path) != null
func player_texture(action: String) -> Texture2D: return _lookup("player:"+action,"Texture2D") as Texture2D
func effect_texture(asset: String) -> Texture2D: return _lookup("effect:"+asset,"Texture2D") as Texture2D
func audio(alias: String) -> AudioStream: return _lookup("audio:"+alias,"AudioStream") as AudioStream
func texture_from_token(token: int) -> Texture2D: return _lookup("token:"+str(token),"Texture2D") as Texture2D

func begin_actual_retirement() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _vault == null: return {"status":"INVALID"}
	if _retire_started: return {"status":"PENDING"}
	var actual: Dictionary = _vault.begin_original_actor_renderer_retirement(_owner,_scope)
	if actual.get("status") not in ["PENDING","READY"] or actual.get("owner_descriptor") != _owner: return {"status":"INVALID","error":"actual_vault_retire_admission_missing"}
	_retire_started = true
	return actual

func poll_actual_retirement() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not _retire_started: return {"status":"INVALID"}
	var actual: Dictionary = _vault.poll_original_actor_renderer_retirement(_owner,_scope)
	if actual.get("owner_descriptor") != _owner or actual.get("status") not in ["PENDING","READY"]: return {"status":"INVALID"}
	if actual.status == "READY" and (actual.get("actual_physical_pins_released") != true or actual.get("actual_original_obligations_terminal") != true): return {"status":"INVALID","error":"actual_physical_retirement_proof_missing"}
	return actual
