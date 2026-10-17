#pragma once
namespace hardcore::simulation {
// Private C++ scope: World access/real H-P query admission precedes entry.
// Main/default engine queries never enter it. It owns no collision state.
extern thread_local unsigned numeric_point_query_depth;
class ScopedNumericPointQuery {
public:
    ScopedNumericPointQuery() { ++numeric_point_query_depth; }
    ~ScopedNumericPointQuery() { --numeric_point_query_depth; }
    ScopedNumericPointQuery(const ScopedNumericPointQuery &) = delete;
    ScopedNumericPointQuery &operator=(const ScopedNumericPointQuery &) = delete;
};
inline bool numeric_point_query_active() { return numeric_point_query_depth != 0; }
}
