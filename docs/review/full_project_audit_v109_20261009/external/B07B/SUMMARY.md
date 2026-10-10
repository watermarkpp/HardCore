# B07-B 全项目测试与证据链精细只读审查

固定生产源码：`b09ac5c2c41517ed516f11b91d09e435813465f2`
固定 Git tree：`39a4fccc89247dae613a12eddcad63301e7f5fea`
职责：verification_and_tests；没有运行 Godot、导出 APK、访问真实玩家存档或更改生产/测试/配置。

## 1. 清单与覆盖实数

- 原范围 3,279 路径；精确 Git 对象实际读取 3,255；缺少 24 项本地退役格子试验，不恢复或删除。另发现当前固定树新增 34 个测试路径（17 对 .gd/.tscn），已纳入补充审计。
- 共登记 3,320 个有效范围与依赖条目，实际读取 3,296 个文件；从 GDScript、Python 和 PowerShell 提取 8,223 个命名函数入口，41 个入口作了针对性静态控制流审读。其余逐入口具体职责列在 COVERAGE.json；静态签名读取不等于全语义覆盖。
- 固定树 1,629 张测试场景；runner 静态直接注册 648 张且全部存在。981 张未出现在套件字面量列表，可能是 adhoc、夹具、编辑器或历史场景，不能据此直接宣称遗漏生产测试，也不能把 1,629 当通过数。
- 以单元合同、正式运行链、微基准/模拟、编辑器/资料编译、平台/导出、历史/fixture 分类并保留来源与未审职责。分类来自路径/静态特征，尚未经各场景运行证明。

## 2. 发现项与所有权

- `B07B-001` TEST_HARNESS_RISK / HIGH：Mutex is scoped by PSScriptRoot, while Windows process owner is inferred from Godot executable directory and not-in-baseline PID. Stop-NewGodotProcesses can terminate the other worktree's process.
- `B07B-002` EVIDENCE_GAP / HIGH：Linux validates source-fingerprint format and engine version, but Windows skips those preconditions; Test-FrameworkReceipt compares source only when expected is nonempty. Runner aggregate stores git_head but not exact dirty/input/engine hashes.
- `B07B-003` FIXTURE_BUG / HIGH：FileAccess.WRITE overwrites one fixed output JSON path with latest check list, without attempt/run ID or preserved old blob. Committed stage50 full custom list is absent; stage50 native FAIL/stdout remain, stage51 and52 lists are retained.
- `B07B-004` EVIDENCE_GAP / MEDIUM：Explicit error allowlist ignores these lines for FAIL count; structured result lacks independent allowlisted cleanup warning counts although raw stdout/stderr/engine logs can preserve them.
- `B07B-005` FIXTURE_BUG / MEDIUM：diag_activation_probe.tscn and diag_bounded_probe.tscn refer to absent same-name scripts; r2_measure/qa_latency_driver.tscn targets absent tests/ui_l1_measure/qa_latency_driver.gd while a sibling r2_measure/qa_latency_driver.gd is tracked. None appears in 648 static registered runner scene literals.
- `B07B-006` EVIDENCE_GAP / MEDIUM：Generic unanchored PASS regex matches marker anywhere in stdout; outside framework namespace there is no run-bound nonzero assertion count or exact per-scene marker check.
- `B07B-007` ISOLATION_RISK / MEDIUM：External overrides are accepted and used to create directories; log files are removed prior to scene, and APPDATA is set, but physical containment/link validation only runs on Linux.

没有发现可绑定本批固定源码的已证明生产玩法 BUG。B07B-001 是跨工作树误杀其他 Godot 进程的条件性 runner 控制流风险，未原生复现；B07B-003 是已有原生台账佐证的固定输出覆盖夹具缺陷。其他发现为证据资格、危险路径条件和未注册旧场景资源断链；不得混成生产缺陷。

## 3. 原生 stage50/51/52 与保全

