# 双审计 A—D 整改与验收快照

审计基线 `4d1efdc45897ace1be64fe0050c977c47f703ad0`。本包只固定第三树的授权施工和证据，不是主树合并、APK 或设备验收。

最终受测 **3488 文件**，内容 SHA256 `dfff3bb9ca79bb93c9480f7186acd5c48a73d27c54fdf6bd798983db62312e4d`。引擎 `4.7.stable.official.5b4e0cb0f`，SHA256 `d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`。全量原生源码 `FINAL_NATIVE_SOURCE.zip` 保留所有受测字节，SHA256 `6d72b0a6cf6aac001605a6f96e0b28d07017ce649ae469881c2aa5730fca7231`；两个辅助重放脚本另列哈希。Git 文件可能保留原始换行或作 CRLF/LF 转换，逐文件验证接受原字节或等价换行；原生压缩包和受测清单用于精确复算。没有源码排除项。

## A 实际消费迟到 — PASS（限定夹具）

真实 damage-port 调用前计数与最大迟到；`tick_delivery_count` 为有效投递尝试，`ticks` 为成功返回，`failed/invalidated/expired` 分别记录拒绝、失效和到期。只增加常数空间统计，不改变调度、时钟、RNG、伤害或生命周期。原750ms反例先有2个业务FAIL；最终边界测试覆盖准时0、恰好1000000us不满足严格小于、同epoch两次pump、暂停、自然到期、目标失效和显式stats故障。

最终同夹具30目标、90状态、360次投递/结算、1800HP、30收益保留。实际最大消费迟到 **733333us**；帧末最大剩余积压 **733333us**，分别报告。683条原始wall样本独立重算P95/P99 **7556/8297us**；死亡排空773694us，资源完成34731us。范围仅PC headless固定目标/现有ignite handler三个来源；不代表Android、GPU、移动战斗、30死亡同时积压或全P6/R3。

## B 本轮成功producer绑定 — PASS

仅相互一致的expectation/receipt不够。新反例16种输入共36检查，旧门禁14 FAIL且真实cold加载改变内存。runner在启动前重置本轮关联，并在原生退出0、完整receipt成功、零错误后记录准确scene/run/source/receipt哈希；重复scene重新启动前也使其旧成功记录失效。cold按runner独立指定producer匹配，不从待验证expectation自行认定本轮。组合与合法退出cold复用同一测试证据门禁，游戏持久化权威不变。

最终负例矩阵 **38检查PASS**，含receipt缺失/截断、旧轮次、错run/source/scene、同consumer ID、失败计数、原生未退出/失败、关联缺失/哈希不符及真实证据写入失败；拒绝发生在选角与恢复前，内存和已有文件保持。最终正常live/cold也通过。

## C 阶段与最终结果 — PASS

trace明确命名`workload_observation_before_final_save_teardown_reload`，使用`phase_status/phase_checks`，没有无范围的status/count。最终以完整receipt、源码/引擎指纹、原生退出和runner结果共同裁决。

最终save、teardown、reload故障各在新建隔离APPDATA实跑，阶段观测PASS仍保留最终FAIL；cold全部在恢复前拒绝，旧expectation字节保持，runner没有成功交接。**六个原生FAIL仍是FAIL**；“负例验证PASS”只表示正确识别预置故障。save实际在世界账本checkpoint失败，reason=`world_clock_checkpoint_failed`，伴随一个精确的拥有路径目录I/O错误；没有改称更后的原子写失败。初次故障分类脚本因此FAIL，原始记录保留；最终分类严格核对实际错误路径、原因和所有其余门禁。正常最终check count与完整receipt一致。

## D 非空generation — NOT_RUN，选择审计方案A

本夹具实际generation为空串。断言和trace现在明确只证明已保存标记保持，不能证明非空代次生产和恢复。XP=450恰好一次及持久化队列排空证据保留。非空generation继续作为单独开放覆盖，不用硬塞内部字符串制造通过。

## 最终回归与前序施工

按旧final_regression的14项顺序，加合法退出live/cold和A边界，共 **17原生 / 384检查PASS**；另B矩阵1原生/38检查PASS，同一最终指纹。`RUN_INDEX.json`保存实际命令，各目录保存完整receipt/native_handoffs/trace，ZIP保存原始日志和前后指纹。

本次从4d基线还包含已经完成且独立验证的价格身份与默认root迁移测试增量：31既有价格候选补登记ID，原价格和来源不变，179个既有物品ID报价保持，疗伤药hc.item.910007沿用原5000价格补ID入口；无新增稳定ID。价格最终9场景通过，真实原始v90归档/合成旧档默认root共121检查通过。它们的受测指纹明确保留在各目录，**不冒充本轮最终17场景运行**。原v90用户归档字节不上传；重放需本机独立保留的原始输入。前序三个生产修复（活跃世界角色守卫、消费队列回收、process补充处理）保留。

## 开放门禁

完整接受前容量仍FAIL；receipt65536安全退休与journal64恢复是两个未完成协议；精确v97 B角色故障原始输入MISSING，新角色和v90通过不能因果结案。完整P6/R3、主树集成、APK、签名、安装和设备均未验收。没有AOE上限、截断、回滚HP、第二writer或TTL/LRU回执清理。主树v97、第二树、真实用户存档未修改。

按`SOURCE_INCREMENT.diff`、`AUDIT_ABCD_EVIDENCE.json`和`RUN_INDEX.json`复核；本包不把旧失败改为PASS，也不以局部证据关闭开放事项。
