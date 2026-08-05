class_name CasterSkillBeamVisualEffect
extends CasterSkillVisualEffect

const DEFAULT_SINGLE_ACTIVE_GROUP := "beam"

var _single_active_group := DEFAULT_SINGLE_ACTIVE_GROUP


func _ready() -> void:
	super._ready()


func _single_active_group_name() -> String:
	return _single_active_group


func _safe_single_active_group() -> String:
	return _single_active_group_name()
