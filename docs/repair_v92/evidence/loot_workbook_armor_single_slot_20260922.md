# 当前地图怪物真实掉率：衣服单槽修正版

状态：PASS。2026-09-22 根据已切换并通过主控生产专项的正式 authority 和最新生产查询快照重生成。新版另存桌面，旧版文件原样保留。本工作未运行 Godot，未修改 compiler、生产源码、掉落 authority 或地图数据。

## 交付文件与输入身份

- 桌面：`C:\Users\Administrator\Desktop\HardCore_当前地图怪物真实掉率_20260922_衣服单槽修正版.xlsx`
- 项目副本：`outputs/repair_v92/excel/armor_single_slot/HardCore_当前地图怪物真实掉率_20260922_衣服单槽修正版.xlsx`
- 大小：680723 bytes；桌面和项目副本 SHA-256 均为 `0B3140886CDF24BC298663CF8F512B33110A0315AED4471F36D8DAD2AC6F5826`。
- 正式 authority：`assets/data/drop/dpv2_user_loot_sheet_authority_v1.json`，SHA-256 `9F6E27418C742C9338CE4B60D752202E50549B48BBC2E066D91C760E6EF43B56`。
- 生产查询快照：`outputs/repair_v92/live_map_loot_authority.json`，SHA-256 `ABB474E32D2D5F37BBBF1932BE976208EAD7D577B95863A18C325E08E2BA66D5`。
- 单槽 directive：`tools/loot_sheet_compiler/evidence/armor_single_slot_directive_v92.json`，SHA-256 `7D6630C87EF5616655FCDEB3A1C873BEBD27BF9742C04C25A5CA032B52031A12`，与正式 authority 内记录相同。
- 分支 `codex/integration`，基线 HEAD `b961cedff8040c9fc81534e094241ad9fa2330ad`。工作树包含主控本轮修改，因此以上内容哈希才是本表的输入身份；基线 HEAD 不代表已包含全部修改。

旧桌面表 `HardCore_当前地图怪物真实掉率_20260922.xlsx` 的 SHA-256 仍为 `75C961CAE7B6EFA83E3D1BE29242B39624F9F4D8B2AEF3A43B949145B6E24637`，没有覆盖或重写。旧报告已标注为衣服单槽修正前的历史快照。

## 覆盖范围与结果

| 项目 | 修正版 |
| --- | ---: |
| 当前正式地图 | 67 |
| 刷新点 | 2645 |
| 刷新怪物 | 120 |
| 工作表 | 121（总览 + 每怪一表） |
| 当前地图独立槽 | 5802 |
| 按实际物品 ID / 金币金额归并的输出行 | 4621 |
| 实际概率为 `0/1` 的输出行 | 16 |
| 受 15 件上限影响的输出行 | 4211 |
| 精确分数文本单元格 | 10423（实际概率 4621 + 原始槽 5802） |

分类沿用当前 canonical 定义：普通 61、精英 27、Boss 17、特殊普通 7、特殊 8。没有擅自把 canonical `special` 归为普通或精英。5 个正式空表怪物 18、30、45、96、100 均保留独立工作表；地图 ID、地图名称、怪物名称、原始槽 UID、保护标志和优先级均完整列出并读回核验。

触龙神（124）已包含，地图为死亡棺材（913207）。金币 70000 单槽判定为 `1/1`，实际落地为 `0/1`：其优先级 100 低于至少 16 个必出药水槽的 200，而落地上限是 15。主表列实际落地概率，单槽判定列只作为核对，二者不会混用。

## 单槽修正的正式核对

全 authority 共 126 种怪物，由 6144 槽变为 6042 槽：37 怪、102 组明确的重复实际衣服，逐个 `monster_id + slot_uid` 保留一槽并移除另一槽。当前地图覆盖其中 95 个移除槽，因此由 5897 槽变为 5802 槽。未出现在当前地图的 7 个移除槽属于完整 authority，但不额外生成不存在刷新点的怪物表。

所有保留的 6042 条槽记录及原顺序与删除前逐字段相同。保留衣服槽的原分数没有求和、翻倍或合并；例如沃玛教主（76）的灵魂战衣实际输出 126：保留男源 `dpv2.direct.m76.v505_0086` 的 `1/20`，移除女源 `dpv2.direct.m76.v505_0085`，现在只进行一次该衣服的 RNG 判定。

这里区分两个层面：女装输出映射到男装 ID 只是实际输出身份归并；旧归档行及 group-to-UID 映射在重建时仍可能展开为两个独立槽。用户删除一行的最新意图需要显式 authoring directive 在归档重建之后执行。不能把旧归档中存在两个来源槽解释成用户仍要两次判定，也不能只在 Excel 展示层隐藏一行。当前正式产物已应用这一 directive。

