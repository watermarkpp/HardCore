# HardCore Current Status

Updated against consolidated main-tree anchor: `550b1cf5`
Branch: `codex/integration`
Updated: 2026-08-29
Purpose: where the project stands right now.

## 2026-09-06 复活后怪物视觉与经验/音乐跟进（最新）

- 源码 `571db0bc`：同图死亡回城保留怪物视觉 generation/订阅，真实跨图隔离不变；死亡扣本级总升级门槛 10%（封顶已有经验），主城音乐默认音量 70%。未修改地图、AI、怪物数量或已批准升级动画。
- 最终源码专项 3/3 PASS、0 engine errors；最小累计热补丁 1,445,316 bytes / 13 项，无删除项，独立基包加载通过。手机已加载精确最终 patchId/SHA，loadError 为空，存档保留。
- 启动后比奇 82 个视觉注册，屏幕内 6 个活怪正常显示；实机死亡回城后再接近怪物仍待用户验收。完整根因、包身份及证据见 `docs/hotfix/20260905/FOLLOWUP.md`。

## 2026-09-05 经验与城镇音乐 hotfix（前一版）

- 源码 `0abc83e9`：经验门槛 10%、经验条横跨四快捷物品槽、一次成功结算仅一次升级动画、技能音效关闭、主城安全区 Loading 后 10 秒一次背景音乐。用户已批准 75% 光焰及人物前后遮挡视觉。
- 干净源码专项 7/7 PASS。最小补丁 `hotfix-20260905-xp-town-minimal` 为 1,404,188 bytes，SHA-256 `1643D8D05276D4DF45A823697645173C6D27A654C37B60238F024086BA501434`；独立基包+补丁加载验证通过。
- 手机已安装精确里程碑 APK70；本次只原子替换旧补丁，备份并保留存档。手机运行回执已确认新 patchId/SHA，loadError 为空。玩法及音乐听感等待用户实测，不宣称全部手动验收完成。详见 `docs/hotfix/20260905/DELIVERY.md`。
- 首次全量导出夹带无关资源和两个删除项，被安全检查拒绝、未安装；最终仅 12 项精确闭包，无删除项。主树交付记录保留失败与成功证据。

## 2026-09-05 审计里程碑（历史基包记录）

- 审计修复及 APK 构建完成：构建提交 `52ae0565856c2d99a28639b2bf0c6278186e0858`，版本 `70 / 1.19.0-audit-milestone`。桌面文件 `HardCore-20260905-audit-milestone-debug.apk`，大小 449,193,057 bytes，SHA-256 `26584B871F61B2F6EC2DDDAF52432263E7D68A6B8BEA35B2A3196D59D5B21664`。证据见 `docs/audits/20260905/MILESTONE_APK.md`。
- 全量 critical 295/298 PASS；余下三项在干净构建提交独立复验 3/3 PASS，正常退出且错误计数为 0。不是一次 298/298 全绿。签名、build-info、运行时资源与实际构建目录的 67 图/208 纹理闭包通过；126 项 CRLF 检出字节差异逐项证明无内容漂移，原始 FAIL 记录保留。
- 用户已拔手机，要求回来再安装：本包未安装、未做新版本实机验收，手机存档/补丁未改动。后续只用精确 SHA 包安装并复核三职业 40 级赤月档案。
- 主树及标签 `milestone-20260905-audit-upgrade` 已同步并核对；标签固定 APK 源 `52ae0565`，主树后续含交付文档证据。13 个旧/临时构建工作树已在远端核对和归档后移除，两次磁盘采样净增 52,050,092,032 bytes（约 48.475 GiB）；源提交、重要包/日志及共享工具保留。详见 `docs/audits/20260905/CLEANUP_COMPLETED.md`。
- 已人工验收的怪物密度性能基线 `c97a08b43832b174f98de31f5ed6673ccda344ae` 已归入 `codex/integration`。该基线不是本轮全部审计通过证明。
- 当前工作树、专业领域、冻结保护与代理调度以根目录最新 `AGENTS.md` 为准。下文旧“只在主树修改”是历史阶段记录，不否定本轮由 integration 明确分配的隔离专项树。
- 下文旧 PASS、旧 APK 和旧标签仅作历史证据，不代表当前 HEAD 验收结果。本轮源码构建锚点与后续证据文档提交分开记录，文件变化必须以实时 Git 为准。

