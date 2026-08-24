# Integration worktree rules

- Own the integration baseline, merges, conflict resolution, cross-system contracts, full acceptance, global services and save formats.
- Exclusive files include `project.godot`, `AGENTS.md`, `scripts/game_root.gd`, `scripts/game_data.gd`, `scripts/region_content.gd`, and `tools/run_godot_tests.ps1`.
- Integrate map-to-monster, monster-to-drop, and cross-domain stable-ID mappings only after the responsible professional branch supplies a tested commit.
- Preserve user dirty work and frozen assets. Never use destructive cleanup to make a merge convenient.
- Run tests through `tools/run_godot_tests.ps1`; keep Godot user data and logs inside this worktree.
- Follow `assets/data/source_priority_policy.json` and reject lower-source overrides without explicit missing evidence.
