# 掉落编译输入可重建性修复

> 历史采样说明：以下保留调查时点的候选与验证状态。主控后续生产修复、动态结果和剩余边界见 [CONTROLLER_REVIEW.md](CONTROLLER_REVIEW.md) 与 [USER_REQUEST_RECONCILIATION.md](USER_REQUEST_RECONCILIATION.md)；本文的旧 NOT_RUN/旧数量不代表最终当前状态。

日期：2026-09-22，UTC+08。范围是编译输入准备、精确UID绑定及说明；本子任务未改
`compile_authority.ps1`，该入口由主控串行接入。没有运行Godot、Git写操作或生产表/地图修改。

## 结果

**PASS：正式输入准备已脱离桌面、TEMP解压包和旧未跟踪输出。** 只用11个指定源码/证据文件的
独立目录，在无旧 `outputs/tmp_loot_sheet` 的环境中重建成功；与当前已验收两个输入逐字段完全等价。

- 126张怪物表；4,883条归档记录 → 4,876条具名奖励。
- 精确过滤CSV列出的7条无奖励身份残留；保留5个明确空profile。
- 精确重放320个合并行、1,420个不同真实baseline UID。
- 精确保留25行共125个 `null` 字段；不把它们归并成空字符串。
- 3个已验收的混合物品组保持既有UID与输出；新路径没有邻近/同base身份推断。
- Windows PowerShell 5.1与PowerShell 7实际执行均PASS。
- 缺失/哈希漂移/身份不符/完整JSON不符/逐字段比较失败均抛错；验证通过后才写指定OutputDir。
- 本子任务Godot、APK、设备、原XLSX重新解析均 **NOT_RUN**。

## 生产入口和依赖变化

原编译器读取未跟踪的 `outputs/tmp_loot_sheet/loot_sheet_parsed.json` 与
`row_to_full_slot_uid_map.json`；旧分组脚本又硬编码仓库C盘位置、TEMP复审包路径，
并在运行时选择同item/base或邻近同base UID。原路径不能从干净检出可靠重建。

新增：

```powershell
pwsh -NoProfile -File tools/loot_sheet_compiler/prepare_archive_inputs.ps1 `
  -ProjectRoot . -OutputDir outputs/loot_archive_rebuild_v92