- 已从固定 Git 对象计算原始证据 164/164 个 SHA-256 与大小全部吻合；这仅是证据保全，不是本轮重新运行测试。
- Stage50 8 PASS/3 FAIL：mass death stdout 虽打印32 deaths/235 checks/真实正掉落、RNG parity、一次save，但随后出现8 ObjectDB、3 resource以及 get_path 相关错误，原生 runner 判 FAIL，严格保留；combat epoch E01 和 magic continuation 的 FAIL 亦保留。
- Stage51 2 PASS/1 FAIL：mass death235 与 magic continuation92 在各自测试树中 PASS；combat epoch E03 仍 FAIL，原样保留。未变化8项沿用 stage50 指纹支持的专项结果，不跨树拼装一个整套 PASS。
- Stage52 1 PASS：combat epoch E03 使用固定 RNG 种子建立真实成功施法的前提，40 checks PASS；没有改变躲避、伤害、HP、怪数或 CPU 负载。Stage50 原始完整自定义 checks 被固定输出路径覆盖，清单 MISSING，不能凭 stdout 计数制造详细断言；51/52 各自已有不可混用的 checks JSON。
- Stage52 freeze 2,531 项中2,528个可追踪路径与本轮 fixed Git object 具有同一 blob，另两个退役 grid 脚本及一个 .uid sidecar 没有对应 fixed tracked blob。不能把 Windows 工作区 CRLF 和 Git LF 的 SHA 差异当源码变化或当原生字节相同；见 EVIDENCE_CHAIN_AUDIT.json。

## 4. 正式测试链与限定能力

- Runner 检查 tests/**/*.tscn、大小写精确 tracked-path、工作树互斥、日志 stdout/stderr/engine ERROR、真实退出与超时，不以中途 PASS 提前结案。Framework 另外验证 run_id、scene_id、非空 check 列表/计数与 invocation_id；本轮未执行这些门禁。
- tests/helpers/formal_initial_ready.gd 的合同是正确服务地图 + WorldBootstrapCoordinator.READY + 无转图 + gameplay input unlocked；60秒仅为生产 fail-safe 上限，绝非启动性能通过阈值。
- mass death 用 FixtureGameRoot 仅跳过 initial world bootstrap 和地面落点规则，保留正式死亡队列/roll_monster_drops、实32死、235项、正物品及 RNG 一致；它不能验证完整正式地图落点，也不是30怪性能证明。
- Magic continuation 的百万 HP 只用于避免时序回归测试对象提前死亡，测试 real combat service positive DIRECT hit/复用; 延迟释放子用例显式选择既有 diagnostic 政策并在结束恢复，普通生产即时结算前提另行断言。
- b09 Android builder 固定源 357–359 行已有 Enter-AndroidJavaEnvironment，576–577 行 finally Restore。helper/probe 与已有证据保持同指纹；builder 的 Git LF 换回 Windows CRLF 后与已保存源码SHA吻合。已证 Java 原专项允许同指纹复用，不重跑无变范围；109 真正构建及设备 NOT_RUN，交 B08。

## 5. 未闭合职责与后续边界

- 8,223 个已索引函数并不等于全函数审核；对大型 runner、工具共用夹具、持续性参考模拟、UI/场景/资源动态调用还有大量逐函数缺口。COVERAGE.json 按路径/函数列明，VALIDATION_GAPS.md 列出重点剩余入口，分类表、证据复核、资源引用为支持件。
- 需要验证的 Windows 进程归属/源码指纹/旧 PASS marker/自定义 checks 覆盖风险只能用不触及主生产和玩家存档的隔离专项验证。已闭合 B01–B06 修复与历史负例不重复重测；B04 怪127掉落仍待用户选择，没有改玩法/概率。B08 补跨链，formal109 和 DEVICE_TEST 都是 NOT_RUN，整项目语义审计仍 MISSING。
