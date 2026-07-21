# MIR-SOURCE-PRIORITY-1：客户端与服务端主辅资料分级报告

## 结论

本项目的58个独立端继续分别建档，不合并、不覆盖。正式施工改为四条资料线各设一个唯一主资料，并固定按“主资料 → 辅1 → 辅2 → 辅3”逐级查询。任何低级资料都不能因为文件名更像、内容更多或搜索更方便而直接被引用。

## 正式分级

### 客户端资源：像素、WIL/WIX、MAP、声音

| 层级 | 权重 | 端标识 | 定位 |
|---|---:|---|---|
| 主资料 | 100 | `client.classic_raw_complete` | 经典完整客户端；42组资源库、180135逻辑帧、528张MAP，解析错误0 |
| 辅1 | 70 | `client.mir2opensource_2013_complete` | 2013完整客户端；资源量大但年代与内容范围晚于经典端 |
| 辅2 | 40 | `archive_extract.mirfiles_new_data.ae702e382cc5` | 私服新增资源包，只补明确缺项 |
| 辅3 | 20 | `archive_extract.mirfiles_hum.bfae8696c79f` | 未知版本人物包，只作最后候选 |

`archive_extract.mirfiles_aige_mir2.847a67ac1446`与主客户端库数、帧数、地图数完全同量，只登记为镜像，用于哈希复核，不算第二套可混用客户端。

### 客户端规则：动作表、偏移、方向、绘制与协议

| 层级 | 权重 | 端标识 |
|---|---:|---|
| 主资料 | 100 | `source.original_gameofmir.mirclient` |
| 辅1 | 70 | `source.original_gameofmir.client` |
| 辅2 | 40 | `source.minipizza_mir2.client` |
| 辅3 | 20 | `working.reference.mir2opensource_2013_client` |

主资料是已验收为`A-rule-source`的经典MirClient完整源码入口。后续源码只在主入口缺少具体规则时逐级参考。

### 服务端数据：NPC、物品、怪物、刷新、商店、任务与配置

| 层级 | 权重 | 端标识 | 定位 |
|---|---:|---|---|
| 主资料 | 100 | `server.crystal.cjlaaa` | 顶层仅Maps、Envir、Configs、Server.MirDB；无Git、BMP、EXE、DLL或压缩包污染 |
| 辅1 | 70 | `server.angelk727_full` | 本地内容最丰富，但混有版本库、3638张BMP和13个程序文件 |
| 辅2 | 40 | `server.crystal.Jev` | 脚本量大，但含大量BMP和压缩包 |
| 辅3 | 20 | `server.crystal.Daneo1989` | 目录较干净，但覆盖少于前三层 |

`server.angelk727_full`虽然内容最多，却不是最干净的正式数据库，所以不能作为主资料。它只负责补充`cjlaaa`已经被证明确实没有的内容。只有单个Server.MirDB的`server.crystal.NightWolf`进入隔离区，不能直接用于运行数据。

### 服务端规则：战斗、移动、AI、硬直、时序与协议

| 层级 | 权重 | 端标识 |
|---|---:|---|
| 主资料 | 100 | `source.original_gameofmir.server_suite` |
| 辅1 | 70 | `source.minipizza_mir2.server` |
| 辅2 | 40 | `source.suprcode_crystal.server` |
| 辅3 | 20 | `archive_extract.GM.51417ae3bc9f` |

主资料是唯一`A-rule-source`经典多进程服务端源码套件。辅3只允许查询GM命令和脚本示例，不得用它推导一般服务端规则。

## 强制使用流程

1. 先把需求归入四条资料线之一。
2. 只查询该资料线的主资料，并记录查询范围、关键词、容器/表/路径和结果。
3. 主资料确实缺失、不可用或版本不兼容时，填写降级证据；“没有马上找到”不构成降级依据。
4. 运行`python tools/source_priority_guard.py authorize`。工具会检查所有更高层是否都有查询描述和原始证据；少一层、少一项证据或尝试跳级都会拒绝。
5. 将授权结果和最终采用端、原路径一并写入派生资源清单及施工记录。若一个成果需要跨端组合，必须逐项记录，默认不允许组合。

## 机器策略与验收

- 唯一机器策略：`assets/data/source_priority_policy.json`
- 降级授权工具：`tools/source_priority_guard.py`
- 证据格式示例：`assets/data/source_priority_fallback_evidence.example.json`
- 自动验收：`tools/verify_source_priority_policy.py`
- 验收结果：`outputs/validation/source_priority_policy_acceptance.json`

验收覆盖四条资料线、唯一主资料、固定权重、来源存在性、严格顺序、无证据拒绝降级和完整证据允许降级。该分级只建立治理顺序，不删除58端原始证据，也不把不同端物理合并。
