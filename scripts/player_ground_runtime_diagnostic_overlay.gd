class_name PlayerGroundRuntimeDiagnosticOverlay
extends Node2D

var actor: Node2D


static func enabled_for_runtime() -> bool:
	# The on-character lines and text were an acceptance-only aid. Keep the
	# coordinate snapshot API available to focused tests, but never attach a
	# visible overlay to gameplay actors.
	return false


func setup(owner_actor: Node2D) -> void:
	actor = owner_actor
	visible = false


func coordinate_snapshot() -> Dictionary:
	if not is_instance_valid(actor):
		return {}
	return {
		"actorOrigin": Vector2.ZERO,
		"physicsFootCenter": Vector2.ZERO,
		"delta": Vector2.ZERO,
	}
