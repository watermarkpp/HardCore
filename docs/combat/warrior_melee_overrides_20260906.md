# Warrior melee project overrides (2026-09-06)

This note records the explicit HardCore gameplay overrides represented by
`assets/data/vanilla_176/skills_source_of_truth_v1.json`. It is not a claim
that the public or historical 1.76 sources prove these exact GU values.

The release footprint remains the only geometry truth. All positions are
fractional canonical ground GU obtained from the shared footpoint projection;
raw pixels and a second range calculation are not valid substitutes.

| Mode | Total reach | Target rule | Defence rule |
| --- | ---: | --- | --- |
| Ordinary melee | 2.0 GU | one target | existing physical damage path; AC settlement was not changed by this geometry patch |
| Fire Sword | 2.0 GU | one target | existing physical damage path; AC settlement was not changed by this geometry patch |
| Thrusting / 刺杀 | 3.0 GU line, 1.0 GU width | unlimited within line | 0..1.5 GU consumes AC; 1.5..3.0 GU bypasses AC |
| Half Moon / 半月 | 2.0 GU, 120 degree fan | unlimited within fan | existing physical damage path; AC settlement was not changed by this geometry patch |

Fire Sword must have a valid melee target before the action starts. An empty
input is rejected without body animation, resource consumption, cooldown, or
proficiency side effects. A target that moves after a valid input is a normal
release-time miss and is a separate runtime case.

攻杀剑术 is a single proc layer for each valid warrior melee action. Its
post-body physical bonus applies to ordinary, Fire Sword, Thrusting, and Half
Moon hits. The selected body skill keeps its own animation; the proc's extra
visual effect is emitted only for a normal body action, not for a skill body
mode. Wild Rush currently has no body-damage effect, so this layer is not
applicable to it; healing, summons, and non-warrior skills are outside this
contract.

The integration owner has synchronized the shared `combat_units` authority,
policy hash, and common contract to the project override (ordinary/fire/half
moon 2.0 GU and thrust 3.0 GU). This note does not claim that the ordinary,
Fire Sword, or Half Moon damage paths were changed to subtract AC; the new
runtime defense evidence is scoped to the two thrust segments.

The canonical source hash after the two new warrior required-test entries is
`D439258D5EF1E76F86FB2EB590A8EC22D49757CD909DE0C1F889370BD2CCDC19`.
The archived package manifest remains untouched. The two project-owned
required-test entries (`slaying_scope_all_body_modes` and
`fire_sword_requires_target_before_action`) are declared explicitly in
`assets/data/vanilla_176/skill_test_manifest_project_overlay_v1.json`; the
loader rejects a missing, mismatched, duplicate, or SOT-unlisted overlay entry
instead of auto-filling the manifest. The merged manifest therefore contains
19 P0 and 152 P1 entries, with 152 matching specialty validators.

The runtime proof paths are:

- `tests/skills/warrior_melee_entry_runtime_test.tscn`: production
  `PlayerCharacter.request_skill`/`request_attack` preserves the existing normal
  fallback without releasing or consuming an armed Fire Sword when no target
  exists; production `GameRoot._on_player_attack` reaches a target at
  the 2 GU release boundary for warrior, wizard, and taoist profiles.
- `tests/skills/summon_owner_teleport_runtime_test.tscn`: same-map random
  teleport and the final map-arrival relocation boundary retain both main pets'
  HP while clearing target, pending attack, velocity, and stale motion state.
- `tests/skills/warrior_thrust_defense_runtime_test.tscn`: canonical thrust
  release snapshots feed both segment damage calls; only the primary segment
  settles high enemy AC.

For summon map arrival, the integration call order is part of the relocation
contract: after the final player position and destination map are established,
reconfigure each retained pet with the current map projection, then compute the
legal canonical spawn plan and call
`SummonActor.relocate_after_owner_teleport(position_px)`. The method clears
stale target/pending-attack/motion state but does not search obstacles or alter
HP, growth, or buffs; the caller owns the legal-position search.
