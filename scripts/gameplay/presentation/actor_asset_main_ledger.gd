extends RefCounted
## A sub-ledger of the existing physical Main vault, not a loader cache or
## scheduler. Texture strong roots live in that vault's original dictionaries.
const Contract := preload("res://scripts/gameplay/presentation/actor_visual_projection_contract.gd")
const PlayerVisual := preload("res://scripts/gameplay/presentation/player_main_visual_projection.gd")
var _vault: WeakRef
var _loading: RefCounted
var _prefix: RefCounted
var _templates: Dictionary = {}
var _owners: Dictionary = {}
var _audio_references: Dictionary = {}
var _aux_references: Dictionary = {}
var _next_template := 0

func configure_main(vault: RefCounted, loading: RefCounted, prefix: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _vault != null or vault == null or vault.get_script().resource_path != "res://scripts/gameplay/enemy/enemy_main_resource_primitives.gd" or vault.get("_configured") != true: return false
	if loading == null or not loading.has_method("verify_actual_original_loading_scope") or prefix == null or prefix.get_script() != preload("res://scripts/gameplay/world/world_main_prefix_consumer.gd"): return false
	_vault = weakref(vault); _loading = loading; _prefix = prefix
	return true

func _main() -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id() and _vault != null and _vault.get_ref() != null
func _error(code: String, status := "INVALID") -> Dictionary: return {"success":false,"status":status,"error":code}
func _owner_key(owner: Dictionary) -> String: return preload("res://scripts/gameplay/source/source_command_digest.gd").sha256(owner)

func prepare_original_player_inputs(profile: RefCounted, world: Dictionary, scope: Dictionary) -> Dictionary:
	if not _main() or _loading.verify_actual_original_loading_scope(scope).get("success") != true or _loading.actual_original_loading_scope(world) != scope: return _error("actual_original_Loading_asset_preparation_required")
	var selected: Dictionary = PlayerVisual.capture_original_asset_recipe(profile)
	if selected.get("success") != true: return selected
	var recipe: Dictionary = selected.recipe
	var key: String = preload("res://scripts/gameplay/source/source_command_digest.gd").sha256({"root_id":world.get("world_runtime_id"),"profile_id":world.get("profile_id"),"recipe":recipe})
	if _templates.has(key): return _template_receipt(key)
	# Stage the exact original results, then root the successful batch once.
	# A failed/import-pending item is never recorded as an original absence.
	var facts: Dictionary = {}
	var textures: Dictionary = {}
	var audio: Dictionary = {}
	for path: String in recipe.appearance_paths:
		var loaded: Dictionary = load_original_player_appearance_path(path)
		if not _stage_asset("path:"+path,loaded,"Texture2D",facts,textures): return _error("original_appearance_load_failed:"+path,"MISSING")
	for family: String in ["player","effect","audio"]:
		var aliases: Array = recipe[{"player":"player_aliases","effect":"effect_aliases","audio":"audio_aliases"}[family]]
		for alias: String in aliases:
			var resource: Resource
			if family == "player": resource = PresentationAssets.player_texture(alias)
			elif family == "effect": resource = PresentationAssets.effect_texture(alias)
			else: resource = PresentationAssets.audio(alias)
			var observed: Dictionary = PresentationAssets.inspect_original_cached_resource(("effects" if family == "effect" else family)+"/"+alias)
			var loaded := {"status":observed.get("status","MISSING"),"resource":resource,"origin":"original_PresentationAssets","observation":observed}
			if not _stage_asset(family+":"+alias,loaded,"AudioStream" if family == "audio" else "Texture2D",facts,audio if family == "audio" else textures): return _error("original_alias_load_failed:"+family+":"+alias,"MISSING")
	var shader: Shader = preload("res://assets/shaders/trial_magic_screen.gdshader")
	if shader == null or facts.is_empty(): return _error("actual_nonempty_shader_and_asset_input_closure_required","MISSING")
	var vault: RefCounted = _vault.get_ref()
	var references: Dictionary = vault.get("_texture_references")
	for token: int in textures: references[token] = textures[token]
	var tokens: Array = textures.keys()
	var root_key := "actor_template:"+key
	# Preserve the existing one vault's release/unrooted rules and global roots.
	if not tokens.is_empty() and not vault._replace_roots(root_key,tokens): return _error("actual_template_texture_roots_rejected")
	for token: int in audio: _audio_references[token] = audio[token]
	_aux_references[root_key] = [shader]
	_next_template += 1
	_templates[key] = {"id":_next_template,"world":world.duplicate(true),"scope":scope.duplicate(true),"recipe":recipe,
		"facts":facts,"texture_tokens":tokens,"audio_tokens":audio.keys(),"root_key":root_key,"shader":shader,
		"database_revision":GameData.database_revision,"configuration_revision":ContentLayers.configuration_revision}
	return _template_receipt(key)

func _stage_asset(key: String, loaded: Dictionary, expected: String, facts: Dictionary, references: Dictionary) -> bool:
	if loaded.get("status") == "ABSENT":
		facts[key] = {"asset_key":key,"exists":false,"originally_absent":true,"observation":loaded.duplicate(true)}
		return true
	var resource: Variant = loaded.get("resource")
	if loaded.get("status") != "LOADED" or not resource is Resource or not resource.is_class(expected): return false
	var token: int = resource.get_instance_id()
	references[token] = resource
	var observation: Dictionary = loaded.duplicate(false)
	observation.erase("resource")
	facts[key] = {"asset_key":key,"exists":true,"resource_token":token,"observation":observation}
	return true

func _template_receipt(key: String) -> Dictionary:
	var row: Dictionary = _templates[key]
	return {"success":true,"status":"READY","phase":"INPUTS_PINNED","template_key":key,"template_id":row.id,
		"world_context":row.world,"loading_scope":row.scope,"fact_count":row.facts.size(),"texture_count":row.texture_tokens.size(),"audio_count":row.audio_tokens.size(),"actual_shader_id":row.shader.get_instance_id()}

func inspect_actual_original_input_template(receipt: Dictionary) -> Dictionary:
	if not _main() or not receipt.get("template_key") is String or not _templates.has(receipt.template_key) or _template_receipt(receipt.template_key) != receipt: return _error("actual_same_input_template_required")
	var row: Dictionary = _templates[receipt.template_key]
	if row.database_revision != GameData.database_revision or row.configuration_revision != ContentLayers.configuration_revision or _loading.verify_actual_original_loading_scope(row.scope).get("success") != true: return _error("actual_input_template_source_changed")
	var vault: RefCounted = _vault.get_ref()
	if vault.get("_texture_roots").get(row.root_key,[]) != row.texture_tokens or _aux_references.get(row.root_key,[]) != [row.shader]: return _error("actual_input_template_roots_changed")
	for token: int in row.texture_tokens:
		var resource: Texture2D = vault.texture_for_renderer(token)
		if resource == null or resource.get_instance_id() != token: return _error("actual_input_template_texture_missing")
	for token: int in row.audio_tokens:
		if not _audio_references.get(token) is AudioStream or _audio_references[token].get_instance_id() != token: return _error("actual_input_template_audio_missing")
	return {"success":true,"status":"READY","actual_template":receipt,"actual_ledger_id":get_instance_id(),"actual_vault_id":vault.get_instance_id(),"actual_Main_process_frame":Engine.get_process_frames()}

func bind_original_actor_inputs(owner: Dictionary, template_key: String, scope: Dictionary) -> Dictionary:
	if not _main() or owner.size() != 4 or owner.get("contract_id") != "hardcore.actor.renderer_owner.v1" or owner.get("kind") != "player" or not owner.get("actor_identity") is Dictionary or not owner.get("renderer_registry_id") is int or owner.renderer_registry_id == 0: return _error("actual_actor_renderer_owner_required")
	if not Contract.valid_identity(owner.actor_identity) and not Contract.valid_premap_player_identity(owner.actor_identity): return _error("actual_Player_display_identity_required")
	if not _templates.has(template_key): return _error("actual_prepared_actor_template_required","MISSING")
	var template: Dictionary = _templates[template_key]
	var world: Dictionary = owner.actor_identity.world
	if template.scope != scope or template.world.world_runtime_id != world.world_runtime_id or template.world.profile_id != world.profile_id or template.database_revision != GameData.database_revision or template.configuration_revision != ContentLayers.configuration_revision: return _error("actual_template_owner_scope_or_revision_mismatch")
	var event: Dictionary = _prefix.actual_current_original_event()
	var publication: Variant = event.payload.get("visual_projection") if event.get("payload") is Dictionary else null
	if event.get("operation") == &"actor_visual_projection" and event.get("arguments") is Array and event.arguments.size() == 1: publication = event.arguments[0]
	if not publication is Dictionary or publication.get("identity") != owner.actor_identity or publication.get("kind") != owner.kind or not Contract.validate_presentation(publication): return _error("actual_current_Native_actor_publication_required")
	var display: RefCounted = preload("res://scripts/gameplay/presentation/actor_main_visual_shell.gd").ProfileDisplay.new(publication.profile)
	var actual_recipe: Dictionary = PlayerVisual.capture_original_asset_recipe(display)
	if actual_recipe.get("success") != true or actual_recipe.recipe != template.recipe: return _error("actual_Source_equipment_recipe_does_not_match_pinned_inputs","MISSING")
	var registry: Object = instance_from_id(owner.renderer_registry_id)
	if registry == null or registry.get_script().resource_path != "res://scripts/gameplay/presentation/main_actor_visual_registry.gd" or registry.get("_header_prefix_consumer") == null or registry.get("_header_prefix_consumer").get_ref() != _prefix: return _error("actual_same_Native_renderer_registry_required")
	var key := _owner_key(owner)
	if _owners.has(key):
		if _owners[key].template != template_key: return _error("actual_owner_recipe_transition_required","MISSING")
		return inspect_original_actor_renderer_pin(owner,{"asset_key":"closure"},scope)
	var root_key := "actor_owner:"+key
	var vault: RefCounted = _vault.get_ref()
	if not template.texture_tokens.is_empty() and not vault._replace_roots(root_key,template.texture_tokens): return _error("actual_actor_texture_roots_rejected")
	_owners[key] = {"owner":owner.duplicate(true),"scope":scope.duplicate(true),"template":template_key,"root_key":root_key,"retiring":false,"instance":null,"instance_bound":false,"accepted_ordinal":event.ordinal}
	_aux_references[root_key] = [template.shader]
	return inspect_original_actor_renderer_pin(owner,{"asset_key":"closure"},scope)

func verify_accepted_original_actor_template_lease(owner: Dictionary, scope: Dictionary) -> bool:
	return inspect_original_actor_renderer_pin(owner,{"asset_key":"closure"},scope).get("success") == true

func prepare_original_player_identity_rehome(before: Dictionary, after: Dictionary, scope: Dictionary, transaction: Dictionary) -> Dictionary:
	if not _main() or before.get("kind") != "player" or after.size() != 4 or after.get("contract_id") != before.get("contract_id") or after.get("kind") != "player" or after.get("renderer_registry_id") != before.get("renderer_registry_id") or (not Contract.valid_identity(after.get("actor_identity",{})) and not Contract.valid_premap_player_identity(after.get("actor_identity",{}))): return _error("actual_same_player_rehome_owner_required")
	var old: Dictionary = _owners.get(_owner_key(before),{})
	if old.is_empty() or old.owner != before or old.scope != scope or old.retiring or not old.instance_bound or old.instance == null or not is_instance_valid(old.instance.get_ref()): return _error("actual_bound_player_instance_required")
	var event: Dictionary = _prefix.actual_current_original_event()
	if event.get("operation") == &"source_map_arrival":
		if event.get("arguments") != [transaction] or transaction.get("contract_id") != "hardcore.source.map_arrival.v2" or not _prefix.get("_host").verify_committed_original_map_arrival(transaction): return _error("actual_Native_map_arrival_rehome_required")
		if before.actor_identity.world != transaction.get("before_world") or after.actor_identity != transaction.get("player_identity") or after.actor_identity.world != transaction.get("after_world") or before.actor_identity.runtime_id != transaction.get("player_runtime_id") or after.actor_identity.runtime_id != before.actor_identity.runtime_id or after.actor_identity.life_generation < before.actor_identity.life_generation: return _error("actual_map_player_identity_continuity_required")
	else:
		var publication: Variant = event.payload.get("visual_projection") if event.get("payload") is Dictionary else null
		if event.get("operation") == &"actor_visual_projection" and event.get("arguments") is Array and event.arguments.size() == 1: publication = event.arguments[0]
		if not transaction.is_empty() or not publication is Dictionary or publication.get("identity") != after.actor_identity or publication.get("kind") != "player" or not Contract.validate_presentation(publication): return _error("actual_current_player_life_publication_required")
		if before.actor_identity.world != after.actor_identity.world or before.actor_identity.runtime_id != after.actor_identity.runtime_id or after.actor_identity.life_generation <= before.actor_identity.life_generation: return _error("actual_original_monotonic_player_life_required")
	var key: String = _owner_key(after)
	if _owners.has(key): return _error("player_rehome_destination_already_owned")
	var template: Dictionary = _templates.get(old.template,{})
	if template.is_empty() or inspect_original_actor_renderer_pin(before,{"asset_key":"closure"},scope).get("success") != true: return _error("actual_original_player_pins_required")
	var next_root := "actor_owner:"+key
	# Keep the old strong roots until the SAME port and Shell have accepted the
	# new identity. Failures retain both records for explicit fault retirement.
	if not _vault.get_ref()._replace_roots(next_root,template.texture_tokens): return _error("actual_player_destination_roots_rejected")
	var next: Dictionary = old.duplicate(false)
	next.owner = after.duplicate(true); next.root_key = next_root
	next.rehome_from = _owner_key(before); next.rehome_event_ordinal = event.ordinal
	_owners[key] = next
	_aux_references[next_root] = _aux_references[old.root_key].duplicate()
	return {"success":true,"status":"READY","owner_descriptor":after,"loading_scope":scope,"actual_instance_id":old.instance.get_ref().get_instance_id()}

func finish_original_player_identity_rehome(before: Dictionary, after: Dictionary, scope: Dictionary, view: Node2D) -> Dictionary:
	if not _main() or not is_instance_valid(view): return _error("actual_Main_player_instance_required")
	var old_key: String = _owner_key(before)
	var next: Dictionary = _owners.get(_owner_key(after),{})
	var old: Dictionary = _owners.get(old_key,{})
	if next.is_empty() or old.is_empty() or next.get("rehome_from") != old_key or next.scope != scope or next.owner != after or next.instance == null or next.instance.get_ref() != view or old.instance.get_ref() != view or view.get("_identity") != after.actor_identity or view.get("_assets").owner_descriptor() != after or next.get("rehome_event_ordinal") != _prefix.actual_current_original_event().get("ordinal"): return _error("actual_same_port_Shell_rehome_commit_required")
	if not _vault.get_ref()._replace_roots(old.root_key,[]): return _error("actual_previous_player_roots_release_failed")
	_aux_references.erase(old.root_key); _owners.erase(old_key)
	next.erase("rehome_from"); next.erase("rehome_event_ordinal")
	return inspect_original_actor_renderer_pin(after,{"asset_key":"closure"},scope)

func lookup_original_actor_renderer_asset(owner: Dictionary, key: String, scope: Dictionary) -> Dictionary:
	if not _main(): return _error("actual_Main_asset_lookup_required")
	var owned: Dictionary = _owners.get(_owner_key(owner),{})
	if owned.is_empty() or owned.owner != owner or owned.scope != scope or owned.retiring: return _error("actual_active_asset_owner_required")
	var template: Dictionary = _templates.get(owned.template,{})
	var fact: Dictionary = template.get("facts",{}).get(key,{})
	if key.begins_with("token:"):
		var token := int(key.trim_prefix("token:"))
		if token in template.get("texture_tokens",[]): fact = {"asset_key":key,"exists":true,"resource_token":token}
	if fact.is_empty(): return _error("unprepared_asset_key:"+key,"MISSING")
	var result: Dictionary = fact.duplicate(true)
	result.merge({"success":true,"owner_descriptor":owner,"loading_scope":scope})
	return result

func inspect_original_actor_renderer_pin(owner: Dictionary, fact: Dictionary, scope: Dictionary) -> Dictionary:
	if not _main(): return _error("actual_Main_pin_inspection_required")
	var owned: Dictionary = _owners.get(_owner_key(owner),{})
	if owned.is_empty() or owned.owner != owner or owned.scope != scope: return _error("actual_actor_pin_owner_required")
	var template: Dictionary = _templates.get(owned.template,{})
	if template.is_empty() or template.database_revision != GameData.database_revision or template.configuration_revision != ContentLayers.configuration_revision: return _error("actual_actor_pin_template_changed")
	var vault: RefCounted = _vault.get_ref()
	var roots: Dictionary = vault.get("_texture_roots")
	for token: int in template.texture_tokens:
		if token not in roots.get(owned.root_key,[]) or vault.texture_for_renderer(token) == null: return _error("actual_actor_texture_pin_missing")
	for token: int in template.audio_tokens:
		if audio_for_renderer(token) == null: return _error("actual_actor_audio_pin_missing")
	if not _aux_references.has(owned.root_key) or template.shader not in _aux_references[owned.root_key]: return _error("actual_actor_shader_pin_missing")
	if fact.get("asset_key") != "closure":
		var actual: Dictionary = lookup_original_actor_renderer_asset(owner,str(fact.get("asset_key","")),scope)
		if actual != fact: return _error("actual_asset_fact_changed")
	return {"success":true,"phase":"INSTANCE_BOUND" if owned.instance_bound else "INPUTS_PINNED","owner_descriptor":owner,"loading_scope":scope,"asset_fact":fact}

func audio_for_renderer(token: int) -> AudioStream:
	if not _main(): return null
	var value: Variant = _audio_references.get(token)
	return value as AudioStream if value is AudioStream and value.get_instance_id() == token else null

func bind_original_actor_renderer_instance(owner: Dictionary, scope: Dictionary, view: Node2D) -> Dictionary:
	if inspect_original_actor_renderer_pin(owner,{"asset_key":"closure"},scope).get("success") != true or not is_instance_valid(view) or not view.is_inside_tree() or view.get("_identity") != owner.actor_identity or view.get("_kind") != owner.kind: return _error("actual_created_actor_instance_required")
	var visual: Node2D = view.get("visual")
	if visual == null or visual.get_script() != PlayerVisual or not visual.actual_render_binding_ok(): return _error("actual_player_visual_binding_required")
	var skill: Sprite2D = visual.get("skill_effect_sprite")
	var proc: Sprite2D = visual.get("passive_proc_effect_sprite")
	if not is_instance_valid(skill) or not is_instance_valid(proc): return _error("actual_original_effect_Sprites_required")
	var first: ShaderMaterial = skill.material
	var second: ShaderMaterial = proc.material
	var key := _owner_key(owner)
	var row: Dictionary = _owners[key]
	var shader: Shader = _templates[row.template].shader
	if first == null or second == null or first == second or first.shader != shader or second.shader != shader: return _error("actual_distinct_original_shader_materials_required")
	for material: ShaderMaterial in [first,second]:
		if material not in _aux_references[row.root_key]: _aux_references[row.root_key].append(material)
	var bar: Node2D = view.get("health_bar")
	if bar == null or bar.get_script() != preload("res://scripts/gameplay/presentation/player_main_health_bar.gd") or not bar.get("_label_font") is Font: return _error("actual_original_Player_label_font_required")
	var actual_font: Font = bar.get("_label_font")
	if actual_font not in _aux_references[row.root_key]: _aux_references[row.root_key].append(actual_font)
	var nodes: Array[Node] = [view]
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		for child: Node in node.get_children(true): nodes.append(child)
		if node is Control and node.has_theme_font("font"):
			var font: Font = node.get_theme_font("font")
			if font != null and font not in _aux_references[row.root_key]: _aux_references[row.root_key].append(font)
	row.instance = weakref(view); row.instance_bound = true
	return inspect_original_actor_renderer_pin(owner,{"asset_key":"closure"},scope)

func begin_original_actor_renderer_retirement(owner: Dictionary, scope: Dictionary) -> Dictionary:
	if not _main(): return _error("actual_Main_actor_retirement_required")
	var row: Dictionary = _owners.get(_owner_key(owner),{})
	if row.is_empty() or row.owner != owner or row.scope != scope: return _error("actual_owned_actor_retirement_required")
	if row.instance != null and is_instance_valid(row.instance.get_ref()): return _error("actor_Node_still_present","PENDING")
	row.retiring = true
	return {"status":"PENDING","owner_descriptor":owner}

func poll_original_actor_renderer_retirement(owner: Dictionary, scope: Dictionary) -> Dictionary:
	if not _main(): return _error("actual_Main_actor_retirement_required")
	var key := _owner_key(owner)
	var row: Dictionary = _owners.get(key,{})
	if row.is_empty() or row.owner != owner or row.scope != scope or not row.retiring: return _error("actual_accepted_actor_retirement_required")
	if row.instance != null and is_instance_valid(row.instance.get_ref()): return {"status":"PENDING","owner_descriptor":owner}
	if not _vault.get_ref()._replace_roots(row.root_key,[]): return _error("actual_actor_roots_release_failed")
	_aux_references.erase(row.root_key); _owners.erase(key)
	return {"status":"READY","owner_descriptor":owner,"actual_physical_pins_released":true,"actual_original_obligations_terminal":true}

func release_original_template(template_key: String) -> Dictionary:
	if not _main() or not _templates.has(template_key): return _error("actual_owned_template_required")
	for row: Dictionary in _owners.values():
		if row.template == template_key: return {"status":"PENDING"}
	var row: Dictionary = _templates[template_key]
	if not _vault.get_ref()._replace_roots(row.root_key,[]): return _error("actual_template_roots_release_failed")
	_aux_references.erase(row.root_key); _templates.erase(template_key)
	var retained: Dictionary = {}
	for template: Dictionary in _templates.values():
		for token: int in template.audio_tokens: retained[token] = true
	for token: int in _audio_references.keys():
		if not retained.has(token): _audio_references.erase(token)
	return {"status":"READY","actual_template_released":template_key}

func terminal() -> bool:
	return _main() and _templates.is_empty() and _owners.is_empty() and _audio_references.is_empty() and _aux_references.is_empty()

static func load_original_player_appearance_path(path: String) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or path.is_empty(): return {"status":"INVALID"}
	if ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		return {"status":"LOADED" if texture != null else "FAILED","resource":texture,"origin":"original_PlayerVisual.imported","path":path,"imported_exists":true}
	if FileAccess.file_exists(path) and path.get_extension().to_lower() == "png":
		var image := Image.load_from_file(path)
		if image == null or image.is_empty(): return {"status":"FAILED","origin":"original_PlayerVisual.raw_png","path":path}
		return {"status":"LOADED","resource":ImageTexture.create_from_image(image),"origin":"original_PlayerVisual.raw_png","path":path}
	return {"status":"ABSENT","origin":"original_PlayerVisual.no_load_branch","path":path,"imported_exists":false,"file_exists":FileAccess.file_exists(path)}
