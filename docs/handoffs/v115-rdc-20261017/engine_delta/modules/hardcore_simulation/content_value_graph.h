#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"

// Stateless boundary. Every invocation has its own identity table; no static
// cache, SceneTree, Resource, or shared mutable owner state participates.
class HardCoreContentValueGraph : public RefCounted {
	GDCLASS(HardCoreContentValueGraph, RefCounted);
protected:
	static void _bind_methods();
public:
	Dictionary capture(const Variant &p_value, bool p_read_only = true, bool p_content_only = true) const;
	Dictionary validate(const Variant &p_value, bool p_content_only = true) const;
	// Opaque identity for one local copy invocation; never a gameplay ID.
	int64_t container_identity_for_local_copy(const Variant &p_value) const;
};
