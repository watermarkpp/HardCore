# 资源清单测试的便携性修复

独立 e367 检出完整 critical 实际执行 546 项，545 PASS / 1 FAIL。唯一失败是 complete_client_resource_catalog_test 依赖未入库 outputs/resource_catalog 中的扫描清单；exact_execution_check.json 核对集合、源码、正常外层退出及全部 1638 份测试原始日志，collection PASS，acceptance FAIL，原结果保留。

只读导出器核对现有正式清单与 SQLite：122 库逐项来源信息、962251 帧、962250 有效帧、332460 头部候选一致；原清单/数据库字节未变。测试改用 tests/fixtures 中同字节清单并额外校验来源合同和 SHA-256。全部原计数、既有头部素材来源及血条偏移断言保留。未重新搜索头盔、重建美术或更改运行时资源权威。

原生 GREEN：scoped_sampler_catalog_55f_20260928_0547 中本测试 PASS，正常退出 0、无引擎错误、无超时。该三场景运行总结果仍为 FAIL，因为另一项新增采样测试首轮存在类型声明错误；不把总结果改写为 PASS。后续采样闭环单独记录。

夹具 manifest SHA-256：602ead7af15bb8ed7f3114a6c51f24b60f911774aedfe0152a8bb7c7fd60d9f6。SQLite SHA-256：4c96ed1aae5ecb1e2660a2a58ae0007e17a87a2ce049d4b16d1925d327ea380a。正式导出器实际退出 0 的原始输出见本目录 export.stdout.json / completion.json。

当前只关闭测试夹具缺失；最终完整回归、性能、锻造集成、APK 和设备仍是独立门禁。
