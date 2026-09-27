# 全图传送门与发布一致性闭环

## 结果

PASS：67 张正式地图、132 个门点的作者合同及游戏实际使用的 18px 人物碰撞足迹查询。117 个有效出入口、15 个仅到达门点，目标身份、目标坐标、双向关系、单向到达规则和返回保护全部通过。没有新增门点或移动任何门点。

覆盖范围另经生产入口核对：map_runtime_release_registry.json 实际67项，与 map_identity_registry.json 的正式地图对应；GameRoot._load_zone 与 _spawn_database_zone_content 均使用 MapEditorRuntimeBridge.is_formal_playable 门禁。GameData 的209项包含历史/待建设身份，不能把离线 RegionContent 参考出口混入正式传送验收，或为“全地图”而重新启用这些旧路径。本次覆盖全部正式发布地图。

找到并修复两项实际问题：

1. 山谷密道 A/B 的 map_exit_000002 已声明单向连接，却仍标为 bidirectional_endpoint。正式工具的准备阶段会修复内存副本，因此游戏目标已有效；直接编辑器发布会拒绝原作者数据。本次只更正两个 portal_role 和各自作者 revision，全部其他作者字节保留。
2. 单目标正式发布工具遗漏编辑器已有的派生墙体发布步骤。运行时文件更新后，原墙体计划的输入哈希失效。工具现在调用相同的共享墙体发布服务，仅当目标已有墙体计划时执行。正式重新发布三图，三份墙体计划只变更 source_runtime_json_sha256。

map_release_identity_matrix 的旧断言要求两条不完整单向连接继续存在。本次移除缺陷白名单，要求全部连接满足合同，并增加模式、角色、布尔标志和空白原因的反例，未削弱身份、互返、哈希或隔离检查。

## 实际测试

RED：新全图专项正常退出 1，只有密道 A/B 的单向角色合同两项失败；132 个足迹查询全部无阻挡。原始日志在 red/。

GREEN：green/runner_results_adhoc_20260928_033224_075_9684.json，9/9 PASS、原生退出 0、无超时、引擎错误 0：

- portal_all_map_authoring_footprint_test
- map_release_identity_matrix_test
- wall_render_binding_test（全部 60 张墙体计划）
- wall_render_publisher_snapshot_test
- portal_actual_arrival_guard_test（4 次真实 READY 到达：A、抉择、B、抉择）
- map_bidirectional_connection_policy_test
- map_identity_portal_network_test
- map_runtime_release_gate_test
- map_runtime_release_registry_contract_test

新全图专项已注册 critical。足迹查询与网络校验不等同于在所有 117 条通路逐一手动走图；手机测试 NOT_RUN。

## 保护证据

verify_publication.py 实际退出 0，publication_protection.json PASS：

- 64 张其他正式地图的作者、运行时和视觉文件字节不变；64 条其他注册记录不变。
- 三图地形、碰撞、实例、视觉快照、怪物/Boss 布置不变。
- 57 张其他墙体计划字节不变；390 份引用墙体 PNG 字节不变。
- 两条作者角色修改为严格字节替换，保留原浮点数写法。
- verify_all_maps.py 重新执行 PASS，source_linked_unconfigured=0。

发布包装器的首轮路径参数错误，以及随后空 stderr 被 PowerShell 当成 null 导致的包装器误报 FAIL，均保留原始记录。后者实际已成功发布抉择之地；未再次重复发布。verify_publication.py 单独核验其原生退出 0、完整 PASS、空 stderr 和无残留引擎，并与另外两图组成精确三图发布集合。

## 边界

本闭环没有触碰用户手工地图坐标、素材、脚点、选取圈、掉落、装备技能数据、人物存档或 AGENTS.md。未推送，未构建或安装 APK。整体 R4、锻造接入、最终完整回归与清理仍有独立待办；本结果不代表它们已经通过。
