#include "content_value_graph.h"
#include "core/object/class_db.h"

#include <cmath>
#include <algorithm>
#include <unordered_map>
#include <cstdint>

namespace {
struct Key {
	const void *id;
	Variant::Type type;
	bool operator==(const Key &other) const { return id == other.id && type == other.type; }
};
struct KeyHash {
	std::size_t operator()(const Key &key) const { return std::hash<const void *>{}(key.id) ^ (static_cast<std::size_t>(key.type) << 1); }
};
struct Entry { Variant value; bool gray = true; int height = 0; std::size_t expanded_nodes = 1; };
struct State {
	std::unordered_map<Key, Entry, KeyHash> identities;
	Array errors;
	std::size_t nodes = 0;
	int last_height = 0;
	bool copy;
	bool read_only;
	bool content_only;
	void fail(const char *error) { if (errors.is_empty()) errors.push_back(String(error)); }
};

Variant visit(const Variant &value, int depth, State &state) {
	const std::size_t node_begin = state.nodes;
	state.last_height = 0;
	if (depth > 64 || ++state.nodes > 8000000) { state.fail("content_graph_capacity"); return {}; }
	const auto type = value.get_type();
	switch (type) {
		case Variant::NIL: case Variant::BOOL: case Variant::INT: case Variant::STRING: return value;
		case Variant::FLOAT:
			if (std::isfinite(static_cast<double>(value))) return value;
			state.fail("non_finite_content_number"); return {};
		case Variant::ARRAY: case Variant::DICTIONARY: break;
		case Variant::OBJECT: case Variant::CALLABLE: case Variant::SIGNAL: case Variant::RID:
			state.fail("non_value_content_object"); return {};
		default:
			if (!state.content_only) {
				// Numeric transport values are copied by Variant/COW. Their owning
				// presentation/input schema is responsible for dimensional checks.
				if (type == Variant::VECTOR2 && !static_cast<Vector2>(value).is_finite()) { state.fail("non_finite_transport_vector"); return {}; }
				if (type == Variant::VECTOR3 && !static_cast<Vector3>(value).is_finite()) { state.fail("non_finite_transport_vector"); return {}; }
				return value;
			}
			state.fail("non_value_content"); return {};
	}

	const Key key{type == Variant::ARRAY ? static_cast<Array>(value).id() : static_cast<Dictionary>(value).id(), type};
	auto previous = state.identities.find(key);
	if (previous != state.identities.end()) {
		if (previous->second.gray) { state.fail("cyclic_content_graph"); return {}; }
		// Reusing an alias must preserve the original expanded graph's depth
		// and capacity limits, including a deeper second path to this value.
		if (depth + previous->second.height > 64 ||
				previous->second.expanded_nodes - 1 > 8000000 - state.nodes) { state.fail("content_graph_capacity"); return {}; }
		state.nodes += previous->second.expanded_nodes - 1;
		state.last_height = previous->second.height;
		return previous->second.value;
	}
	// Container identity lookup is independent of contents. Equal but distinct
	// empty containers do not form a structural-hash collision bucket.
	if (type == Variant::ARRAY) {
		const Array source = value;
		if (source.is_typed() && source.get_typed_builtin() == Variant::OBJECT) { state.fail("non_value_content_type"); return {}; }
		Array target = state.copy ? source.duplicate(false) : source;
		if (state.copy) target.clear();
		state.identities.emplace(key, Entry{target, true});
		int height = 0;
		for (int i = 0; i < source.size(); ++i) {
			Variant child = visit(source[i], depth + 1, state);
			if (!state.errors.is_empty()) return {};
			height = std::max(height, state.last_height + 1);
			if (state.copy) target.push_back(child);
		}
		if (state.copy && state.read_only) target.make_read_only();
		auto &entry = state.identities.at(key);
		entry.gray = false; entry.height = height; entry.expanded_nodes = state.nodes - node_begin;
		state.last_height = height;
		return target;
	}
	const Dictionary source = value;
	if ((source.is_typed_key() && source.get_typed_key_builtin() == Variant::OBJECT) ||
			(source.is_typed_value() && source.get_typed_value_builtin() == Variant::OBJECT)) { state.fail("non_value_content_type"); return {}; }
	Dictionary target = state.copy ? source.duplicate(false) : source;
	if (state.copy) target.clear();
	state.identities.emplace(key, Entry{target, true});
	int height = 0;
	Array keys = source.keys();
	for (int i = 0; i < keys.size(); ++i) {
		const Variant &field = keys[i];
		// Runtime navigation indices use exact GU bucket/canonical vertex
		// keys. Preserve their Variant types only in runtime transport mode;
		// JSON content/save admission retains its original restricted keys.
		const bool runtime_value_key = !state.content_only &&
				(field.get_type() == Variant::STRING_NAME ||
				field.get_type() == Variant::VECTOR2I ||
				(field.get_type() == Variant::VECTOR2 && static_cast<Vector2>(field).is_finite()));
		// GDScript named Dictionary assignment retains a StringName key. It is
		// an immutable runtime value, not an Object or a JSON field conversion.
		// Preserve its exact type here; default content/save mode still rejects it.
		if (field.get_type() != Variant::STRING && field.get_type() != Variant::INT &&
				!(field.get_type() == Variant::FLOAT && std::isfinite(static_cast<double>(field))) &&
				!runtime_value_key) { state.fail("non_value_content_key"); return {}; }
		Variant child = visit(source[field], depth + 1, state);
		if (!state.errors.is_empty()) return {};
		height = std::max(height, state.last_height + 1);
		if (state.copy) target[field] = child;
	}
	if (state.copy && state.read_only) target.make_read_only();
	auto &entry = state.identities.at(key);
	entry.gray = false; entry.height = height; entry.expanded_nodes = state.nodes - node_begin;
	state.last_height = height;
	return target;
}
Dictionary run(const Variant &value, bool copy, bool read_only, bool content_only) {
	State state{{}, {}, 0, 0, copy, read_only, content_only};
	Variant owned = visit(value, 0, state);
	Dictionary result;
	result["success"] = state.errors.is_empty();
	result["errors"] = state.errors;
	if (copy) result["value"] = state.errors.is_empty() ? owned : Variant();
	result["nodes"] = static_cast<int64_t>(state.nodes);
	result["memo_entries"] = static_cast<int64_t>(state.identities.size());
	return result;
}
}

