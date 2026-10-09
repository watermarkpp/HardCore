# B02-006 / B02-005 / B02-007 reachability disposition

**Scope.** Static review only, against the current fixed-source overlay after the B02 Player repairs. No Godot/native run was performed and no production or test file was changed. The primary skill bytes are `assets/data/vanilla_176/skills_source_of_truth_v1.json` (SHA256 `7575C45A7BD147F8E60D2EFDB15C6C5E9781445DDC2F748E73DD69ED386A62AB`). Relevant source fingerprints at review time:

| file | SHA256 |
|---|---|
| `scripts/player.gd` | `40CE84D019E1B5770A5749A5384C49572F7F7666A5FF581D3DB9B9BD05E718D3` |
| `scripts/game_root.gd` | `706C754BD41D3CF39F5EF2308F7D4DBF2D7A281728C0D08408CF95C1D52A82A0` |
| `scripts/player_state.gd` | `13CCCB4CFF55EDA54C858C69EA8A0DA16C33AF44F19EC43B7199CF3DDF4D80A6` |
| `scripts/skills/skill_resource_service.gd` | `DA17E627C6BD614CC51E3BD31C76D39D4F2D78A5B70EAD1667B37E48BAE2C24F` |
| `scripts/skills/skill_runtime_router.gd` | `841A02F77B299000F183957A2212ADE72E5EEAF15ADEB102041C268336252CD9` |
| `scripts/skills/skill_data_loader.gd` | `D68158A992129EB5F479CDCAF38914AA63A6FFF19716C3D3A7674972B9A6389D` |

## B02-006 — `CONDITIONAL_RISK_NOT_PROVEN` (no current trigger)

The source-level omission is real: `Player.can_request_skill()` at `scripts/player.gd:562-608` builds one `SkillResourceService.quote()` and returns only `current_mp >= quote.mp_cost` at line 608. It does not require `quote.valid`. `GameRoot._try_release_skill()` at `scripts/game_root.gd:7561-7577` repeats the MP comparison and calls `player.can_request_skill()`, also without a validity check. A formally invalid quote with an affordable MP value could therefore pass these admission gates and start Player action/cooldown state before the later canonical plan rejects it.

The fixed production data does not currently demonstrate that precondition:

* The SOT contains 33 skills: 6 warrior, 14 wizard, and 13 taoist. The only material-bearing definitions are taoist skills (`taoist.poison`, `soul_fire_talisman`, summons, buffs, and related support skills). `SkillResourceService._quote_single()` at `scripts/skills/skill_resource_service.gd:93-172` applies the explicit `class == "taoist"` material-free contract at lines 94 and 123-125, before material sufficiency can reject them. This is the user-authoritative Taoist material-free policy and must remain unchanged. `taoist.poison` cannot currently reach the `selected_poison_powder` invalid branch at lines 138-147 because its item is nulled by that policy; its canonical context selection at `scripts/player_state.gd:4052-4059` only chooses the legacy powder label.
* All non-Taoist SOT definitions have no item requirement. Their reachable non-MP quote failure is therefore not established by the fixed definitions. `insufficient_mana` is the MP reason and is already covered by the two MP comparisons before action admission.
* The dual-defense path is deliberately one transaction. `PlayerState.canonical_skill_resource_context()` at `scripts/player_state.gd:4080-4095` adds the partner only when the other defense skill is learned. `_freeze_partner_resource_context()` at `scripts/player.gd:790-797` takes the partner from the current action configuration. `_quote_dual_defense()` at `scripts/skills/skill_resource_service.gd:231-312` rejects malformed/missing partners, but a current configuration is checked by `_action_configuration_current()` at `scripts/player.gd:563-564` and `622-623`, and the production capture at `scripts/game_root.gd:15537-15559` supplies the learned partner definition/rank. No valid current learned configuration producing `invalid_combined_defense_partner` or `unknown_skill` was found.

