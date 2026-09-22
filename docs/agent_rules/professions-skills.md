# Professions-skills worktree rules

- Own profession growth, player skills, player projectiles, summons, formulas, state machines, effects and their tests.
- Shared combat runtime changes require integration handoff; do not change monster AI, map spawning, equipment definitions, UI layout or global save formats.
- Preserve formal player skill ranges and reject unreachable casts before resource, action or cooldown commits.
