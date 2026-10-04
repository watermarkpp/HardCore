# 符文来源与组合接入：受测固定增量

2026-10-04，第三工作树单主控串行施工。父审查提交 `08ccdf29e1be5897fa1ffdb6964f58300ad55c3b`；施工 HEAD 仍为 `5d9ceb0121980ca9636d9d1cc2e19982949fbf63`，大量既有未提交工作保留。本目录是下一审查提交的原字节证据，提交身份以包含本目录的固定 Git SHA 为准。

最终受测内容指纹：`5b9967313469bd7f30178a76f0e72b7de01e99b58ca47052a43fecd0edaf49ee`，3716 个源码/测试/配置文件，较父阶段 27 个增量路径。Godot `4.7.stable.official.5b4e0cb0f`；console SHA256 `d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`，引擎子进程文件 SHA256 `b2ca888d5115a6cedee564764a2ee494a625f2ec2edbabd010fe33c9a88a6bf8`。

## 有界改动

- 在正式作者身份数据登记 `hc.item.990002`、`hc.item.990003` 和 `hc.item_category.rune`。既有生成器生成运行索引；1240 个旧身份的业务字段不变，21 个类别证据 pointer 随作者数组插入由生成器更新。`IDENTITY_PRESERVATION.json` 逐项记录；生成器检查与 27 项 Python 单元检查通过。
- 新模块 `hc.runes.fixture` 默认关闭，两个记录使用同一主源记录解析、creator 与 instance 合同 `hc.runes.fixture.rune.v1`。仅验证一个明确槽 `hc.runes.primary`，不决定正式玩法的符文孔数、收费、掉落或平衡。
- 既有 `hardcore.item.container.v2` 容器支持独立 `hc.runes` v1 扩展，宝石和符文拥有各自实例身份；同一资产不得归属多个位置。未知身份/未来 Rune 或嵌入版本优先形成 aggregate 只读结果，不能借已知损坏回退旧备份覆盖未来资产。
- `hc.runes.insert/remove` 复用现有 ItemTransactionPort、Journal 和唯一 ordered writer。Rune 请求使用 `rune_instance_id`；旧 Gem 字段和摘要合同保持。每次只修改本操作的 namespace，未持久提交不提前暴露资产归属。
- 正式词缀、已嵌宝石、已嵌符文经统一贡献来源形成三个独立 ignite 句柄。真实 Root→Player timer 释放、非空容量票据、基础命中、三来源周期交付及资源持有/退休被控制夹具验证；停用只撤后续来源，已接受工作保留。

## 两个原生反例与最小修复

### 预留物品销毁入口

`rune_reserved_destruction_red_093459_058564` 记录了 `reserved_before=true`，销毁拒绝为 `invalid_inventory_index`，但 `inventory_unchanged=false`、`writer_finished=true`。原因是销毁入口先同步 drain 另一已接受事务，再判断调用方的旧索引；没有证据表明 Rune 被销毁。修复只在现有 `destroy_inventory_indices` barrier 前按稳定预留身份拒绝所选 Rune、host 或混合选择，随后原事务仍能正常持久提交。GREEN 与最终 Rune 35 项完整检查通过。

### 父审查 P2：旧兼容装备不得授权伪造新词缀来源

`rune_affix_admission_typed_red_094025_604531` 保存 27 项/13 FAIL 和一个生产脚本错误。旧兼容装备缺完整 drop 合同、重复或伪造 modifier、错误实例身份可进入新 affix 来源；缺 instance_id 会在贡献入口报错。更早 RED 还包含测试自身不安全读取，原件保留并先修测试防护后重跑。最小生产修复只在声明 affix 的新来源入口调用既有完整 GameData drop-instance 验证；普通旧装备兼容保持。最终 29 项检查确认 typed 拒绝、原装配/目录/统计保留，以及健康真实来源可继续启用。

## 最终同字节采用

| 原生分组 | 场景数 | 隔离约束 |
|---|---:|---|
| `rune_delivery_clean_direct_095540_552855` | 28 | 新测试拥有 APPDATA，30 秒窗口 |
| `rune_delivery_journal_single_100515_109933` | 1 | 独立 v2 恢复矩阵单独账户，60 秒窗口 |
| `rune_delivery_journal_chain_100711_955151` | 3 | seed/cold/restart 仅彼此共用本轮账户与 handoff，60 秒窗口 |
| `rune_delivery_final_world_100856_061086` | 8 | 四组 live/cold 使用本轮 producer，60 秒窗口 |

40 个唯一场景均最终原生退出 0、无 timeout、无脚本错误；36 份完整框架 receipt 共 1537 项检查。四组 before/after 全量指纹相同。完整命令、run/invocation/source/exit、回执及本轮 producer/cold 关联见 `RUN_INDEX.json` 和 `native/`；不以中途 marker 作裁决。

Rune cold 通过独立进程恢复两个扩展及全部实例字段、三个来源，并重交原 Gem/Rune 成功命令，确认 durable replay、没有新增 writer 或资产变化。模块在夹具中明确重新启用；不宣称启用状态自动持久化，也不宣称地面掉落冷重建。

113 次原生场景尝试共 97 PASS、16 FAIL，失败原件全部保留。最终采用仅上述四组，不把阶段不同指纹合并。两次最终分组失误分别是：legacy 负例故意留下未来 journal 与损坏物品后共用账户，正式 startup 拒绝；两个 producer 共用账户、创建同名角色，正式建角拒绝。后续仅为各测试选择独立测试拥有账户，没有删除原角色、放松门禁或改同名规则。其他 RED、阶段缺口详见 `RUNE_SOURCE_WORKLOG_20261004.md`。

## 原件与保护

- `TESTED_SOURCE.zip`：15767124 字节，SHA256 `51cbd820ffba227c192ca13d1b68f21f1cc4396368ddcc1f75af27b4475b7efb`。
- `NATIVE_EVIDENCE.zip`：8988854 字节，SHA256 `cb6ab7021d250676394680fb7532dc9bc23134a03b3d4273508c133fbec330da`。
- 两 ZIP 均重新打开逐成员检查原始长度/哈希；Git 与受测源码的逐文件 exact/CRLF-only 对账另见 `GIT_TESTED_SOURCE_MAP.json`。
- 主树、第二树 HEAD/index/dirty 指纹与既有保护记录一致；第三树真实 index 当前 SHA256 `df5a01dd0d87c14620e0021d70c25a830eb2cc37aa7b012eeb14ee1f2c58c5fb`，未被临时发布 index 覆盖。历史 index 连续性仍为 FAIL，旧原件 MISSING，不恢复、不重建、不把当前备份当历史证明。
- 原主源图片/音频及冻结 MonsterStreaming 原字节保持。测试数据仅在本工作树独立 APPDATA 内。
- 父 08cc 两位完整报告及实际来源/读取身份保存于 `audit_parent_08ccdf29/`；它们不审查本新增量。既有 ObjectDB warning 保留，不称总内存零增长或设备通过。

## 仍开放的原范围

Task4 死亡子连锁、防自激、动态几何完整接受承诺、生成式组合，以及 Task5 新增功能模板、自然持续 P6/R3、Android/GPU 和 APK 交付继续施工。本受控三来源夹具不替代自然输入/渲染/设备验收。旧故障 supervisor 必须先完成安全复用核验；精确 v97 第二角色原 B 输入仍 MISSING。没有主树集成或真实存档操作；完整架构、APK 和设备状态为 NOT_RUN。