void HardCoreContentValueGraph::_bind_methods() {
	ClassDB::bind_method(D_METHOD("container_identity_for_local_copy", "value"), &HardCoreContentValueGraph::container_identity_for_local_copy);
	ClassDB::bind_method(D_METHOD("capture", "value", "read_only", "content_only"), &HardCoreContentValueGraph::capture, DEFVAL(true), DEFVAL(true));
	ClassDB::bind_method(D_METHOD("validate", "value", "content_only"), &HardCoreContentValueGraph::validate, DEFVAL(true));
}
Dictionary HardCoreContentValueGraph::capture(const Variant &p_value, bool p_read_only, bool p_content_only) const { return run(p_value, true, p_read_only, p_content_only); }
Dictionary HardCoreContentValueGraph::validate(const Variant &p_value, bool p_content_only) const { return run(p_value, false, false, p_content_only); }

int64_t HardCoreContentValueGraph::container_identity_for_local_copy(const Variant &p_value) const {
	// Exactly Variant::identity_compare Array/Dictionary identity semantics.
	// Caller keeps input containers pinned throughout this local traversal.
	if (p_value.get_type() == Variant::ARRAY) return int64_t(reinterpret_cast<std::uintptr_t>(static_cast<Array>(p_value).id()));
	if (p_value.get_type() == Variant::DICTIONARY) return int64_t(reinterpret_cast<std::uintptr_t>(static_cast<Dictionary>(p_value).id()));
	return 0;
}
