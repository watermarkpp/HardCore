# B07B-003 — Custom receipt preservation

`tests/hc_monster_ai/test_support.gd` 的原 `finish()` 固定写入 `res://outputs/hc_monster_ai_package/<name>.json`，重复运行会以 `WRITE` 截断旧证据；旧 payload 还没有源码、引擎、场景、run、invocation 和 native PID 元数据。

## 修复

新增 `separate_write_receipt(name)`：

- 每个 `TestSupport` 实例只允许成功写入一次；第二次同一实例写入直接失败。
- 文件名仅允许安全字符；每个 receipt 使用独立 nonce 子目录，目录创建成功本身作为独占写入权，已存在目录直接失败。
- 写入前检查目标已存在，拒绝覆盖。
- 保留完整原始 `checks`，包括 PASS 与 FAIL 条目及其 label/message。
- 写入 source SHA、engine version、scene、run ID、invocation ID、native process ID 和 receipt nonce；环境变量缺失时保留明确的 derived_missing_environment 标记和值，不留空字段。
- `finish()` 复用该 writer，自身仍负责打印和退出。

专项场景创建两个挂入测试树的独立 `TestSupport` 实例，分别写入 PASS 和 FAIL receipt，验证独立路径、完整 checks、元数据、重复写失败和原始字节保全，并释放两个实例。

本专项不修改 gameplay、runner、compiler 或正式数据。原固定命名文件没有在正常测试消费者中找到必要依赖，因此 `finish()` 已切换到独立 nonce receipt。主控尚未执行 native；状态为 `NATIVE TEST: NOT_RUN`。
