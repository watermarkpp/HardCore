# 当前正式地图怪物真实掉率 Excel 交付

> 历史快照：本报告记录衣服单槽修正前的 5897 槽版本，保留原文件和验收结果供追溯。当前交付请见 [衣服单槽修正版报告](loot_workbook_armor_single_slot_20260922.md)，新版为 5802 槽，另存桌面文件，没有覆盖本报告对应旧表。

状态：PASS。2026-09-22 生成并放置桌面，未修改生产源码、正式掉落数据或地图数据；本工作未启动 Godot。

## 成品身份

- 桌面：`C:\Users\Administrator\Desktop\HardCore_当前地图怪物真实掉率_20260922.xlsx`
- 项目副本：`outputs/repair_v92/excel/HardCore_当前地图怪物真实掉率_20260922.xlsx`
- 大小：685903 bytes。
- 两份文件 SHA-256：`75C961CAE7B6EFA83E3D1BE29242B39624F9F4D8B2AEF3A43B949145B6E24637`。
- 创建期间基线 HEAD：`b961cedff8040c9fc81534e094241ad9fa2330ad`。本轮工作树有主控尚未提交修改，因此该 HEAD 只标识基线；本表的实际内容身份由下面查询快照和文件哈希固定。

## 范围与口径

121 张工作表：1 张总览，120 种当前正式地图刷新怪物各 1 张。共 67 张正式地图、2645 个刷新点、5897 个独立掉落槽、4621 行按实际输出身份合并的结果。

正式分类保留为普通 61、精英 27、Boss 17、特殊普通 7、特殊 8。后两项对应 canonical `special` 的 15 种怪物；不强制改成普通/精英/Boss。沃玛卫士1（74）canonical 分类为 `elite`，刷新分类为 `special_normal`，因此主表保留精英，另列刷新分类。

空表怪物也各有工作表：18 毒蜘蛛、30 食人花、45 蝎子、96 羊、100 狼。触龙神（124）已包含，刷新地图为死亡棺材（913207），共 80 槽；金币 70000 的实际落地概率为 `0/1`。

主表“实际落地概率”指每次击杀后指定实际物品 ID、或指定金额金币至少落地一份的概率。同实际输出 ID 的多个独立槽合并；使用查询快照的最终输出身份，因此衣服男女映射后的重复输出正确归并。计入保护组、优先级、并列超限随机选择和 15 件上限。原始槽 UID、每槽判定分数、保护标志和优先级另列在同一怪物表下方供核对。当前地图精确 ID 和名称也完整保留。

死亡掉落流程之后的个人显示过滤、拾取结果、事件额外奖励不属于此概率定义。工作表是已验证快照；为保留任意精度精确分数，概率以文本静态值存储，不由 Excel 浮点公式重新计算。

## 精确计算

依照 `scripts/layers/runtime/loot_runtime_service.gd` 的 `roll_monster_drops`、`_select_ground_rewards`、`_consume_group`：

1. 每槽按查询到的 `final_numerator/final_denominator` 独立判定。
2. 成功候选先分保护/常规组，各组再按优先级降序。
3. 对任意目标输出，以 Poisson-binomial 整数多项式计算每组目标成功数量 `t`、其他成功数量 `o` 的精确分布。
4. 动态规划状态为“目前占用落地位数量，并且尚未选中目标”的概率质量。剩余 `r` 个位置时，如果全组能放下，只有 `t=0` 可以继续未选中；超限时未选中目标的条件概率为 `C(o,r)/C(t+o,r)`，`o<r` 时为零。满位时后续目标无法落地。
5. 最终实际概率为 1 减去所有未选中目标的状态质量。目标跨优先级/保护组出现时，仍保留并推进同一未命中状态。

全程使用 Python 任意精度整数及 `Fraction`，没有 Monte Carlo、浮点近似或精度截断。最长精确分数 318 字符。4211 行受到上限影响，16 行实际概率为 `0/1`。

## 验证证据

- 精确算法：PASS。76 个固定/随机小案例独立穷举所有成功失败组合及各组实际选择子集，与动态规划逐项严格相等；另验证 16 个同级必出候选抢 15 席的 `15/16`、16 个高优先级必出候选导致低优先级目标 `0/1`。
- OOXML 全量读取：PASS。全部 10518 个概率单元格（4621 实际 + 5897 槽）均为文本存储，且 `numFmt` 为 `@`。日期/数值类型的概率单元格为零。
- 全量身份与内容对照：PASS。120 怪 ID 全集、分类、每个输出行、每个源槽行、每张刷新地图 ID/名称、5 个空表全部与精确计算快照逐格相等。
- Artifact Tool inspect：PASS，公式错误搜索为零。
- 视觉：PASS。121 表均渲染开头范围并通过 11 张拼图逐表检查；触龙神表和总览另外以完整预览检查，文本分数换行可见。预览范围不是全表数据完整性的替代，完整性由上述逐格验证承担。
- 桌面副本：PASS，与导出副本字节哈希一致；未覆盖已有未知同名文件。
- Native Excel 应用运行：NOT_RUN。本次通过 XLSX 类型/格式验证文本分数保存行为。

## 输入与生成链

- 查询快照：`outputs/repair_v92/live_map_loot_authority.json`，SHA-256 `828423EF48D5639700F58B251E4B6996353549DC2C87B3137AA6203BF55904C0`。快照由主控真实生产查询建立，计算前后哈希一致；本工作未重新启动 Godot。
- 查询所指权威数据：`assets/data/drop/dpv2_user_loot_sheet_authority_v1.json`，SHA-256 `6314EA67E689A1D65862B6D0C23E92499529DC06F62E454F17FA0B9A1CE690D3`。
- 生产选择逻辑：`scripts/layers/runtime/loot_runtime_service.gd`，SHA-256 `28CEE09BFCA48A62294B43E41D93666EC7A0539F3D7AAB2BA91304632DD0CCCB`。
- 计算器：`tools/loot_audit_v92/calculate_exact_loot.py`。
- Excel 作者程序：`tools/loot_audit_v92/build_loot_workbook.mjs`，仅使用 bundled `@oai/artifact-tool`，未使用 openpyxl/xlsxwriter。
- 独立读回验证：`tools/loot_audit_v92/verify_loot_workbook.py`。
- 机检证据：`loot_workbook_verification.json`。

执行命令：

```powershell
& 'C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools/loot_audit_v92/calculate_exact_loot.py
& 'C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe' --max-old-space-size=8192 tools/loot_audit_v92/build_loot_workbook.mjs
& 'C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools/loot_audit_v92/verify_loot_workbook.py
```

作者程序从 `outputs/repair_v92/excel/node_modules` junction 解析 bundled Node 依赖，禁止改用仓库本地依赖。创建操作标记在首次作者命令前已成功执行一次。

未新增/修改游戏稳定 ID，无跨系统接入需求。未 commit、push、构建或发布游戏。