```

`OutputDir`必须显式指定；`ProjectRoot`省略时从脚本位置解析。两个标准输入写入该目录。
`-VerifyAgainstDir`只作可选验收比较，不是生成输入。主控已把编译器接为先准备
`<OutputDir>/source_inputs`，再读取这两个文件；本报告不代替主控的最终整条编译验收。

`group_merged_rows_v4.ps1`保留文件名以便调用，但实现改为验证、重放精确封存map。
可独立运行，或由prepare以 `-ValidateOnly -PassThru` 调用，后者不写文件。
它不改变当前工作目录，也不读环境变量或隐式旧输出。

旧 `parse_xlsx.ps1`尚在仓库作为历史提取工具；它不在这条正式可重建链中，本次没有改它。
原工作簿字节没有被恢复或重写，归档重建不能冒充原工作簿重新解析。

## 封存证据和精确性

新增 `evidence/archive_input_bindings_v1.json`，合同
`hardcore.loot_sheet.archive_inputs.v1`，两脚本均固定其SHA。
全部源文本绑定明确使用 `source_hash_mode=utf8_lf_text`：
UTF-8解码、CRLF归一为LF，再对UTF-8字节SHA256。此规则也用于manifest自身seal，
避免Git的换行转换产生假失败。压缩二进制不在本绑定里；没有把该规则应用于gzip。

绑定8份原文/数据：

1. `workbook_rows_4883.json`
2. `workbook_summary.json`
3. `sheet_coverage_126.json`
4. `SOURCE_BINDINGS.json`
5. `03_合并独立槽320行_待绑定完整UID.csv`
6. `04_五张空表与七条残留.csv`
7. 新封存 `row_to_full_slot_uid_map.v1.json`
8. `assets/data/drop/dpv2_direct_baseline_v2.json`

原始工作簿绑定为
`bc234fca54286547b07f64731c9d0e3674aa19a703863c393c356caf97005251`。
准备脚本同时检查summary、SOURCE_BINDINGS和manifest一致，不从未知工作簿猜测。

原parser格式中的空字符串和null区别不在4883行原档里：原档把不存在XML单元格与存在但空的
单元格都记为null。主控批准以已验收parser的精确坐标封存这部分表示信息：
赤月恶魔111–118行、祖玛卫士00的82–98行，各5个字段
`item_id/type/gold/composition/slot_raw`，共125项。应用坐标前必须确认源字段null且
候选输出为空字符串，禁止丢弃任何非空源值。

公式使用归档的展开公式，去掉单个前导等号；概率缓存值使用归档 `E_raw.raw` 原字符串，
不重新计算浮点或从显示百分比倒推。表次序来自126表coverage，行次序来自4883归档。
完整输出还必须匹配已验收JSON的紧凑序列化SHA，不能仅以计数相同通过。

| 输入 | 已验收原始字节SHA256 | 紧凑JSON内容SHA256 |
| --- | --- | --- |
| `loot_sheet_parsed.json` | `c361a3dcbabacedb0cd93cf9b35abac9d7284d75dede0b3e23538e0ddcaa32b8` | `a663a4b6122de93bf0146d6ba9340a2f1ebb4910028953b5b237196bc6f892cb` |
| `row_to_full_slot_uid_map.json` | `ad91e747f3e1f92d16581c93d7fb381e0f3f91559a731380ddd2100ea228511d` | `42f295b2427fd71f1b33c45bac32238312ffbbe1f9d0b6b49a192f2f3113fb9b` |

PowerShell 7在本机还重建出与两个旧文件相同的原始字节SHA。
PowerShell 5.1序列化排版不同，原始输出SHA分别为
`2a7e0465356958516c60223b210aed4a59a7a27a303612c236668af076c0f6c4` 与
`e96b1aed12b831088304dd32be4dfcb8a96526b268f2e3c79e119318b2d61423`；
完整字段、JSON类型、null、数组次序和紧凑JSON SHA保持一致。原始SHA作为取证记录，
不会把JSON排版差异误判为业务差异。

## 320行UID绑定的证据边界

完整map来自当前已验收 `row_to_full_slot_uid_map.json`，以原字节封存在versioned evidence。
它没有被当作可重新推导的规则。运行时校验：

- 320个row key唯一，与原CSV的monster、sheet、行号、展示名、单槽概率、N和代表UID逐项相等。
- 代表UID的真实item ID与CSV一致；金币无item字段按原明确0表示匹配。
- 所有1,420个UID存在于完整SHA绑定的baseline，属于准确monster、顺序与baseline一致，
  全局无重复，成员数为N且包含代表UID。
- 每个已绑定记录的base分数与原接受组一致；完整baseline SHA绑定其全部记录内容。
- 完整map JSON和其历史mode计数均匹配封存证据。

原算法的317组 `item_base_all` 和3组 `base_run_from_rep` 仅保留为出处。3组具体为：

| monster / Excel行 | 确切UID | 实际item IDs |
| --- | --- | --- |
| 92 / 23 | `dpv2.direct.m92.v505_0022`、`dpv2.direct.m92.v505_0023` | 174、200 |
| 94 / 23 | `dpv2.direct.m94.v505_0023`、`dpv2.direct.m94.v505_0024` | 174、200 |
| 225 / 34 | `dpv2.direct.m225.slot_041`、`dpv2.direct.m225.slot_042` | 224、223 |

CSV只有代表UID，无法独立证明这3组全部成员的原始作者意图。本次按主控确认保留已验收准确map，
不冒称重新从CSV证明了组意图，也不继续运行旧邻近猜测。用户确认其他掉落无问题后，
本任务没有调整它们的物品身份、概率或输出。

## 实际检查

| 检查 | 结果 |
| --- | --- |
| Python先重建全部parser字段并比较原JSON | PASS |
| prepare对原已验收目录完整递归字段比较 | PASS |
| source-only目录（11个文件）从无关cwd运行，省略ProjectRoot，无旧outputs输入 | PASS |
| 同一source-only证据全LF与全CRLF两种形式 | PASS |
| 分组入口独立运行，320行完整JSON相等 | PASS |
| 修改归档源字节：退出1，未创建目标目录 | PASS |
| 只修改比较文件gold=150→151：退出1，未创建目标目录 | PASS |
| 最终脚本PowerShell7/source-only/完整字段比较 | PASS |
| 最终脚本Windows PowerShell5.1/source-only/完整字段比较 | PASS |
| 最终脚本Windows PowerShell5.1归档哈希漂移拒绝 | PASS |
| 两脚本无TEMP/USERPROFILE/硬编码旧outputs/Set-Location/现代专属SHA API | PASS |
| scoped diff审阅与diff --check | PASS |
| 整条compiler最终输出/生产安装 | NOT_RUN（本子任务；由主控负责） |
| Godot、APK、设备、原XLSX重新解析 | NOT_RUN |

兼容性检查曾发现并修复：原始SHA与LF seal混用、PowerShell5.1的ConvertFrom-Json数组枚举差异、
JSON整数与PowerShell Int32内部类型差异、旧.NET没有HashData/ToHexString，以及嵌套5.1宿主
无法自动载入Get-FileHash的环境差异。最终使用SHA256.Create/ComputeHash、BitConverter，
源码UTF-8 BOM，源/输出hash均不依赖Get-FileHash模块。上述最终重跑均通过。

常用复核命令：

```powershell
pwsh -NoProfile -File tools/loot_sheet_compiler/prepare_archive_inputs.ps1 `
  -ProjectRoot . -OutputDir outputs/loot_archive_rebuild_v92 `
  -VerifyAgainstDir outputs/tmp_loot_sheet

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools/loot_sheet_compiler/prepare_archive_inputs.ps1 `
  -ProjectRoot . -OutputDir outputs/loot_archive_rebuild_v92_ps51 `
  -VerifyAgainstDir outputs/tmp_loot_sheet
