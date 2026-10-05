extends RefCounted

const RESOURCE_PATH := "res://assets/shaders/trial_magic_screen.gdshader"

static func acquire_resource() -> Resource:
	return ResourceLoader.load(RESOURCE_PATH)
