# Golden Runtime Authority

## APK 身份

| 字段 | 值 |
|------|-----|
| FILE | `outputs/hardcore/HardCore-1.18.3-runtime-fix-9d6435bc-debug.apk` |
| SHA256 | `B74F58FC1E17A28D2A0FAE7E709085E410F4C48FF6141DD6C293596DDEF341CB` |
| SIZE | 273,784,115 bytes |
| VERSION | 1.18.3 |
| BUILD_TIME | 2026-08-15 11:57:00 +08:00 |
| BASE_COMMIT | `9d6435bced2c27294cdabd362ceadc8cc322f89b` |

## Hotfix 链

- 32 个正式 PCK hotfix
- 0 个包含怪物数据
- 覆盖范围：UI/HUD/商店/仓库/技能面板/地图标签/启动CG/冷启动
- 所有 hotfix commit 均已 push 到 origin/main

## 怪物运行时数据

| 文件 | 记录数 |
|------|:---:|
| monster_animation_catalog.json | 214 |
| monster_ground_contacts.json | 214 |
| monster_ground_contact_calibrations.json | 214 |
| monster_ground_alignment_manual_v1.json | 212 (+ 2 airborne) |
| monster_overhead_anchors.json | 214 |
| complete_monster_client_art_sources.json (CMAS) | 143 条怪物记录 (290 grep 行) |
| bich_common (含 contentBounds+drawOffset) | 22 |
| bich_undead (含 contentBounds+drawOffset) | 11 |
| classic_boss | 6 |

### 143 vs 290 解释
- 143 = 不同怪物记录数（runtimeMappingsByMonsterId 条目数）
- 290 = grep "footAnchor" 行数（143 × 2 平行索引段 + 4 lockedUserGeometry）
- 两者不矛盾，是不同统计口径

## 投射策略分布
- grounded: 202
- flying: 9
- hover: 3

## 美术资源
- 6 顶级目录, ~113 怪物动画子目录
- 全部拥有完整 5 动作集 (idle/walk/attack/hit/death)

## 提取位置
- 基准 PCK: `outputs/device_lab_patches/base_full_9d6435bc_from_apk.pck`
- 资源提取: `outputs/device_lab_patches/apk_assets_9d6435bc/` (7,139 files)
