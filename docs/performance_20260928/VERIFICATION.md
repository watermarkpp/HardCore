# Astra 修复验证 — 2026-09-28

## 结论与身份

- 接管基线：`21b40ddae663997f8e9f267585988e6a7c63db6a`，主树 `codex/integration`。
- 本地定向/相关回归：**PASS，39 个不同场景**。逐项结果见 `evidence/latest_results.json`，保留中间 FAIL 的 runner 原始结果，不以中途 PASS marker 覆盖超时/退出状态。
- 验证代码身份：`evidence/verified_source_sha256_lf.json`（LF 规范化 SHA256）。测试分批按依赖执行；不是最终 HEAD 上重新跑完整 critical。
- 全量 critical：**NOT_RUN**，遵守用户“不重跑全部548项、修复失败和相关回归”要求。
- 新候选手机验收：**NOT_RUN**。本地耗时不等同于 Android 端到端流畅度。
- 用户最新要求改为完整 APK 放桌面。采用正式隔离构建、候选 versionCode 95（升级既有94），包名/签名/角色存档兼容保持。
- APK已于2026-09-29完成并复制桌面，固定源码7076bc465dbf7dc837381f267fa8eb9e151bf001；包内内容和签名验证PASS，详见 `APK_DELIVERY.md`。设备尚未安装，不将打包完成记为手机性能通过。

## 修复与覆盖

| 系统 | 修复 | 实际覆盖 |
|---|---|---|
| 物品使用 | 输入只改权威状态和标记待存；顺序后台写人物档，不等待世界时钟。失败提示、正常退出保存；不向实时状态回灌旧快照 | 20次连续使用、旧人物/世界写入重叠、自身写入期间再次使用、拾取同堆叠/最后一个物品、金币收据、重复收据、真实写失败恢复、药/油/书/神水/随机卷、退出 |
| 工作台 | 放入顺序不限，放错/多放也允许取出；合法组合和足够金币才启用按钮。放入/取出/正式结算走后台人物存档 | 材料优先、配方后选、错位、额外物品、数量、金币、重复报价、真实锻造/合成输出、与正在提交的拾取重叠、退出 |
| 仓库 | 准备阶段按已用CPU时间让出帧；最终日志/共享档/人物档由原有单通道后台提交；入口等待改为跨帧等待 | 500物品/100件批量存取、正常与失败回滚、共享金币、交易身份、回执生命周期、提交中切后台；仍保留双文件一致性 |
| UI 刷新 | 背包和仓库只重写变化格子的图文；选中态独立刷新，值快照防止原地修改漏刷新 | 不变格0次重写、单堆叠变化只更新1格、仓库/背包装备布局 |
| 八方向 | 人物输入按Ground GU量化；碰撞侧滑不产生离轴位移。怪物路线分合法八向腿，保留精确端点及完整脚印校验 | 32输入角度、碰撞斜墙、远坐标精度、两类怪物/八向/小数起点、真实多边形窄道、24自然追击、D3持续运动 |
| 镜头 | 每process帧仅积分一次指数平滑，保留地图边界、缩放，明确传送时复位 | 黑边预算、菱形边界、多个更新调用、长帧不越过目标、走跑回归 |
| 图标/loading | 圣物/徽章/碎片32px显示边界、仓库遵循显示尺寸；loading文字与全屏logo共中线 | 图标/仓库边界、配方预览、safe area文字中心、布局回归 |
| 战斗语义 | 未调整公式、RNG顺序、攻击准入/半径、事件或伤害延迟 | 受击硬直、中毒链、圣物运行时、技能/快速药槽；原始八向移动与镜头在手机仍待目测 |

工作台仍保留既有格子角色与二次点取回操作：锻造中央目标、上方黑铁、两侧首饰；合成0格为输出。用户要求的任意**先后顺序**已经实现，未把布局变成无角色格子。

## 可比性能证据

同一台Windows、headless、同一500物品/100件批量场景；完整JSON在 `evidence/warehouse_before.json` 和 `warehouse_after.json`。

