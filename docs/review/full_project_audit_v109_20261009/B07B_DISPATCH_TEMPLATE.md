进入 B07-B：全项目测试和证据体系的精细只读审查。沿用本项目极高推理，不使用 Pro。固定完整源码 SHA 由主控本轮提供，不能拿施工目录或旧 HEAD 替代。

先读取 STANDARD_AUDIT_PROMPT.md、SCOPE.md、AUDIT_SCOPE_MANIFEST.json、BATCH_07.md、AGENTS.md、PROJECT_CORE_CONTRACTS.md、AUDIT_PROGRESS.md，以及 B01–B06 的主控处置和原生验证台账。保持正式玩法与唯一权威，不运行引擎/导出，不改生产或测试，不删文件。

审查 verification_and_tests 全部清单，并补漏实际测试入口与工具消费者。先按单元合同、正式运行链、微基准/模拟、编辑器/数据编译、平台/导出、历史/fixture 分组，再逐文件记录实际覆盖到的函数职责。不得用“读过3279条路径”冒称3279个测试或完整语义审查。大型测试与共享夹具必须明确审过和未审过的函数清单。

重点查：正式 READY/存档/地图/所有者/代际前提是否建立；是否错误替换业务入口、减少负载或HP、截断AOE、放宽期限、修改概率或弱化断言；碰撞与攻击/AOE数据结算是否走正式权威；原生退出、完整receipt、scene/run/invocation/producer、source与engine/input指纹是否绑定；是否把脚本返回0、中途PASS或静态导出当原生/Android验收；日志错误和清理警告是否遗漏；测试对象是否泄漏；故意负例错误是否单独分类；跨源码阶段是否错误拼接通过；是否重复跑未变且已有证据的项目。

重点入口包含 tools/run_godot_tests.ps1、tools/test_framework_receipt.ps1、实际runner依赖、tests/framework/helpers/check_receipt.gd 与跨模块共享fixture。核对 runner tracked-path门禁、隔离用户数据、并发源码冻结、错误/超时传播和原始失败证据保留。禁止读取真实玩家存档、凭据或密钥。

每条发现明确分清生产BUG、夹具BUG、证据缺口和冗余候选。用正式调用链证明影响，不因测试未跑便声称代码BUG。现有失败不得被旧PASS覆盖；未变已证项目按函数/依赖指纹复用，不要求为了汇总重跑。

只在 external/B07B 下交付七标准文件：SUMMARY.md、FINDINGS.json、FINDINGS.csv、COVERAGE.json、REDUNDANCY.md、VALIDATION_GAPS.md、SOURCE_BINDING.json。可附分类/引用图/职责清单，不能改其他目录。顶层 fixed_source_sha 用本轮实际固定SHA。完成报告后读取最新远端HEAD，在最新HEAD只追加本批报告，普通push不force；保持原审计绑定。回报报告commit、parent、固定SHA、文件hash和具体剩余职责。
