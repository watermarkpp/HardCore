# Maps worktree rules

- Own map art/data, `map_editor_workspace/**`, map scripts, map-editor services, environment validation and map tests.
- Maps may define geometry, collision, portals, regions and stable `spawn_group_id`; they must not define monster combat values or equipment drops.
- Preserve authored map work. Publish only source-backed runtime releases and hand cross-domain spawn semantics to integration.
