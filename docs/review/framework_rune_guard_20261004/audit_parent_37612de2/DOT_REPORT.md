37612de2 本轮二审完成：上一轮伪造词缀准入 P2 已关闭；新增发现 1 个 P1 存档保护缺口、1 个 P2 销毁入口缺口，以及一项 APPDATA 隔离证据待补。本轮暂不建议结案

请求 ID：rune-sources-37612de2-20261004
固定 SHA：37612de204c42fe3b4fd6a89137e90f3449bc0c2
父 SHA：08ccdf29e1be5897fa1ffdb6964f58300ad55c3b
[本轮源码与证据](https://github.com/watermarkpp/HardCore/tree/37612de204c42fe3b4fd6a89137e90f3449bc0c2/docs/review/framework_rune_sources_20261004)

1. P1：独立未来 Rune 的版本身份，会被当前私有字段检查遮住

item_extension_codec.decode_wire 在第40–41行先检查 _hc_item_extension，直接返回 INVALID；第43–48行才识别独立 Rune 的未知合同。这与同一函数已经采用的“未来容器先确认所有者，再应用当前字段规则”不一致

最小反例：保留一份正常共享仓库文档及有效旧 .bak。在主档 warehouse_inventory 放入独立 Rune，合同为 hc.runes.fixture.rune.v2，保留 item_id=990002、正常名称、count=1、有效 instance_id，同时带 _hc_item_extension={}。其余文档结构与备份不变

预期是未知合同触发 OPAQUE_UNSUPPORTED，整个聚合只读，主备文件和发布状态不动。当前源码却先返回 INVALID，随后发生：
- 共享仓库验证把它归为 terminal=false
- 启动预检因此允许选用有效旧备份
- 启动初始化进入恢复路径
- 未来主档被移到隔离文件，旧备份被提升为主档并发布为当前仓库

[Codec 检查顺序](https://github.com/watermarkpp/HardCore/blob/37612de204c42fe3b4fd6a89137e90f3449bc0c2/scripts/items/item_extension_codec.gd#L26-L48)，[启动选择逻辑](https://github.com/watermarkpp/HardCore/blob/37612de204c42fe3b4fd6a89137e90f3449bc0c2/scripts/player_state.gd#L493-L597)，[聚合终态判定](https://github.com/watermarkpp/HardCore/blob/37612de204c42fe3b4fd6a89137e90f3449bc0c2/scripts/player_state.gd#L5184-L5193)，[备份提升](https://github.com/watermarkpp/HardCore/blob/37612de204c42fe3b4fd6a89137e90f3449bc0c2/scripts/player_state.gd#L5686-L5735)

这里没有永久删除原字节，未来主档会被隔离；问题是本应保持只读的未来资产失去当前权威，发生回退。这条路径属于普通启动，不依赖启动后的外部文件替换

修复方向：先识别独立 Rune 的不支持合同／身份，再应用当前版本私有字段规则。已知 v1 带私有字段仍应判 INVALID，不能为了修复未来版本保护而放宽当前格式

建议先补隔离原生 RED：直接 codec、聚合验证、正常启动三个层次，断言未来版本保持 terminal、无 writer／旧仓库发布、主备原字节不变；同时保留已知 v1 同字段损坏的正确恢复对照。现有 future-container 测试已有相同所有权原则，可复用其方法

这是已确认的源码反例，新增原生运行尚未执行。当前282项 future ownership 回执覆盖普通未来 Rune／namespace／未知身份，但没有覆盖此“未来独立 Rune＋当前私有字段”的组合

2. P2：销毁预检查漏掉 remove 事务的预留输出槽

新增检查只调用 record_reserved，检查当前槽内的资产身份。hc.runes.remove 同时会预留首次空位作为 destination，而 slot_reserved 已能识别它。空字典没有资产身份，追加槽甚至还不在当前 inventory 范围内，因此新检查漏过两者

最小反例：
- inventory 为“已嵌 Rune 的 host、空格、无关物品”
- 正式 quote＋commit 接受 hc.runes.remove，目标空格为1；保留 pending.job，不等待完成
- 调用 destroy_inventory_indices([1])

源码路径是：预检查漏过空格→barrier drain 完成取出事务→原 Rune 落入格1→销毁入口才校验索引占用→格1现在合法且独立 Rune 可释放所有权→清空并保存。在成功 I/O 条件下，代码会返回成功销毁1件

追加位置也有同样问题；混合选择“无关物品索引＋预留输出槽”还会一起处理两件物品。没有 pending remove 时，同样的空格或追加索引应返回 invalid_inventory_index

[销毁入口，第1451–1478行](https://github.com/watermarkpp/HardCore/blob/37612de204c42fe3b4fd6a89137e90f3449bc0c2/scripts/player_state.gd#L1451-L1478)，[输出槽预留，第112–131行](https://github.com/watermarkpp/HardCore/blob/37612de204c42fe3b4fd6a89137e90f3449bc0c2/scripts/items/item_transaction_port.gd#L112-L131)，[完成后发布资产](https://github.com/watermarkpp/HardCore/blob/37612de204c42fe3b4fd6a89137e90f3449bc0c2/scripts/items/item_transaction_port.gd#L203-L240)

建议在 barrier 前检查所选索引的 output reservation，检查不应依赖槽已存在或非空；可复用已有 slot_reserved。另一种正确方向是提前固定并验证所选资产身份，避免 drain 后重新解释索引

新增回归应覆盖 Gem／Rune remove 的空槽、追加槽、混合选择：销毁拒绝、destroyed=0、资产不变、已有 pending.job 未被该调用完成、没有新增 writer；随后显式完成原事务，确认只取出一份资产并保留另一个 namespace。不能把“已有合法 writer 尚待完成”误判成必须 pending_count=0

这是源码推导的正式 API 反例，尚未原生复现。普通 UI 使用占用项选择和身份引用，目前没有证据证明普通空槽点击会丢物。父版 Gem remove 已有同类输出槽风险，本轮增加了 Rune 暴露面

本轮原销毁 RED 的含义仍保持：destroyed=0、invalid_inventory_index、inventory_unchanged=false、writer_finished=true，证明被拒绝的销毁调用完成了另一事务，并不证明那次 Rune 被销毁。最终35项通过覆盖了插入侧 Rune／host／混合选择，但未覆盖 pending remove 输出槽

3. 上一轮词缀 P2 已按限定范围关闭

新 provider 对声明 drop_affix 的记录，在匹配 modifier 和读取 instance_id 之前调用既有完整 GameData.validate_item_drop_instance，复用原合同、实例身份及确定性修饰验证

typed RED 保留27检查／13失败，并保留旧 collect 的缺 instance_id 生产脚本错误；最终为29/29、原生退出0。缺合同、重复／伪造 modifier、错误身份、缺身份均拒绝来源和发布，旧目录、bundle、stats、compile_count保持；普通无词缀旧装备仍兼容并产生零词缀来源

[修复位置](https://github.com/watermarkpp/HardCore/blob/37612de204c42fe3b4fd6a89137e90f3449bc0c2/scripts/features/adapters/contribution_provider.gd#L23-L35)

这项不需要再次扩大施工。两个新问题分别属于输出槽预留和未来版本所有权，不能混成原词缀修复未生效

4. Rune／Gem 事务与三来源战斗的正常链路可采纳

四种插入／移除操作使用同一 ItemTransactionPort、Journal 和 ordered writer。Gem 仍使用 gem_instance_id，原 profile／action／target／gem 四元素摘要合同保持；Rune 使用 rune_instance_id，没有把新字段混进旧 Gem 摘要

_compose_target 从完整 extensions 出发，只更新本次 namespace。宝石和符文拥有独立实例身份，跨 namespace 和聚合重复所有权检查仍存在，未发现第二 writer 或通过重建单 namespace 丢失另一资产的路径

[请求摘要与接受](https://github.com/watermarkpp/HardCore/blob/37612de204c42fe3b4fd6a89137e90f3449bc0c2/scripts/items/item_transaction_port.gd#L45-L118)，[namespace 保留](https://github.com/watermarkpp/HardCore/blob/37612de204c42fe3b4fd6a89137e90f3449bc0c2/scripts/items/item_transaction_port.gd#L293-L299)

三来源夹具确认：正式词缀、宝石990001、符文990002形成三个独立 ignite 句柄；选择性拆卸只撤对应来源，重插恢复原句柄集合，base和gold检查保持

战斗调用真实 Player.request_skill，等待真实起手 Timer，观察同一个接受 lease 恰好释放一次；非空 binding 有容量票据，基础伤害为正，三个持续状态完成四次对应周期交付，RNG保持。停用模块后不再产生后续订阅，已接受状态继续完成

最终 live 35/35，独立 cold 14/14。producer为98cb0b56-9a04-447b-89f9-9eef991b182e，cold为0fe24563-65e3-4ec2-a44d-1567021dbb14，二者绑定本轮 invocation 65b99757-53d1-49ca-946a-78692bce500e 和最终源码指纹。cold重交原 Gem :4、Rune :2 操作，走提交前的 durable replay 返回，资产不变、无新增 writer

[战斗夹具](https://github.com/watermarkpp/HardCore/blob/37612de204c42fe3b4fd6a89137e90f3449bc0c2/tests/framework/rune_source_composition_test.gd#L76-L113)，[cold 验证](https://github.com/watermarkpp/HardCore/blob/37612de204c42fe3b4fd6a89137e90f3449bc0c2/tests/framework/rune_source_composition_cold_test.gd#L20-L65)

仍需准确限定：普通处理被停止，后续使用手动 pump 和模拟钟推进；cold明确重新启用模块。这些证据不证明启用状态自动持久化、自然连续输入、渲染或设备表现

5. 身份数据、归档与最终采用集合核对

我独立比较了父／当前实际运行身份索引：1240个旧身份全部保留，业务字段零变化；21个类别仅证据 pointer 随作者数组位置更新。新增只有 hc.item.990002、hc.item.990003、hc.item_category.rune 三个身份。没有独立重跑生成器，生成器检查和Python单测属于提交方提供的运行证据

源码和原生档案核对：
- 3716份源码，较父版16新增＋11修改＝27路径
- 内容指纹复算为5b9967313469bd7f30178a76f0e72b7de01e99b58ca47052a43fecd0edaf49ee
- 对固定 Git blob 全量比较：837份字节一致，2879份仅CRLF差异，零其他不匹配
- 源码 ZIP：15767124字节，SHA256 51cbd820ffba227c192ca13d1b68f21f1cc4396368ddcc1f75af27b4475b7efb
- 原生 ZIP：8988854字节，SHA256 cb6ab7021d250676394680fb7532dc9bc23134a03b3d4273508c133fbec330da；591份成员哈希和长度匹配，无重复路径
- 113次原生尝试＝97 PASS＋16 FAIL，失败原件保留
- 最终40唯一场景、36完整 framework receipt、1537个通过检查，另4项普通场景
- 所有最终 runner／receipt／handoff 的 scene、run、invocation、source、完整回执哈希和退出状态一致；原生退出0、无超时，未扫描到原始 SCRIPT ERROR／ERROR
- 8份 expectation 均关联同调用的指定 producer，包括 Rune live→cold 和 journal seed→cold→restart

最终仍有11个场景保留 ObjectDB 退出告警：10个为8实例，summon场景为10实例，不能据此宣称无告警或无泄漏

[运行索引和采用范围](https://github.com/watermarkpp/HardCore/blob/37612de204c42fe3b4fd6a89137e90f3449bc0c2/docs/review/framework_rune_sources_20261004/RUN_INDEX.json)

6. APPDATA 隔离需要补一项可追溯记录

四组独立 invocation、对应源码、最终结果和旧失败保留都已核实。但扫描本轮591份原生归档，未找到每组具体 APPDATA 目录或子进程环境记录；不同 invocation ID 本身不能证明不同数据目录

当前 runner 可以使用 HARDCORE_AUDIT_RUNTIME_APPDATA，也可以落到工作树默认目录。因此“四组分别拥有 APPDATA”暂保留为生产方声明，不能升级为本次独立字节验证结论。这不是认定最终运行实际串号或污染

请补已有启动记录中的“每组解析后的 APPDATA／user-data根→命令或环境→invocation／子进程”的对应证据，并说明 seed／cold／restart 哪些有意共享。优先归档已有记录，无需仅为元数据缺口盲目重跑全部40场景。若历史记录确实没有，也应如实标注缺失

7. 下一步建议与整体边界

先对第1、2项分别补原生 RED，再做窄修复和相关回归；第6项补现成隔离记录。上一轮 affix 修复、正常三来源接受、旧 Gem 摘要兼容和身份业务字段保留可以继续采纳

历史 index 连续性 FAIL／旧原件 MISSING继续保留；上一轮当前 index 原件已复算的结论不重开。当前真实 HEAD／index 未切换属于现场保护归档声明，我没有直接检查用户电脑

本报告为固定远端源码及原生档案二审，没有运行引擎或改工程。死亡子连锁、防自激、动态完整接受保证、Task5、自然P6/R3、旧supervisor安全复用、精确v97B、Android／GPU／APK仍开放。完整结果已留在本对话，供原施工主控直接拉取
