# d701 双审计证据补充

本次仅补齐既有受控强杀producer的原始归档和性能措辞，不改生产、测试、fixture、额度、输入或引擎，不运行新的Godot场景。父审查提交d70121c7183094a23992985e63ee796dd5c0f586已经由Pro与小可爱分别读取；完整报告、消息身份及实际读取时间已保存。

## 两个原producer的原始记录

producer_prepared与producer_promoting各归档9个原文件：runner_results、validation、before/after指纹、runner日志、native_handoffs及Godot/stdout/stderr日志。MANIFEST记录原路径、大小和SHA256；ORIGINAL_PRODUCER_BYTES.zip另保留18文件原始字节，避免Git文本换行转换影响原始哈希核验；所有归档字节与现存源文件一致，未拷贝两个目录中无关旧traces。

RUN_INDEX按nonce、source、invocation、run及PID/创建时间/命令哈希连接原controller和独立cold。PREPARED armed14项、cold28项；PROMOTING armed15项、cold27项。两个producer都保留原生/effective与场景wrapper退出-1、外层验证命令退出1、FAIL、非timeout和无成功交接；不把缺失最终receipt伪造为成功。原控制器归档与原cold无需改写。

这一补充闭合原始文件远端可读性，不新增强杀次数。仅覆盖已观察PREPARED与PROMOTING业务边界，不覆盖rename内部任意时刻、物理掉电或有效旧primary整体外部替换。

## 性能口径

原ABBA表不改。CPU门禁只检查P95/P99两轮分离，不能写“CPU所有分位无分离”。CPU是enemy_physics_usec回调计数差值，不是整进程CPU；wall是physics回调间隔。

CPU P50两项描述性分离保留：20/cold/reverse A=4.057/4.077ms，B=4.136/4.081ms，中值+1.020408%；20/cold/static A=3.869/3.892ms，B=3.900/3.912ms，中值+0.657132%。原帧间隔三个例外继续保留：10/cold/static P95+0.615672%、P99+3.799025%，20/warm/static P95+0.465249%。

18条件、72采样组starts/hp_delta=0，是PC headless移动对比；资源cold/warm不代表手机冷热。两次重复不能推断统计显著、战斗、GPU、Android、热机或全帧性能验收。

## 验收边界

最终b234内容27场景/876检查与父a607内容239次/4221检查保持各自指纹，本次没有重跑或变更采用数量。原v97 B输入MISSING，设备/GPU/热机、物理掉电、外部旧primary仍NOT_RUN。没有主树合入、APK或发布。
