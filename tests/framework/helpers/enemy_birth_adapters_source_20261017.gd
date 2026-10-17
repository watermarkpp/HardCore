extends "res://tests/framework/helpers/player_birth_life_source_20261015.gd"
## Reuses actual Native Player/body/Registry lifecycle. This adds the real
## Enemy target-link setter; it does not pretend to run full Enemy.setup.
const CanonicalAccess := preload("res://scripts/gameplay/world/world_canonical_actor_access.gd")
const EnemyModel := preload("res://scripts/gameplay/actors/enemy_actor_model.gd")
func _init(host: Object, boot: Dictionary) -> void:
	super(host,boot)
	if _record == null: return
	var access := CanonicalAccess.new(_registry,null,self,{}, {})
	var enemy := EnemyModel.new()
	enemy.actor_links = access
	var original_life: int = _model.current_life()
	var prior_leases: int = _registry.remaining_lease_count()
	enemy.primary_target = _record
	var target: Object = enemy.primary_target
	_check(target != null and target.record() == _record,"actual Enemy primary_target resolves the canonical registered Player Handle")
	_check(enemy.get("_primary_target_link").borrow_model() == _model,"real persistent ActorLink retains original PlayerModel, not a substituted facade")
	_check(_registry.resolve_runtime_actor(_model.get_instance_id()) == null,"raw PlayerModel is not a registered Handle identity")
	_check(_model.current_life() == original_life,"target binding does not invent Player combat life")
	target = null
	var link: RefCounted = enemy.get("_primary_target_link")
	link.dispose(); enemy.primary_target = null; link = null
	_check(_registry.remaining_lease_count() == prior_leases,"target/link view leases return exactly to original baseline")
	enemy.actor_links = null
