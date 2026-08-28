# DPV2-SPB-1 Single-Player ×25 Drop Boost Report

Status: `CLOSED`

Baseline commit: `98ea003b66915622b5c265602e54386f9213016c`

## Outcome

DPV2-SPB-1 adds an independent exact-rational probability overlay above the
unchanged DPV2 direct baseline. Production selects the overlay only while SPB
is enabled and the global drop preset is exactly `1x`. Disabling SPB selects
the mirrored base rational and then applies the global scale exactly once.

Gold probability remains a base-probability bypass. Independently, enabled SPB
multiplies the amount of every successful Gold reward by exactly `10/1`;
disabling SPB restores the frozen Direct Baseline Gold amount.

The production RNG still rolls every resolved source slot independently before
the existing protected/priority overflow selection and nine-ground-slot cap.

## Production configuration

- `enabled = true`
- multiplier: `25/1`
- AUTO ceiling: `1/20`
- Gold reward-amount multiplier: `10/1` (probability remains bypass/base)
- required enabled-mode global preset: `1x` (`1/1`)
- Production slots/effective records: `6809`
- Direct profiles: `156`
- Drop-enabled profiles: `144`
- New-armor Boss manual exclusions: canonical monster IDs `235..240`
- Monster `225` is not a new-armor Boss exclusion.

## Exact classification counts

The mutually exclusive effective policy partition is:

| Effective policy | Slots |
| --- | ---: |
| `AUTO_BOOST` | 4537 |
| `BYPASS_COMMON_RECOVERY` | 1357 |
| `BYPASS_GOLD` | 128 |
| `BYPASS_NEW_ARMOR_BOSS` | 324 |
| `BYPASS_UNCLASSIFIED` | 463 |
| Total | 6809 |

The full audit populations intentionally overlap the whole-Boss exclusion:

| Audit population | Slots |
| --- | ---: |
| Common recovery | 1597 |
| Gold | 134 |
| New-armor Boss | 324 |
| A07 equipment | 4311 |
| A07 rare consumable | 268 |
| Fail-safe unclassified candidate | 499 |
| Blessing Oil (`920033`) | 22 |

The 499 unclassified candidates are 439 skill-book slots, 2 Boss-key slots,
10 material slots, and 48 Return Scroll/Warrior Oil slots. Boss precedence
places 36 of those candidates into `BYPASS_NEW_ARMOR_BOSS`, leaving the 463
effective unclassified slots shown above.

A07 freezes 167 exact equipment IDs and 13 exact rare-consumable IDs into the
SPB authority. Functional-special ring IDs `253`, `254`, and `260` remain
equipment AUTO slots because their formal A07 item identity is `戒指`.

## Formula and anchor

The only AUTO formula is:

```text
if base >= 1/20:
    final = base
else:
    final = min(base * 25, 1/20)
```

All arithmetic is positive-integer rational arithmetic with GCD reduction.
The effective ledger reports 2203 ceiling-applied slots.

The production experience anchor is the real slot:

```text
monster: 135 白野猪
slot_uid: dpv2.direct.m135.slot_124
item: 105 裁决之杖
base: 1/5000
SPB effective/final: 1/200
policy: AUTO_BOOST
```

## Probability distribution

All 6809 slots, before and after the production SPB overlay:

| Probability band | Base | SPB effective |
| --- | ---: | ---: |
| `>= 1/20` | 2295 | 4939 |
| `1/21–1/50` | 537 | 930 |
| `1/51–1/100` | 789 | 335 |
| `1/101–1/200` | 519 | 162 |
| `1/201–1/500` | 1286 | 281 |
| `1/501–1/1000` | 755 | 66 |
| `1/1001–1/5000` | 531 | 66 |
| `1/5001–1/10000` | 86 | 24 |
| `< 1/10000` | 11 | 6 |
| Total | 6809 | 6809 |

## Runtime fail-closed behavior

GameData loads and validates both SPB authorities, validates all source/hash
bindings, mirrors every immutable Direct Baseline field, checks the exact
formula for all 6809 records, and builds a `slot_uid` index.

Production rejects unresolved, missing, duplicate, mismatched, malformed, or
wrong-monster SPB records. LootRuntime resolves all slots before the first RNG
draw, so these failures and enabled-SPB/non-`1x` global conflicts consume zero
RNG draws. Runtime name/tier/fuzzy classification is not used.

Attempts expose base, table-effective, selected source, boost policy/reasons,
multiplier, ceiling, global scale, final rational, provenance, protected flag,
overflow priority, draw, and post-RNG overflow outcome.

## Immutable and probability gates

| Gate | Result |
| --- | --- |
| 21CQ source drift | 0 |
| Direct baseline raw/semantic drift | 0 |
| Base probability drift | 0 |
| Slot UID drift | 0 |
| Reward identity drift | 0 |
| Provenance drift | 0 |
| Protected/priority/origin drift | 0 |
| Duplicate slot collapse | 0 |
| Effective base mirror mismatch | 0 |
| Probability decreases | 0 |
| Ceiling violations | 0 |
| Boost formula mismatch | 0 |
| Bypass probability mismatch | 0 |
| Disabled-mode mismatch | 0 / 6809 |
| Gold probability mismatch | 0 / 134 |
| Gold enabled amount mismatch (`base ×10`) | 0 / 134 |
| Gold disabled amount mismatch (`base`) | 0 / 134 |

Frozen raw SHA-256 values:

```text
canonical_monster_drop_source_v2.json
59338A7E5CAACCC82661E942908CAEA0A4A06CF56402961E4C3E55FB123E4013

dpv2_direct_baseline_v2.json
9E9225DF113BDC94ECDA071388DC5FCFA92ED34BF8028519B06F205E06FF4DD0

dpv2_21cq_source_provenance_v1.json
F48A033D5A33D80B795A838BE837AE84FA93469B6055FE012309ACC07082E347
```

Full immutable 6809-slot ledger SHA-256:

```text
057F3664C2CE5376B2A937CB317E978769860AA1B3390D0EF038B512CD496B80
```

## Verification

- Existing R1 final gate: `DPV2_FINAL_GATE_PASS blocker_count=0`
- SPB builder `--check`: PASS
- SPB Python tests: `25 passed`
- SPB Godot runtime test: `1 passed`, `0 failed`, `engine_log_errors=0`
- Existing Direct runtime regression tests remain PASS.
- Fresh P1A, P1A audit, world integration, and engine-log acceptance are
  executed by the unchanged R1 final gate before the SPB-specific gates.
- Final SPB gate: `DPV2_SPB_FINAL_GATE_PASS blocker_count=0`

## Required closure answers

```text
21CQ原始数据是否修改？
NO

6809槽base probability是否修改？
NO

原始槽UID是否修改？
NO

原始奖励身份是否修改？
NO

×25是否作为独立层实现？
YES

是否可以一键关闭并恢复原版？
YES

disabled mismatch？
0

普通恢复药是否提高？
NO

Gold概率是否提高？
NO

Gold数量是否提高？
YES ×10

新衣服Boss是否提高？
NO

正常装备是否×25？
YES

稀有功能消耗品是否×25？
YES

自动概率是否超过1/20？
NO

R1是否回归？
NO
```
