# DPV2 A0.6 Item Tier Decision Package

## Status and scope

`WAITING_HUMAN_AUTHORITY` for all eight rows. This package is an evidence package only: it does not assign a final Tier, change the 7032-slot drop closure, or activate a production denominator.

- Base requested by controller: `041343432ec8e4e7960aded9524a1c146a23241a`
- Live branch during authoring: `codex/integration`
- Live HEAD observed: `ca4908b1ea3dc6d4a75dd081b18dc28960570c7b`
- Current canonical closure: 156 monster identities, 7032 item/gold slots, 238 raw item tokens, 233 canonical unique items
- A0.6 identity authority: `assets/data/drop/dpv2_item_identity_authority_v1.json` (`A0_6_COMPLETE_ITEM_IDENTITY_ONLY`); it assigns identity only, not Tier
- V1 workbook role: `V1 DROP DESIGN BASIS` only; it is not monster identity authority

No existing authority, catalog, runtime, drop, map, or A0.5 file was edited.

## Source and validation evidence

| Source | Use | SHA-256 |
|---|---|---|
| `C:\Users\Administrator\Downloads\HardCore_怪物变体与掉率母版_V1_审核稿.xlsx` | V1 DROP DESIGN BASIS | `BC64C096528D43E314CB5E01446F15DB53418C0AD10A7A66497FC4DB66C3418C` |
| `assets/data/runtime/canonical_monster_catalog.json` | current canonical monster/drop closure | `742C939875DD4CB14203C03056C386B1AD57FF9A9359F92B996160E07BA9E32D` |
| `assets/data/service_item_catalog.json` | exact service item identity and metadata | `DB61781AD87853A3169AFF491A1AF8336884B4BE0D34FF13145C703713DA44B2` |
| `assets/data/equipment_attribute_master.json` | item-master exact-match check | `223C96DF954077AA8970A277EFE229D9DBC16609D2503A0033E60197F7E00701` |
| `assets/data/drop/dpv2_item_identity_authority_v1.json` | A0.6 canonical item identity authority; identity-only, production inactive | `C2F2F7E2803C7E54C5C096726D14B0E6730CC517DC3D20EE33F0D45BB0E4761C` |

V1 search covered all sheets and searched both canonical and legacy raw tokens. There are zero exact item or group hits for these eight materials. Relevant no-hit design ranges are:

- `03_物品掉率母版` rows 3-29
- `04_未知暗殿掉落迁移` rows 3-9
- `06_关键装备覆盖` rows 3-22
- `07_平滑概率矩阵` rows 3-14
- `08_倍率模拟` rows 3-14

Validation performed:

- exactly 8 unique unresolved canonical names
- exactly 8 exact service-catalog name matches
- exactly 8 explicit canonical-ID records in the A0.6 identity authority
- zero exact `equipment_attribute_master` matches
- exactly 12 current source slots across the eight items
- every row has at least one canonical-drop evidence pointer and source reference
- every row has `mapping_basis=UNRESOLVED`, null V1/DPV2/effective denominator, and `authority_disposition=WAITING_HUMAN_AUTHORITY`

## Candidate policy

The candidates below are not assignments. `FUNCTIONAL_SPECIAL` is the only V1 bucket that can plausibly contain a non-combat functional/material-like reward, while `COLLECTOR_LOW` is a lower-value non-combat alternative. Neither is supported by a V1 exact item/group hit. `POTION_*`, equipment tiers, and skill-book tiers are rejected for these rows because the authoritative service kind is `material` and `useEffect=none`.

No name-only inference is used. Service `kind`, `category`, stackability, price, and the canonical monster/slot context are recorded as evidence, not as a final rarity decision.

## Unresolved matrix