| 操作轮次 | 改前最大帧间隔(ms) | 改后最大帧间隔(ms) | 改前完成耗时(ms) | 改后完成耗时(ms) |
|---|---:|---:|---:|---:|
| 存入1 | 86.317 | 19.547 | 250.209 | 272.667 |
| 取出1 | 95.950 | 22.247 | 266.803 | 279.300 |
| 存入2 | 109.178 | 24.468 | 281.572 | 303.516 |
| 取出2 | 115.049 | 24.938 | 292.670 | 292.834 |

结果是明显降低最长阻塞，**并未证明批量交易总完成时间缩短**；100件仍约0.3秒。普通单件的手机操作感受必须另验。不是通过少保存/少转移物品取得改善。

20次立即物品调用本地约1.37ms；40次工作台放取约8.25ms（整个循环，具体输出见原始日志）。这不包括GPU、触控和整套手机画面，不能据此声称所有长帧消失。

## 失败裁定

- 新增反例先出现真实生产 FAIL：同步物品写入、工作台同步等待、未变格重复刷新、仓库入口等待、偏轴移动/镜头重复积分；实现后相关测试通过。
- 施工中的 parser return、get_meta默认null报错、缺item_id、测试调用名拼写错误：已修复并重跑对应项。
- quick_item_slots旧预期4本书升3级与既有v2技能规则冲突：修fixture为3本，不改正式技能规则。
- relic_synthesis_runtime旧测试允许额外装备/第5碎片，与用户本轮“多放则按钮不亮”裁决冲突：改为明确拒绝额外物品、取回后才能合成，保留全部未消费物品断言。
- player_walk fixture在安全城镇用攻击火球与安全区规则冲突：改用真实自身魔法盾触发同一施法/移动约束，不改安全区。
- monster blocked fixture在ready前关闭物理处理被ready覆盖：移到ready后，生产节拍不变。
- 当前39项最后结果无FAIL，无timeout，无engine log errors；其余未执行场景不冒充通过。

## 保护与交付边界

- `assets/**`、`map_editor_workspace/**`、`project.godot`、`export_presets.cfg` 相对接管HEAD零diff；人工地图、脚点、技能素材、选取圈、基础数据保持。
- 既存dirty `AGENTS.md`、`tests/cangyue_area_test.gd` 和无关未跟踪内容保留且不进入本轮提交。
- 不读取覆盖手机存档，不回放旧备份；没有录屏/截图。
- 新增稳定物品/技能ID：无。无新存档schema；后台队列修订号仅运行时存在。
- 本轮未自动push；完整APK用固定提交构建。最终路径/签名/哈希及包内证据另写 `APK_DELIVERY.md`。

## 复现命令

通过 `tools/run_godot_tests.ps1 -TestPaths @(...) -TimeoutSeconds 30` 分批执行；完整实际集合在latest_results.json，不是泛写测试计划。代表命令：

```powershell
& .\tools\run_godot_tests.ps1 -TestPaths @('tests/immediate_item_save_test.tscn','tests/f03_periodic_background_save_test.tscn','tests/f03_pickup_receipt_lifecycle_test.tscn','tests/f03_workbench_receipt_boundary_test.tscn') -TimeoutSeconds 30
& .\tools\run_godot_tests.ps1 -TestPaths @('tests/repair_20260913/warehouse_prepared_transaction_test.tscn','tests/f03_warehouse_receipt_boundary_test.tscn','tests/warehouse_gothic_ui_test.tscn','tests/hidden_inventory_refresh_test.tscn') -TimeoutSeconds 30
```

## v94后热补丁继承

上一补丁v94-loading-save-forge-21b40dda-slim：APK基线4123abdc99388ec3fe83776f9b3e7029b14428d1，补丁源码21b40ddae663997f8e9f267585988e6a7c63db6a。两者祖先核验均PASS。六项脚本与旧manifest逐项一致，旧manifest已存evidence。新APK从21b40ddae之后的提交构建，包含原补丁。device_lab_patch_bootstrap_test追加PASS，实际创建旧PCK验证新build_info拒绝挂载并清理旧补丁，角色档不参与清理。