## Current HEAD

Use annotated tag `standard-20260829-main-tree` for the immutable consolidated standard. Formal runtime/map baseline is `00f6e5e6525a4a07679b41eb482a2cfd05fdd068`.

## Current Stage

**MAIN TREE CONSOLIDATION CLOSED / DEVICE ACCEPTANCE CONTINUES**

## 2026-08-29 Main Tree Standard Freeze

- 地图、怪物、装备、职业、UI、地图编辑器、素材编辑工具和校准器已按提交与工作副本双层筛查，正式内容统一收口到 `codex/integration`。
- DeepSeek/DSH 工作树的正式地图编辑器、footprint 校准、XZSC 素材导入/校准及怪物编辑器成果均已在正式历史中；未倒灌中间版本和旧 217 怪 Authority。
- 所有仍有历史价值但不应启用的 WIP、候选数据和校准证据均已保存到远端 `archive/*-20260829` refs。
- 以后正常修改只在主树完成；临时工作树验收并合入后立即删除。可热修内容继续通过补丁进入 APK，超出热修边界的重大修改重新打包。
- 完整证据与恢复点见 `docs/handoff/2026-08-29/MAIN_TREE_STANDARD_FREEZE.md`。

## Historical 2026-08-10 Foundation Audit Closure

## 2026-08-10 Foundation Audit Closure

- 全项目按 UI/数据、地图发布、职业战斗、核心世界/存档四个互斥范围完成 Sol high/xhigh 审计、修复和集成；Monster Streaming 继续遵守既有 `HOLD`，未修改冻结生产实现。
- 关闭的主要缺陷：安全退出误报成功与坏档无备份恢复；canonical 资源提交/召唤 descriptor 丢失；玩家和召唤物死亡重复结算；投射物重复建立释放快照；地图候选跨文档发布、registry 非 fail-closed、显示名覆盖；HUD 出售/任务放弃/仓库排序无权威消费者；仓库上限与弹窗布局；12 个女性盔甲主表缺失；Android build-info/dirty/编译脚本验证不完整。
- 正式关键回归：`critical = PASS 250/250`，`failed=0`，`engine_log_errors=0`；来源优先级、资源完整性、测试注册、Python AST、PowerShell 解析全部通过。
- 固定 APK runtime commit：`58db719671c15a126fde67733745e1a84ccee3a9`。
- 桌面 APK：`C:/Users/Administrator/Desktop/HardCore-20260810-foundation-audit-debug.apk`；`245,014,120` 字节；SHA-256 `E673181750303DD189F7ABFF32679B882EE46DDD0321159BDC3809F1EE978AA1`。
- Android 验证：`versionCode=64`、`versionName=1.18.1-spatial-projection`、`HardCore`、`com.personal.mafaoffline`、`arm64-v8a`、minSdk 24、targetSdk 36；APK v2/v3 签名、12 个编译脚本、运行时资源探针和 build-info commit 全部通过。

## Active Wizard Line Presentation Alignment

- `WIZARD-LINE-PRESENTATION-ALIGNMENT = DEVICE_ACCEPTANCE_PENDING`
- Professional implementation commit: `14bb52f5`（merged into integration as `348b6809`）
- Formal design: Hellfire / Laser use target-aligned continuous canonical geometry; Presentation consumes the same release snapshot and must not quantize Gameplay to character or source-art directions.
- Automated verification:
  - focused arbitrary-angle alignment: `PASS`（Hellfire 126 samples + Laser 126 samples）
  - `wizard_line_geometry_critical`: `PASS / 3_OF_3`
  - related caster visual tests: `PASS / 4_OF_4`
  - suite registration guard: `PASS`
- Single authorized default Critical run: every completed entry before the outer 900-second command cutoff passed, including `wizard_line_geometry_critical`; no final runner JSON / `TEST_SUMMARY` was produced, so this is `PARTIAL`, not a formal full-Critical PASS. Do not rerun automatically.
- Gameplay origin / axis / length / width, lock-on, target selection, damage and Geometry Debug Band were not modified.
- Final closure requires a newly exported Debug APK and device visual acceptance.