| canonical ID | canonical key | service index | canonical name | type/category | current drops | slot/chance summary | plausible candidates | blocker | disposition |
|---|---:|---|---|---|---|---|---|---|
| 920023 | `service:870` | 870 | 沃玛号角 | material / 制作材料 | 76 沃玛教主 (boss) | 1 slot: 1/4 | `FUNCTIONAL_SPECIAL` (14400), `COLLECTOR_LOW` (1200) | V1 has no material row or item/group hit; boss source does not prove Tier | `WAITING_HUMAN_AUTHORITY` |
| 920032 | `service:871` | 871 | 祖玛头像 | material / 制作材料 | 160 祖玛教主 (boss) | 1 slot: 1/1 | `FUNCTIONAL_SPECIAL` (14400), `COLLECTOR_LOW` (1200) | V1 has no material row or item/group hit; boss source does not prove Tier | `WAITING_HUMAN_AUTHORITY` |
| 920037 | `service:855` | 855 | 肉 | material / 肉类 | 96 羊, 100 狼 (ordinary) | 4 slots: 1/1 + 1/10 per monster | `FUNCTIONAL_SPECIAL` (14400), `COLLECTOR_LOW` (1200) | V1 has no material row or item/group hit; ordinary source does not prove Tier | `WAITING_HUMAN_AUTHORITY` |
| 920038 | `service:872` | 872 | 蛆卵 | material / 制作材料 | 46 洞蛆 (ordinary) | 1 slot: 1/5 | `FUNCTIONAL_SPECIAL` (14400), `COLLECTOR_LOW` (1200) | V1 has no material row or item/group hit | `WAITING_HUMAN_AUTHORITY` |
| 920039 | `service:868` | 868 | 蜘蛛牙 | material / 制作材料 | 18 毒蜘蛛, 185 剧毒蜘蛛 (ordinary) | 2 slots: 1/3, 1/2 | `FUNCTIONAL_SPECIAL` (14400), `COLLECTOR_LOW` (1200) | V1 has no material row or item/group hit; canonicalization is identity-only aliasing | `WAITING_HUMAN_AUTHORITY` |
| 920040 | `service:873` | 873 | 蝎尾 | material / 制作材料 | 45 蝎子 (ordinary) | 1 slot: 1/1 | `FUNCTIONAL_SPECIAL` (14400), `COLLECTOR_LOW` (1200) | V1 has no material row or item/group hit; canonicalization is identity-only aliasing | `WAITING_HUMAN_AUTHORITY` |
| 920049 | `service:866` | 866 | 食人花叶 | material / 制作材料 | 30 食人花 (ordinary) | 1 slot: 1/1 | `FUNCTIONAL_SPECIAL` (14400), `COLLECTOR_LOW` (1200) | V1 has no material row or item/group hit; canonicalization is identity-only aliasing | `WAITING_HUMAN_AUTHORITY` |
| 920050 | `service:867` | 867 | 食人花果 | material / 制作材料 | 30 食人花 (ordinary) | 1 slot: 1/5 | `FUNCTIONAL_SPECIAL` (14400), `COLLECTOR_LOW` (1200) | V1 has no material row or item/group hit; canonicalization is identity-only aliasing | `WAITING_HUMAN_AUTHORITY` |

## Service metadata

The eight rows have no exact record in `equipment_attribute_master.json`; their service records are exact and primary in `service_item_catalog.json`.

| key | service type | grade/set | required class/gender | shape | weight | durability | max stack | price | stackable | use effect | art |
|---|---:|---|---|---:|---:|---:|---:|---:|---|---|---|
| `service:870` 沃玛号角 | 16 | 0 / 0 | 31 / 3 | 0 | 1 | 0 | 1 | 1000000 | false | none | exact, image 261 |
| `service:871` 祖玛头像 | 16 | 0 / 0 | 31 / 3 | 0 | 1 | 0 | 1 | 500000 | false | none | exact, image 271 |
| `service:855` 肉 | 15 | 0 / 0 | 31 / 3 | 0 | 3 | 10000 | 1 | 200 | false | none | exact, image 1 |
| `service:872` 蛆卵 | 16 | 0 / 0 | 31 / 3 | 0 | 1 | 0 | 100 | 500 | true | none | exact, image 252 |
| `service:868` 蜘蛛牙 | 16 | 0 / 0 | 31 / 3 | 0 | 1 | 0 | 100 | 100 | true | none | exact, image 253 |
| `service:873` 蝎尾 | 16 | 0 / 0 | 31 / 3 | 0 | 1 | 0 | 100 | 100 | true | none | exact, image 254 |
| `service:866` 食人花叶 | 16 | 0 / 0 | 31 / 3 | 0 | 1 | 0 | 100 | 100 | true | none | exact, image 255 |
| `service:867` 食人花果 | 16 | 0 / 0 | 31 / 3 | 0 | 1 | 0 | 100 | 600 | true | none | exact, image 256 |

## Authority decision required

For each row, Human Authority must choose one of:

1. Add an explicit canonical material Tier and denominator/override to the DPV2 authority; or
2. Mark the material as a deliberate non-Tier/quest-material class with an explicit runtime policy.

Until that decision exists, preserve the explicit canonical item ID, exact service index, and canonical alias; do not infer a Tier from identity, do not default to `COMMON`, and do not calculate an effective denominator.
