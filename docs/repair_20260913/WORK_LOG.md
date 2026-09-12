# 2026-09-13 repair and APK acceptance

Controller: current Codex/Astra. No engineering delegation. GLM read-only scan attempted via the approved arkcli profile; returned BLOCKED (`CreateProcessWithLogonW failed: 2`) without project evidence. Controller continues targeted investigation.

## Baseline and preservation

- Original checkout: `HardCore`, `codex/m30-r3-integration`, `b3296528d7f85c7dff2c78adafaa0f5e4ec33c16`. Existing AGENTS.md edits and untracked translation/uid files preserved there.
- Sole implementation tree: `HardCore-worktrees/takeover-20260913`, `codex/takeover-20260913`.
- Latest UI candidate: `codex/r3-3-single-heading`, `e608c2c09fbe98ad2bce68344052af42c32d70b3`; inspected from Git, not the other tree's dirty test file. Merge combines it with b3296528, retaining that branch's audio missing-key and APK verification fixes. Merge is uncommitted until integration checks.
- Bootstrap fails only because the task branch is outside its legacy route whitelist. Equivalent preflight uses `docs/agent_rules/integration.md`; required baseline, ownership and snapshot JSON files exist. Root user instructions apply to this serial cross-system integration task.
- Latest existing desktop APK: `HardCore-20260912-release-closure-v75.apk`; final delivery must preserve package/signing/save compatibility and use a newer version.
- Protected: authored maps, map geometry, monster count/stats/respawn, approved equipment base attributes, drop probabilities and retention ordering, attack ownership/cadence, latest manual UI layout. Only explicitly requested deltas (JP rolls, luck/curse, fire-wall 3x3, 0.6 height, drop cap 15, visual corrections) may change their related behavior.
- Original map trees: assets/maps `c46ea4b3146096113ae793236a87e4ceceb7812d`, map_editor_workspace `fa6c3e7a67d389e555cdf4140337f37cf0ee88f2`. Equipment master blob `fd8262dbc67bd65b978f63e38da728a84e2ecf37`. Latest UI layout must be preserved from e608c2c0, not restored from b3296528.
- Imported assets copied into independent task cache; tool binaries copied locally. dev_art_sources is a read-only-use junction to the existing local sources. No user saves copied or modified.

## Requested acceptance (pending)

| # | Scope | Required evidence | State |
|---|---|---|---|
| 1 | Multi-monster frame drops | Same-scenario CPU/frame profile before/after; preserved gameplay | NOT_RUN |
| 2 | Inventory selection and UI details/rarity | Actual native and emulated input; repeat open, selection/dismiss/equip; detail geometry and color | NOT_RUN |
| 3 | Blessing oil and exclusive luck/curse | Primary original rule trace, deterministic outcomes and combat consumption; zero stat hidden | NOT_RUN |
| 4 | Small JP | Primary roll rules, multiple attributes/amounts, justified single-player rate; deterministic/statistical checks | NOT_RUN |
| 5 | Fire wall 3x3, height 60%, spell depth | Canonical footprint and visual depth/height regression | NOT_RUN |
| 6 | Weapon/body run depth | Primary action/direction/frame ordering; all weapon contract coverage and visual samples | NOT_RUN |
| 7 | Drop/pickup/gold stalls | Production measurements for single equipment, gold, mass drop and mass pickup | NOT_RUN |
| 8 | Drop cap 15 | Authority and runtime agree; probabilities/order unchanged; overflow and pickup tests | NOT_RUN |
| 9 | Monster ranged/spell visuals | Exact IDs and primary source mappings, runtime load tests; no guessed substitute | NOT_RUN |

Final gate: targeted tests, related regression, final diff/frozen hash review, fixed source commit, isolated APK build, package/signing/bytecode/resource checks, desktop artifact SHA. Device/manual review remains NOT_RUN until actually performed.

## Retrieved requirements

Read current task plus ChatGPT project conversations: `UI修改方案`, `制定GLM修复方案`, `核对装备与武器问题`, `审查优化并打包`. Treat historical assistant diagnoses as candidates, not proof. Preserve docked details, title/body sizes 20/14, rarity names, music/SFX sliders with save-on-close, blank-tap dismissal without breaking function controls, no residual selection border, static ground drops, and no discarded-item success popup. Latest long-text contract permits body-only vertical scroll after legal geometry is exhausted. Weapon report also describes level-30 炼狱→井中月 replacement failing until re-entry; verify the real UI transaction while retaining item requirements.