非衣服 5791 条槽逐字段、顺序和哈希均未变；此前赤月/祖玛调整的 168 条 overlay 也逐字段、顺序和哈希未变：

- 非衣服前后 canonical SHA-256：`0A5169A9C1E0A3F2E82C29B54BC89915758691D8C19AA5F23582EF105E886609`。
- Overlay 前后 canonical SHA-256：`935885E3732909B81424CFDC20B3AB2028388DDA70FE3B6BE80B2BFF71C91ACF`。

6 个暗之 Boss 的最高级衣服槽完全保留：235/140、236/144、237/142、238/141、239/145、240/143（分别为怪物 ID / 原始装备 ID）。每条均为对应 `dpv2.direct.m{ID}.slot_054`、`1/30`、保护组、优先级 2000。完整记录及逐条前后哈希在本报告配套 JSON 的 `armor_revision.frozen_exceptions` 中，可直接机器复核。

移除竞争槽会改变 15 件上限下其他物品至少落地一份的概率。与旧表相比，1135 行实际输出概率发生变化，其中 1015 行为非衣服实际输出；这些非衣服的单槽概率和优先级均未改动。这是按同一上限规则重新计算的结果。

主控已经将归档输入准备链改为从 tracked evidence 重建，摆脱旧临时 outputs。此交付只读核验 `outputs/repair_v92/armor/final_prepared_a/` 与 `outputs/repair_v92/armor/source_only/out/` 的正式编译产物，二者与当前 authority 的完整 SHA-256 均为 `9F6E2741…E6EF43B56`。不把早期临时编译产物 `1B316A5D…A4E13A1F` 当成当前 authority。

## 概率算法与生产语义

重新阅读当前 `loot_runtime_service.gd` 的 `roll_monster_drops`、`_select_ground_rewards`、`_consume_group`、`_shuffle_candidates`，确认：每个正式槽先按 `final_numerator/final_denominator` 独立判定；保护组优先，组内按 priority 降序；同级成功候选超过余位时无偏洗牌；总落地最多 15 件。数学器没有引入其他倍率、分母规则或 SPB 变更。

主表定义为“每次击杀，该实际物品 ID 或该金币金额至少实际落地一份”。使用 Python 任意精度整数及 `Fraction`，逐优先组计算目标成功数 t、其他成功数 o 的精确 Poisson-binomial 分布。状态记录已占用落地位、且目标尚未落地的概率质量。余位 r 不足时，未选中目标的条件概率是 `C(o,r) / C(t+o,r)`；最后以 1 减去未选中质量，正确处理同一实际输出跨多个组、多个优先级出现的情况。没有使用 Monte Carlo、百分比近似或把判定分数冒充最终落地率。

## 验证证据

- 数学：76 个独立逐结果/逐子集穷举案例，另加 2 个 cap 边界案例，PASS。
- 生产输入：快照无 failures；67/2645/120/5802 计数一致；当前 authority 的 126/6042 与 directive 的 102 删除、37 怪、6 例外独立核对 PASS。
- OOXML：121 张表及 120 个怪物 ID 全集一致；4621 行实际输出、5802 行槽明细、全部地图、分类、空表及总览计数逐格读回 PASS。10423 个概率单元格均为字符串类型和 `@` 文本格式，没有数值或日期概率单元格。
- 视觉：artifact-tool 为全部 121 张表渲染顶部区域，11 张 montage 覆盖全部工作表并逐一检查；触龙神另做原尺寸检查。精确长分数换行保留，最长 318 字符。全表内容完整性由上述 OOXML 检查覆盖；不声称视觉逐行检查全部数据。
- 公式错误扫描：无公式错误；所有分数以静态精确文本保存，避免 Excel 浮点精度截断。
- 桌面文件与项目副本哈希一致；旧桌面文件哈希未变。
- 原生 Microsoft Excel 应用打开测试：NOT_RUN；实际文件内容、类型、文本格式与 artifact-tool 渲染已验证。
- 主控生产专项反馈 PASS：`armor_single_slot_authority`、`user_loot_sheet`、rv15 provider 反例、SPB 脱钩、`live_map_export`。这些 Godot 专项由主控执行，本表任务没有启动 Godot。

复现入口为 `tools/loot_audit_v92/calculate_exact_loot.py`、`build_loot_workbook.mjs`、`verify_loot_workbook.py`、`verify_armor_revision.py`；xlsx author 使用 bundled `@oai/artifact-tool`。Python 仅负责精确计算、只读 XML 校验及预览拼图，不用于编写 xlsx。

完整机检证据：[loot_workbook_armor_single_slot_verification.json](loot_workbook_armor_single_slot_verification.json)。中间结果与 121 张预览保留在 `outputs/repair_v92/excel/armor_single_slot/`。本次生成没有 Git 写操作。
