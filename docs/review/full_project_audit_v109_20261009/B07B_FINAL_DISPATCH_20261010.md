继续 B07-B：全项目测试和证据体系的精细只读审查。沿用当前对话，使用极高，不使用 Pro。

仓库 watermarkpp/HardCore，分支 codex/v108-runtime-bug-review-20261009。本批唯一固定完整源码 SHA：b09ac5c2c41517ed516f11b91d09e435813465f2。请实际读取这个 Git 对象，不能用主控施工目录、旧684源码或远端后续 HEAD 替代。后续工具修复仍在本地施工，不属于这批固定源码。

先读 docs/review/full_project_audit_v109_20261009/ 内 STANDARD_AUDIT_PROMPT.md、SCOPE.md、AUDIT_SCOPE_MANIFEST.json、BATCH_07.md、AUDIT_PROGRESS.md、CROSS_BATCH_RESPONSIBILITY_GAPS.json，以及根 AGENTS.md、PROJECT_CORE_CONTRACTS.md。你的 B07A 原报告保留在根 external/B07A，其九个精确 blob 已镜像到上述审计目录 external/B07A，RECEIVE_RECEIPT 记录原路径；没有重写原结论。注意本批报告必须用下面指定的完整目录，不能再写根 external。

审查 verification_and_tests 全部清单，实际入口遗漏或错分类须补入。按单元合同、正式运行链、微基准/模拟、编辑器/资料编译、平台/导出、历史/fixture 分组，逐文件/函数职责记录已审与未审。3279条路径是清单数量，不是3279项测试通过，读取 blob 也不是语义覆盖。共享大型夹具和运行器必须逐函数追踪控制流，列出具体未闭合职责。

重点查正式 READY/存档/地图/所有者/代际前提；是否替换业务入口、减少负载/HP、截断AOE、放宽期限、修改概率/弱化断言；攻击/AOE/碰撞是否走正式唯一权威；原生退出、完整 receipt、scene/run/invocation/producer、源码/引擎/输入指纹是否绑定；是否拿脚本退出0、中途PASS、静态导出当原生/Android验收；是否遗漏错误、清理警告、泄漏、故意负例；是否跨源码拼接通过、旧PASS覆盖新FAIL或无依据重复测试。

重点入口 tools/run_godot_tests.ps1、tools/test_framework_receipt.ps1、实际 runner 依赖、tests/framework/helpers/check_receipt.gd 和跨模块共享 fixture。核对 tracked-path 门禁、隔离用户数据、并发冻结、错误/超时传播和原始失败留存。不得运行 Godot/导出，不得读取真实玩家存档、凭据、签名密钥；只查安全源码和已经提交的证据。

新固定提交包含11项此前留在本地的战斗/受击/掉落实验夹具，主控按当前正式合同修正后进行了必要回归。证据在 INTEGRATION_REMAINDERS_NATIVE_LEDGER.json、FINAL_DISPOSITION.md、RAW_MANIFEST.json 和 evidence/INTEGRATION_REMAINDERS。第50轮8PASS3FAIL、第51轮2PASS1FAIL、第52轮1PASS，原失败完整保留，未变化8项复用50，mass death/magic continuation复用51，combat epoch用52；不是同一源码的整套/设备PASS。mass death保持32只死亡、235项、实际正掉落/RNG一致；释放中的延迟兼容子用例明确选择既有测试政策开关并复原，普通生产即时结算合同仍单独断言。E03固定随机种子仅建立实际成功施法前提，不修改闪避/伤害/HP/性能负载。

特别检查 tests/hc_monster_ai/test_support.gd 固定输出 receipt 的覆盖风险：50轮原生FAIL/stdout保留，但其自定义检查列表在51之前被固定路径覆盖，完整列表 MISSING；51、52已另存。不要把50缺失列表填成伪造证据。检查生产 vs夹具问题并给最小隔离方案，不要求重跑无变范围。

Java builder遗漏的4行真实 helper消费者接线已在3fda44b提交保留；当前b09包括它。JAVA_BUILD_ENTRY_INTEGRATION_DISPOSITION及原Java preflight恢复证据完整保留，helper/probe/JVM/消费者字节未变，按相同指纹复用。B07A固定684缺少这4行，不能称已经审过最新消费者；B08继续最终构建边界。

每条发现分清生产BUG、夹具BUG、证据缺口、冗余候选，以实际调用链证明影响；不能因为未运行就报代码BUG。现有失败不被旧PASS覆盖，未变且相关依赖相同的证据复用。保持当前已授权玩法及资料唯一权威；ID127掉落产品选择仍待用户，不补概率。

只新增 docs/review/full_project_audit_v109_20261009/external/B07B/ 下七标准文件：SUMMARY.md、FINDINGS.json、FINDINGS.csv、COVERAGE.json、REDUNDANCY.md、VALIDATION_GAPS.md、SOURCE_BINDING.json；可在同目录附分类/引用图/职责清单。顶层 fixed_source_sha 必须是 b09ac5c2c41517ed516f11b91d09e435813465f2。不能改生产、测试、资料、配置或其他报告。完成时读取远端最新 HEAD，在最新 HEAD 只追加本批报告，普通 push 不force，固定审计绑定不变。回报报告commit/parent/固定SHA/全部hash/具体剩余职责。请实际开始，不能只给计划；工具或仓库权限缺失立即如实说明。
