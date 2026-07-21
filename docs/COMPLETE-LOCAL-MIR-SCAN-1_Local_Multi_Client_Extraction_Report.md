# COMPLETE-LOCAL-MIR-SCAN-1：本地多端全量拆解验收报告

## 结论

本地客户端、服务端数据库、源码端、资源包及解包副本的全量拆解扫描已完成并通过机器验收。所有端按独立身份建档；全局库只提供跨端检索和哈希对照，不覆盖端内归属，也不把同名文件合并成一个来源。

## 覆盖范围与统计

| 项目 | 结果 |
|---|---:|
| 来源根目录 | `dev_art_sources/` |
| 文件数 | 38,887 |
| 总字节数 | 14,595,954,010 |
| 独立端档案 | 58 |
| 文本文件 | 14,268 |
| 资源库 | 243 |
| 全路径逻辑帧 | 1,663,124 |
| 有效帧 | 1,617,808 |
| 去重后帧记录 | 1,247,757 |
| MAP画像 | 8,057 |
| 压缩包 | 16 |
| SQLite完整性 | `ok` |
| 未哈希文件 | 0 |

文件数与字节数均已重新从磁盘统计并与SQLite、`validation.json`逐项核对，58个端的独立清单合计也与全局统计完全一致。`catalog.sqlite`的实际SHA-256与`manifest.json`记录一致：`3a133f39e9a0bf0b065b29778ff4f40d33aaa009ba1bed0a3213ae3a33233c79`。

## 分档规则

- 每个完整客户端、服务端数据库、源码端、资源包和解包来源有独立目录及独立`manifest.json`。
- 复合源码树已拆成客户端、服务端、共享组件或工具等不同端，不以压缩包外层目录粗暴合并。
- 每端均提供`files.csv`、`semantic_hits.csv`、`resource_libraries.csv`和`maps.csv`；适用项为空时仍保留表头和档案身份。
- 全局`cross_distribution_duplicates.csv`只登记跨端同哈希内容，不能改变任何文件的端归属。
- 私服数据维持B/C候选等级，进入正式游戏前必须结合客户端像素、配套源码或多个独立端交叉验证。

## 已知阻塞与解析异常

扫描器保留了22项解析异常，没有静默丢弃：

- 3个压缩包缺少密码：`mirfiles_black_dr.rar`（7个加密成员）、`mirfiles_black_ha.rar`（9个加密成员）、`mirfiles_masks_weapons_series_1.rar`（19个加密成员）。压缩包本体、成员目录、加密状态和原始哈希均已建档。
- 18个0字节图片/WIL是上述加密包或旧`selected`副本留下的解包占位，不可作为素材使用。
- `DelphiX/Demos/Iso/Level1.map`是1024字节的DelphiX示例关卡文件，与传奇MAP只是扩展名相同；已作为扩展名碰撞保留，不应交给传奇地图解析器使用。

以上22项均被验收器识别为预期、可解释的来源阻塞；未发现额外的未知解析错误。除非取得3个压缩包的密码，否则不能安全恢复其中的真实像素内容。

## 产物入口

- 全局清单：`outputs/resource_catalog/complete_local_mir_sources/manifest.json`
- SQLite检索库：`outputs/resource_catalog/complete_local_mir_sources/catalog.sqlite`
- 58端独立档案：`outputs/resource_catalog/complete_local_mir_sources/distributions/`
- 跨端哈希对照：`outputs/resource_catalog/complete_local_mir_sources/cross_distribution_duplicates.csv`
- 扫描日志：`outputs/resource_catalog/complete_local_mir_sources/scan.stdout.log`
- 独立验收报告：`outputs/validation/complete_local_mir_scan_acceptance.json`
- 可重复验收器：`tools/verify_complete_local_mir_scan.py`

## 验收结果

`tools/verify_complete_local_mir_scan.py`已验证以下12项全部通过：SQLite完整性、数据库哈希、磁盘文件数、磁盘字节数、全文件哈希、58端数量、端目录精确匹配、每端必需清单、端统计合计、独立分档策略、跨端对照表、预期异常分类。

扫描器契约测试3项通过。当前工程Python环境没有安装`pytest`，因此使用同一Python运行时直接载入并执行三个纯断言测试函数；测试内容与通过`pytest`调用相同。

## NPC施工的使用边界

后续NPC施工应先按端查询`semantic_hits.csv`和SQLite全文索引，分别提取NPC名称、地图坐标、对话脚本、商店、修理、仓库、传送和任务关系，再做跨端差异表。不得先合并多个私服端后反推“标准NPC”；任何进入正式运行的数据都必须保留端名、原路径、原始文本或数据库记录以及可信度。
