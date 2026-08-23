# APPROVED_APK_PROVENANCE_REPORT (2026-08-17)

> 依据用户明确事实重建：最终验收 Debug APK **不是**单一 Git commit 直接构建，
> 而是 BASE_COMMIT + 多轮 HOTFIX（UI 热修施工）组合产物。

## 一、APK 身份

| 字段 | 值 |
|---|---|
| APPROVED_APK | `HardCore-1.18.3-runtime-fix-9d6435bc-debug.apk` |
| APPROVED_APK_PATH | `outputs/hardcore/HardCore-1.18.3-runtime-fix-9d6435bc-debug.apk` |
| APPROVED_APK_SHA256 | `B74F58FC1E17A28D2A0FAE7E709085E410F4C48FF6141DD6C293596DDEF341CB` |
| APK_BUILD_TIME | 2026-08-15 11:57:00 +08:00 |
| APK_SIZE | 273,784,115 bytes |
| 提取基准 PCK | `outputs/device_lab_patches/base_full_9d6435bc_from_apk.pck` (SHA256 F34F09A5...) |
| APK 内资源提取 | `outputs/device_lab_patches/apk_assets_9d6435bc/` (7,139 files, .gdc compiled) |

## 二、BASE_SOURCE

| 字段 | 值 |
|---|---|
| BASE_SOURCE_COMMIT | `9d6435bced2c27294cdabd362ceadc8cc322f89b` |
| BASE_SUBJECT | test(startup): isolate background scene preload |
| BASE_BRANCH | codex/integration（现已并入 origin/main） |
| BASE_WORKTREE | 主工作树 HardCore（构建时刻） |
| 构建间隔 | commit 11:45 → APK 11:57（12 分钟） |
| PUSH 状态 | 已 push origin/main（`git branch -r --contains` 证实） |

## 三、HOTFIX 施工链（32 个正式 PCK hotfix，全部含 UI 资源）

> 证据：`outputs/device_lab_patches/*.json` 每个记录 baseCommit + patchCommit + resources 清单；
> 所有 patchCommit 均可在 git 解析并已 push origin/main。

### 施工段（按时间）

| 阶段 | 时间 | patchCommit | 主题 |
|---|---|---|---|
| 早期 UI 累积 v1-v11 | 08-13 15:35 → 08-14 11:47 | 54590273, 0fceaf66, ea5fd521, a3aa267d, 09ed417a, f6fa0b5f, 7c08edcd, b8d1a2ea, 66cbbb49, 3b219b83, 37756dc8, 612c05a5 | shop/warehouse/skill/map UI |
| basepack | 08-14 21:45 | 5b7efca9 (base=5bd099da) | repair batch / startup hud repair |
| 深夜热修 | 08-14 23:45 → 08-15 02:12 | fad30fbc, 0af855db, bd7b6efc, 95373da9, f17b0be6, 4f03902d, 6a2e0b33, a9a98b3b | startup/HUD/theme/inventory |
| 冷启动修复 | 08-15 11:30 → 11:45 | 1e5228c8, 9d6435bc | cold prewarm + APK build commit |

**APK 内 UI 最终版本 = 9d6435bc 时刻**（13 个关键 UI 脚本全部在 hotfix 链内被修改过：hud/game_root/game_data/inventory_panel/gothic_ui_theme/character_select/brand_intro/adaptive_button_style_box/player_state/world_bootstrap_coordinator/startup_loading/pricing_service/device_lab_runtime）。

## 四、APK 之后（post-APK）继续施工

APK 后 main 新增 23 个 commit：**monster 系统 17 个**、world-ui 热修 5 个（dd17716e/c1a60bcb/d148e2a1/59724524）、npc/map-editor 2 个。

| 文件 | post-APK 修改 commit | 性质 |
|---|---|---|
| scripts/game_root.gd | a91bc586 | monster 权威（APK 后） |
| scripts/game_data.gd | a91bc586 / 5c1e6697 / 7bbb4bbc | monster 权威/掉落（APK 后） |
| 其余 UI 脚本 | 无 post-APK 修改 | APK 内版本 == main 版本（除上述） |

## 五、FINAL_APK_ONLY_OR_DIFFERENT_RESOURCES

- UI 资源（assets/ui + scenes + branding + project.godot）：APK 提取 111 项，**main 全部存在**（APK_ONLY=0）。
- 差异仅在内容版本：APK 使用 9d6435bc 时刻；main 的 game_root.gd/game_data.gd 被 post-APK monster commit 修改。
- 结论：**无 APK-only 资源丢失风险**；UI 主体版本可从 origin/main（已含全部 hotfix）重建。

## 六、结论

- APPROVED_APK = BASE_COMMIT 9d6435bc + 32 轮 hotfix（31 轮在其之前）+ 提取验证 base_full PCK。
- 所有 hotfix commit 均已 push origin/main；UI 资源全部在 main 中可恢复。
- monster 系统是 APK 之后继续施工的有效工作（17 commit）。
- 详细结构化数据：`outputs/APPROVED_APK_PROVENANCE.json`