## Confirmed Production Blockers

`confirmed_production_blockers = 0`

## New Must-Fix

`0`

## Hellfire Damage Regression Fix

- `known_unverified_production_regressions = 0`
- `HELLFIRE_CANONICAL_TARGET_REGRESSION = FIX_IMPLEMENTED`
- User-visible symptom confirmed: Hellfire animation and geometry released, but no target received damage.
- Root cause: the canonical target selector interpreted production `maximum_targets = 0` as an empty target set before applying the explicit `target_limit_policy = all_intersecting_effect_cells` contract.
- Fix commit: `13821799fced2fee0d50c27d89bba3149464077f` (`fix(skills): restore hellfire line damage`).
- Automated verification:
  - production-effect regression reproduced before fix and passed after fix: `PASS / 1_OF_1`
  - wizard canonical/runtime/lock integration: `PASS / 3_OF_3`
  - `wizard_line_geometry_critical`: `PASS / 3_OF_3`
- `HELLFIRE_DAMAGE_DEVICE_ACCEPTANCE = PENDING`

## Closed Recent Bugs

- B030 = `CLOSED`（PassiveProcSkillEffect actor 平面）
- B038 = `CLOSED`（Skill Panel AssignmentHint 溢出）

## Test Infrastructure Debts

- B004 = `CONFIRMED_TEST_INFRA`
  - `production_touch_scroll_works=true`
  - `old_test_calls_disabled_path=true`
  - 旧测试调用了被 `STABLE_ID` 策略禁用的 `launcher._input` 路径。
- B037 = `CONFIRMED_TEST_INFRA`
  - `InventoryScroll` 存在于真实 HUD 树且触摸有效。
  - 旧测试只扫描 `MobileSafeRoot`，漏掉 HUD 根子节点。

## Runner Allowlist Gate Closure

- `RUNNER ALLOWLIST GATE = CLOSED`
- 关闭提交：`9a174d14015268e570bf687ddf3e14aad440f314`（`fix(test): harden runner allowlist contract`）
- public suites：23
- runner identity isolation：`PASS`
- `TestPaths`：`adhoc only`
- timeout hard range：`1..60`
- `monster_streaming_critical` direct suite remains available。
- `monster_streaming_critical` excluded from default critical while `HOLD`。
- formal suite smoke：`player_visual_contract_critical = PASS / 1_OF_1`
- `confirmed_runner_blockers = 0`
- registration guard remaining weakness：`NON_BLOCKING_TEST_INFRA_DEBT`

## Monster Streaming Historical Evidence

- apply-order 历史记录：20-run evidence 17 PASS / 3 FAIL。
- 当前状态：
  - `HOLD`
  - `NOT_NEXT_GATE`
  - `NOT_ACTIVE_MUST_FIX`
  - `20_RUN_NOT_AUTHORIZED`
  - `PRODUCTION_CHANGE_NOT_AUTHORIZED`
- 该状态不是 `CLOSED`；它只暂停执行，不否认历史现象。

## Environment Noise

- Orc Tomb headless dummy renderer shutdown：20/20 standalone PASS；批跑偶发关闭期 RID 噪声。

## Next Verification

- `NEXT_VERIFICATION = FOUNDATION_APK_DEVICE_ACCEPTANCE`
- `STATUS = DESKTOP_APK_READY_FOR_MANUAL_ACCEPTANCE`
- 使用 2026-08-10 桌面 APK 复验战斗、存档、地图发布、装备性别门禁、商店出售、任务放弃、仓库排序，以及既有 Wizard Line / Hellfire 实机表现。

## Pending Freeze Quality Gates

1. `NEXT_FREEZE_QUALITY_GATE = WORLD_ACTOR_SPAWN_PERFORMANCE` — `NOT_STARTED`
2. Final G1 audit — `NOT_STARTED`
3. Android device acceptance — `NOT_STARTED`

用户当前已暂停全部 Freeze 工作；上述 verification 与 quality gates 均未开始。

## Do Not Work On

- 未制作地图内容（338 等）
- 未来 MSE 功能
- B004/B037 生产代码（两项均已确认是测试基础设施问题）
- GameRoot 拆分
- 坐标重新设计
- Snapshot 重新设计
