# Monsters worktree rules

- Own monster art/data, `scripts/enemy.gd`, `scripts/monster_visual.gd`, animation policy, Boss mechanics and monster tests.
- Use stable canonical `monster_id`; runtime identity is ID-only and fail-closed.
- Do not change map geometry, equipment definitions, UI or integration-owned global services.
- Approved Red Moon and fixed-area ground-spike assets are frozen unless the user explicitly reopens them.
