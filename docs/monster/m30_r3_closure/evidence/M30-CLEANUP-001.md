# M30-CLEANUP-001 退出清理债项登记

- 建议名称：既有 GameRoot/CombatRuntime 服务对象生命周期与退出清理
- 状态：OPEN（cleanup FAIL；本轮获"仅 integration 接入"有限例外）
- 证据（均按固定提交 d5d73183 读取）：
  - `docs/monster/m30_r4r3/evidence/r3_20260910_131310_527366ad/stdout.log.txt`（R2 生产 verbose：Leaked GDScriptNativeClass + GDScript + Node(remove_child 未 free，路径空)；Resource still in use: res://scripts/layers/runtime/combat_runtime_service.gd）
  - `docs/monster/m30_r4r3/evidence/r3_20260910_131355_2ac78b78/stdout.log.txt`（prune 生产 verbose：同 instance id 同资源，签名一致）
  - `docs/monster/m30_r4r3/evidence/r3_20260910_131310_527366ad/stderr.log.txt`（safe 场景 get_path 报错与退出孤儿诊断阶段一并保留，未做全局错误白名单）
  - 12 份旧档只读侧车：所有实例化完整世界的场景同签名；profile/freeze（无完整世界）无泄漏
- 源码线索（已核）：
  - `scripts/game_root.gd`：`var _combat_runtime: Node = CombatRuntimeServiceScript.new()`，该服务脚本继承 Node；当前使用点未见 add_child 或显式 free
  - `scripts/layers/runtime/combat_runtime_service.gd`
- 边界表述：当前日志支持"基线与候选存在同签名退出问题"，**不支持**"仅测试、绝非生产"的断言；verbose 中 remove_child/free 文字为引擎通用 Hint，非具体调用链。重复创建/销毁世界是否累积及实际影响未实测。
- 例外边界：仅覆盖原已识别签名的退出期对象/资源清理；不覆盖新脚本异常、断言失败、非零退出、超时、运行期资源加载失败、内存持续增长、真机崩溃。
- 处置约束：本轮不为清理债修改生产 GameRoot/Player/CombatRuntimeService 或全局 runner；后续以短生命周期回归另立项；禁止在测试中偷偷释放生产对象后宣称生产已修好。
- 本轮最终组合核验（d5d73183，enemy f74a044c）：八方向 functional PASS，cleanup FAIL 签名 = 本债项原签名，落在例外边界内（无新脚本异常/非零退出/超时/加载失败）。

## 2026-09-11 处置结果（UI R5 + M30 最终收口执行单）

- 状态：OPEN → **RESOLVED（integration 最小接线修复，历史 FAIL 记录保留于本文件上方，不改写）**
- 修复提交：`c5ca7ad2`（`scripts/game_root.gd` blob `863cf1a8650b1ee0602078c25253788b212393af`；diff 证据 `docs/closure/20260910/evidence/game_root_function_diff_vs_m30_baseline.txt` 证明相对 M30 基线 blob 49b43b52 仅 3 个 hunk：本接线 + 2 个 UI 音频接线 hunk）
- 修复内容：`GameRoot._init()` 内 `_combat_runtime.name = "CombatRuntimeService"; add_child(_combat_runtime)`，使从未进入 SceneTree 的服务实例随其所有者释放；战斗常量与 AIA2 合同零改动（AIA2 五方法与 enemy.gd blob 不变）
- 新增回归：`tests/game_root_combat_runtime_ownership_test.gd/.tscn`（真实 main.tscn 全世界 2 次重入 + 6 次重建循环 + 出树所有者释放 + weakref 断言）；PASS 证据 `outputs/test_logs/runner_results_adhoc_20260911_063047_663_11892.json`，退出期无 leaked/still-in-use 记录
- 相邻回归：加载链全套（ownership/loading_transition/input_release_cleanup/ordinary_attack 三件套）与 M30 十项电池在修复后代码上全部通过（详见 docs/closure/20260910 最终报告）
- 残留边界：真机（Android）退出清理与内存增长观察未执行（无模拟器/设备，NOT_RUN）；本轮修复以桌面 headless 真实世界生命周期回归为限