The later canonical path is stricter. `SkillRuntimeRouter.route/build` computes the quote at `scripts/skills/skill_runtime_router.gd:73-88` and explicitly rejects `valid == false` before constructing the plan. GameRoot executes that canonical plan at `scripts/game_root.gd:8725-8749`; resource commit is based on the accepted plan at `8750-8780`. This prevents an invalid quote from becoming a committed resource/effect, but it does not remove the earlier conditional risk of an already-started Player action if resource/context state changes between admission and release.

**Disposition.** `CONDITIONAL_RISK_NOT_PROVEN`, not a confirmed production bug. Do not add a speculative `quote.valid` gate or alter Taoist material policy from this static evidence. The only justified follow-up is a fixed-source direct contract that constructs an actually reachable non-MP invalid quote through a real learned/configured skill or a real feature-modified definition, then asserts no action timer/cooldown/stealth break/MP change. If no such trigger can be produced, retain this as a conditional source risk. A malformed synthetic `Dictionary`, an invented material requirement, or an invalid/stale configuration is not evidence.

## Formal skill/resource coverage map

| SOT family | concrete definitions | resource outcome in current production | quote-invalid reachability conclusion |
|---|---|---|---|
| Warrior | `warrior.basic_swordsmanship`, `slaying_swordsmanship`, `thrusting`, `half_moon`, `wild_rush`, `fire_sword` | no item; melee/toggle resource handling | no non-MP invalid quote shown |
| Wizard | `wizard.fireball`, `repulsion_ring`, `temptation_light`, `hellfire`, `lightning`, `great_fireball`, `teleport`, `exploding_flame`, `fire_wall`, `laser`, `hell_lightning`, `magic_shield`, `holy_word`, `ice_storm` | no item in SOT; MP only for this quote layer | no non-MP invalid quote shown |
| Taoist | `healing`, `spiritual_warfare`, `poison`, `soul_fire_talisman`, `summon_skeleton`, `invisibility`, `mass_invisibility`, `magic_defense`, `defense`, `revelation`, `entrapment`, `mass_healing`, `summon_divine_beast` | material fields exist, but `SkillResourceService` applies the explicit material-free Taoist contract; poison's powder selector remains a data/context field | no current material-invalid trigger; dual-defense malformed partner remains conditional only |

## B02-005 — `ACCEPTED_CONTRACT / NO_CHANGE`

`Player.request_skill()` calls `break_stealth()` at `scripts/player.gd:624-629`, before `can_request_skill()` and before the world preflight in `_request_active_skill()` at `636-645`. The dated source comment explicitly says the user override is that **submission** breaks stealth, so a later LOS/world rejection does not retroactively make the submission successful. This matches the current product rule and the previous B02 finding. No source change is justified. A future product change from “submission” to “accepted cast” would need a decision-first regression covering blocked LOS, insufficient MP, action rejection, and the existing equipment rearm owner; it must not be inferred from code style.

## B02-007 — `ACCEPTED_CONTRACT / NO_CHANGE`

The formula split remains a source fact, not a proven defect. Legacy equipment lifesteal in `scripts/game_root.gd:13369-13372` derives recovery from the original damage input (`max(1, damage)`), while the feature damage/lifesteal path records and consumes actual HP loss in its damage facts. The B02 source chain is `GameRoot._apply_physical_hit` -> combat damage resolver -> Enemy HP mutation -> legacy recovery versus feature `actual_loss`. The current user-authoritative equipment contract keeps the legacy rainbow-ring/equipment recovery basis on the passed damage value. Feature `actual_loss` is a separate existing contract and is not evidence that the equipment lane must change. Preserve both lanes; no automatic formula merge is authorized.

## Validation status

`STATIC_REVIEW_ONLY`; no new test was created or run for this note, no native result is claimed, and the earlier B02-005/B02-007 source evidence remains applicable only to the fixed source fingerprints listed above.
