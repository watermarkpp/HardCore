extends RefCounted

const EnemyActorScript := preload("res://scripts/enemy.gd")

## The direct contract drives the same EnemyActor static epoch/quota adapter
## used by the experiment. It never creates an actor or commits an attack.

func admit(process_epoch: int) -> String:
	return EnemyActorScript.attack_ab_test_attempt(process_epoch)

func reset() -> void:
	EnemyActorScript.attack_ab_test_reset_epoch()

func snapshot() -> Dictionary:
	return EnemyActorScript.attack_ab_diagnostics()