```

本机source-only测试结果：
`outputs/loot_archive_probe_v92_20260922_163444/results.json`、
`final_results.json`，同目录保存各case日志和两个宿主的最终日志。
首次source-only正常重建未传VerifyAgainstDir；最终重跑使用它增加独立逐字段比较。
目录只包含本子任务复制的证据/脚本和测试输出，没有生产源修改。

## 交付文件

| 文件 | 字节数 | 原始SHA256 |
| --- | ---: | --- |
| `tools/loot_sheet_compiler/prepare_archive_inputs.ps1` | 11056 | `b688d14b93d35bc55162ffa1b66756cc074418217e1602dab19fc0dc644c4c2b` |
| `tools/loot_sheet_compiler/group_merged_rows_v4.ps1` | 6707 | `d40b0a37be2e48b43fd86e536b5ac24c50c4762ab650e5ffc2d1bb5b88825821` |
| `tools/loot_sheet_compiler/README.md` | 6557 | `c3dee0b214d404c33278be1bbadd67cd825b2832a2af59a6a6f090dada7a5686` |
| `tools/loot_sheet_compiler/evidence/archive_input_bindings_v1.json` | 7463 | `fb104571f478b7ab3b39dd618105b8dc1d3e5c141279034ac17f0aa64ba29ec1` |
| `tools/loot_sheet_compiler/evidence/row_to_full_slot_uid_map.v1.json` | 120621 | `ad91e747f3e1f92d16581c93d7fb381e0f3f91559a731380ddd2100ea228511d` |

manifest当前raw字节正好为UTF-8 LF，所以其raw SHA与正式normalized seal相同；
map的normalized源绑定则是
`8b76c43f45a2c068f8825d7b968e637528e2119db8e16d0d3e12d14d49c81600`。

未stage/commit/push；未更改新掉率表、equipment master、地图、原CSV、原始归档行。
本子任务拥有文件已完成，主控应在最终编译输出和最终提交处统一绑定证据。
