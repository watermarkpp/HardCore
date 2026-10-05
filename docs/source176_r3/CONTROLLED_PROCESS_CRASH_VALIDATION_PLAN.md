# 隔离进程强制结束的有界补证计划

2026-10-02。状态：NOT_RUN。该文档在固定源码critical运行期间形成，未修改生产代码或启动第二原生runner。

本计划只验证测试自有Godot进程在现有writer两个可观察阶段被操作系统结束后的独立恢复，不称物理掉电、任意机器崩溃窗口或所有文件系统保证。真实存档、主树、第二树始终排除。

## 已读取的实际生产边界

- item_transaction_port以现有quote/commit接收一项事务，只有一个活动plan和一个json writer；主线程完成回调才发布内存所有权与journal。
- json_persistence_service的队首依次通过READ_UPDATE、NEW、PREPARING、PREPARED、READING、PROMOTING；每次pump最多处理当前阶段。PREPARE和PROMOTE在原工作线程执行。
- json_persistence_job的PREPARE写入、flush并回读测试自有临时文件。PROMOTE执行既有主备轮换与临时提升；结果发布不等于主线程完成回调已消费。
- load_save读取唯一角色文档。健康primary按其journal恢复；缺失/损坏primary进入已受测的关闭旧epoch的备份恢复路径。

## 最小两个边界

1. 真实事务已接受，PREPARED业务校验完成，尚未启动提升：正式primary保持前一序号；结束进程后旧快照仍权威。重启重发这项未提交操作应只完成一次，并保持对应物品所有权一致。
2. PROMOTING工作线程已完成文件提升，但主线程尚未消费回调：正式primary已有下一序号，内存仍旧所有权。结束进程后加载新primary；原操作只能只读重放，改请求内容须拒绝，不新建writer、不再次变动资源。

仅在测试夹具中停用PlayerState的自动process，按既有pump推进到所需阶段；不改生产阶段实现、文件内容、时钟、HP或资源。观察阶段到达且所有前置断言通过后，夹具写测试自有的armed记录并停止继续pump，等待外部结束。

## 外部控制与证据协议

- 复用正式wrapper及其真实启动参数、项目内日志和本次唯一隔离APPDATA；单原生runner，无GUI。
- 控制器生成本轮随机nonce，检查armed的nonce、场景、run/invocation ID、source hash、PID、实际进程路径及本工作树项目参数。目标不是本轮自建Godot进程则拒绝结束。
- 操作系统结束后必须证实目标进程已退出并保存原生退出码、完整stdout/stderr/engine日志。该producer不是PASS；原runner中的FAIL/缺少PASS回执原样保留。
- 另写明确“预期强制结束已验证”的控制器交接记录。只有匹配的阶段、源字节、armed证据和实际结束结果都成立，才允许cold消费。不得伪造常规成功producer回执，也不得复用旧armed或旧cold期望。
- cold验证当前明确指定的控制器交接；错nonce、错source、错误场景、缺原生退出或未结束全部拒绝。它与普通live/cold的成功producer协议分开命名，避免弱化既有门禁。
- live及cold检查唯一实例身份、journal epoch/sequence/retired水位、原命令及改内容重发、writer和资源变化。最终同源码同时保留常规live/cold回归。

## 明确保留的范围

这两个边界不覆盖PROMOTE内部各次rename之间被结束、物理断电或磁盘故障，不证明外部整体替换有效旧primary可被发现，不改变跨重启掉落玩法。若后续测到不同实际行为，保留原FAIL并追根，不通过增加延迟、清journal、TTL/LRU或回滚已提交HP修饰结果。
