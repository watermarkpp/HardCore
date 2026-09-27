# F03 公共仓库存取提交边界

真实 RED：warehouse_receipt_red_55f_20260928_0550，原生正常退出 1、引擎错误 0、无超时。真实旧金币拾取已 PROMOTE 到磁盘，尚未主线程 ACK，随后调用公开直接存取。直接 deposit/withdraw 都返回成功，但旧 ACK 在修改后恢复旧背包：存入的唯一物品同时留在内存背包和仓库；取出的物品暂时丢失于内存。磁盘归属与内存不一致。四个完整场景中 prepared 两格原先已通过；不伪称其失败。

根因：公开 batch 入口先取快照/修改状态，底层原子写入才消费旧提交回执，时序太迟。最小生产修复仅在 deposit_to_warehouse_batch 和 withdraw_from_warehouse_batch 入口调用既有 _before_state_transaction，先消费已批准提交，再读取/复制状态。热路径 pump、格式、公式、RNG、自动存档频率均未变。

同一反例 GREEN：warehouse_receipt_green_55f_20260928_0551 正常退出 0。存入/取出 × direct/prepared 四格：旧金币恰好 17、物品唯一、内存与磁盘归属一致、公共操作成功。初次 fixture API 调用错误原始运行保留，runner 明确 FAIL；新增完整场景数断言防止漏执行误报。

相关回归 9/9 PASS，本目录 runner_results：新反例、shared warehouse transaction、shared warehouse migration、warehouse prepared transaction、bank prepared transaction、F03 pickup receipt lifecycle、native pickup lifecycle、ordered cleanup、hot persistence。正常退出 0、无错误、无超时。新反例已注册 critical。

verify_scoped_closures.py 的 scoped_closure_receipt.json 保留之前失败、RED/GREEN 与相关回归的实际结果以及原始日志 SHA。该闭环不替代后续锻造公共入口的真实反例和最终 full/clean/performance 门禁。
