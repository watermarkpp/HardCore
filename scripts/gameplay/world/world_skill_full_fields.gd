extends "res://scripts/gameplay/world/world_skill_fields.gd"
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const LinkSequence := preload("res://scripts/gameplay/world/world_skill_link_sequence.gd")
const LinkMap := preload("res://scripts/gameplay/world/world_skill_link_map.gd")

func configure_actor_links(actors: RefCounted) -> void:
	_values["_pending_main_pet_arrivals"] = LinkSequence.new(actors)
	_values["_fire_wall_field_registry"] = LinkMap.new(actors)

func _init() -> void:
	super()
	_values["manual_target_lock"] = false
	_values["manual_magic_target_lock"] = false
	_values["_active_target_domain_magic"] = true
	_values["auto_target_enabled"] = true
	_values["_active_safe_zones"] = []
	_values["_safe_zone_context"] = {
	"contract_id": WorldSpatialRulesScript.SAFE_ZONE_CONTEXT_CONTRACT_ID,
	"map_id": -1,
	"revision": 0,
	"generation": 0,
	"valid": true,
	"failure_reason": "",
	"zones": [],
	"aabb_ground_gu": Rect2(),
}
	_values["_player_safe_zone_cache"] = {
	"player_instance_id": 0,
	"map_id": -1,
	"revision": -1,
	"generation": -1,
	"ground_position_gu": Vector2.INF,
	"inside": false,
	"valid": false,
}
	_values["_combat_target_query_service"] = null
	_values["_combat_target_query_service_map_id"] = -2
	_values["_combat_target_query_service_index"] = null
	_values["_target_spatial_query_scratch"] = ([] as Array[Object])
	_values["_aoe_candidate_scratch"] = ([] as Array[Object])
	_values["_direct_spell_target_stats_scratch"] = {}
	_values["_ground_effect_manager"] = null
	_values["missing_projection_rejection_count"] = 0
	_values["projection_rejection_reason"] = &""
	_values["reference_audit_mode"] = false
	_values["_aoe_reference_fallback_test_enabled"] = false
	_values["_projection_profile_cache"] = {}
	_values["_projection_profile_cache_audit_mode"] = false
	_values["_projection_profile_runtime_identity_cache"] = {}
	_values["_ground_effect_runtime_serial"] = 0
	_values["_map_transition_in_progress"] = false
	_values["_pending_main_pet_retry_tile"] = Vector2i.ZERO
	_values["_pending_main_pet_retry_tile_valid"] = false
	_values["_canonical_cast_serial"] = 0
	_values["_skill_footprint_release_serial"] = 0
	_values["_canonical_fire_charge_expires_ms"] = 0
	_values["_selected_friendly_instance_id"] = 0
	_values["_ongoing_heals"] = ([] as Array[Dictionary])
	_values["_pending_melee_diagnostic"] = {}
	_values["_active_physical_hit_diagnostics"] = ([] as Array[Dictionary])
	_values["_fire_wall_field_order"] = []
	_values["_fire_wall_registry_validation_enabled"] = true
	_values["_hc_lightning_hint_ms"] = -1000
