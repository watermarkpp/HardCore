# Price identity preflight (read-only)

Date: 2026-10-09
Scope: current MAIN working tree versus the isolated ATTACK_START_FRAME_AB workspace. No Godot run, test, source edit, or production-data edit was performed for this audit.

## Result

The isolated `immediate_04` `GameData` `push_error("Price candidate identity is unknown, conflicting or repeated")` is a **workspace-copy failure**, not a demonstrated failure of the current MAIN price candidate data.

`GameData` loads `res://assets/data/equipment_price_candidates_v1.json` at `scripts/game_data.gd:1955-1969`. For each record it calls `_price_candidate_owner` (`scripts/game_data.gd:2857-2870`), which resolves `entity_id` through the preloaded `EntityRegistry` and rejects an empty owner or repeated canonical owner. `EntityRegistry.ensure_loaded` (`scripts/identity/entity_registry.gd:16-24`) first validates every `source_hashes` entry against the file in the workspace (`:35-41`). The isolated registry therefore fails before price-owner resolution: its referenced source file is stale relative to the registry.

## Exact dependency mismatch

The registry is byte-identical in MAIN and isolated, but its one declared source dependency is not:

| Path | MAIN | isolated | evidence |
|---|---|---|---|
| `assets/data/runtime/entity_registry_v1.json` | 396,609 bytes; SHA256 `4953930C630C8CAD09A696D5EE95B2B25D673F76F706B5E9BD6F644CAE33654E` | same | exact clone |
| `assets/data/runtime/entity_registry_v1.json` source hash for `res://assets/data/equipment_granted_skills.source.json` | declared `E9B0783FB9EAF9572F38188B5ABBBFC0D10F6D1CCF694842FAD9D631B6B2B119` | same declared value | registry content identical |
| `assets/data/equipment_granted_skills.source.json` | 1,116 bytes; SHA256 `E9B0783FB9EAF9572F38188B5ABBBFC0D10F6D1CCF694842FAD9D631B6B2B119` | 1,152 bytes; SHA256 `EBDDCB09420627BF2544AB8693E6903284127A839D5388024F0EC0DC38E0FADB` | isolated actual bytes do not satisfy the registry declaration |

The correct missing overlay dependency is exactly `assets/data/equipment_granted_skills.source.json`, copied from the current MAIN working bytes. It was absent from the 56-path production/authoring overlay recorded in `WORKSPACE_PREP.md`; the price and registry JSON files themselves are present and byte-identical in both trees.

Other directly inspected runtime inputs were also byte-identical: `assets/data/equipment_price_candidates_v1.json` (24,878 bytes, SHA256 `7A5A5C2914FE7D2D56EA355B3465570A15B8A767D354734CBA4E5587241BEEBB`), `assets/data/service_item_catalog.json`, `assets/data/service_reference.json`, `assets/data/item_runtime_authority_v1.json`, `assets/data/merchant_catalog_v1.json`, `scripts/game_data.gd`, and `scripts/identity/entity_registry.gd`. The price file's `policyPath` is `assets/data/source_priority_policy.json`; that file is byte-identical (22,403 bytes, SHA256 `58ADF6E75EEA5549C4A535098E568505408EFA621901A1DADB868798739AC3C7) and its embedded `policySha256` is historical evidence, not used by `_load_equipment_price_candidates` to decide owner identity.

## Current MAIN candidate check

A static check against the current MAIN runtime registry found 50 price records and 50 unique `entity_id` values; every `entity_id` resolves to a registry record. There were no unknown IDs, duplicate IDs, or declared numeric identity fields in the rows that could conflict (all rows contain only `entity_id` for identity). Thus this audit finds no current MAIN row-level unknown/conflicting/repeated condition. This is a source/JSON inspection only; it is not a Godot PASS and does not replace the required isolated rerun after the exact dependency overlay.

## Boundary / next action

Copy only the current MAIN bytes of `assets/data/equipment_granted_skills.source.json` into the isolated workspace and record the resulting hash in the run manifest. Do not substitute a stock/fixed107 price list, regenerate the registry, or relax the `EntityRegistry` source-hash guard. Until that copy and a later authorized run are recorded, the isolated preflight remains `BLOCKED` by the dependency mismatch; the current MAIN candidate data remains unproven by runtime execution (`NOT_RUN` in this audit).
