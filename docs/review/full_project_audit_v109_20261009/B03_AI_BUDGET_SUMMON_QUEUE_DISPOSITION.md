# B03-003 / B03-004 AI budget 与 summon queue 分诊

审计基线：fixed `4e77c619249450b7c33e833c2bb3531f3f120bfc`，当前工作树保留 dirty 状态。本次只读核对 Enemy、`HCDecisionBudget`、`HCM30SummonQueue` 和 GameRoot 的正式调用链；没有调用测试、native 或修改生产文件。

当前源码指纹：

| 文件 | SHA256 |
|---|---|
| `scripts/enemy.gd` | `4EB42E585F30C3401366184CD240771ACD9BC25A066BCEC9AE859E38A71DDF2A` |
| `scripts/monster_ai_package/decision_budget.gd` | `75FAC6271678E07A40752F38D2FF7231AFAEECECD940F137A654D2991153507B` |
| `scripts/monster_ai_package/m30/summon_queue.gd` | `96BCD616093871C6035B38A050B76FE5B78663336C507644886C25D1A08EEACC` |
| `scripts/game_root.gd` | `2EA2DC8E90239E8C1DB9260CABBB57A7991EC14B82999C89B2035661E90E5C93` |

## B03-003：300 ms optional pursuit lease

结论：**PASS（静态调用链）**。当前生产配置在 `project.godot:72-73` 为 `owner_decision_interval_ms=300` 与 `owner_optional_budget_enabled=true`。Enemy 的设置读取和允许值位于 `scripts/enemy.gd:504-508`；它只影响 rich pursuit observation/selection，不把攻击、受击、已提交移动 leg 或碰撞推进改成等待路径。

正式入口如下：

1. `_retarget_internal` 在 `scripts/enemy.gd:8401-8427` 对 ordinary melee 或启用 optional owner window 的 Boss 调用 `_owner_decision_window_due()`。如果当前 deadline 未到，当前目标的安全区、死亡、leash/disengage 等身份判断仍先执行；普通已提交 movement leg 由 `scripts/enemy.gd:10248-10283` 继续用 physics delta 推进，随后才返回 `OWNER_DECISION_WAIT`。
2. deadline 到达后，`_owner_optional_budget_try_begin()`（`scripts/enemy.gd:8219-8240`）使用当前完整 scope 调用 `HCDecisionBudget.begin_pursuit_turn(self, scope, &"owner_window")`。被拒绝时不提交 deadline，因此不会制造欠债或追赶式多次规划；成功服务后由 `_owner_decision_record_served()` 在 `scripts/enemy.gd:8309-8326` 提交下一次 deadline，首次 deadline 还按 instance-id 分散在一个 interval 内。
3. 在默认 `immediate` 模式，`_pursuit_process_budget_begin()`（`scripts/enemy.gd:10695-10754`）才为 ordinary melee 的 observation/new-step 打开 process lease。若已有 outer `pursuit_turn_active(self)`，它调用 `borrow_pursuit_turn(..., "nested_process_%s" % kind)`，不会再开第二个 FrameBudget scope；每种 nested kind 在同一 outer lease 内只借一次。
4. `_hc_refresh_observation()`（`scripts/enemy.gd:10809-10900`）在完成真实 target/map/LOS 读取后才结束 legacy `HCDecisionBudget.begin/end`。这个 legacy observation lease 是 rich observation 的实际工作段，不是每 physics 的攻击许可。等待期间的轻量 poll 只在已有 pending 时尝试 `begin(..., &"poll")`，失败即返回，不做额外查询。
5. GameRoot 只有在 `HCDecisionBudget.pursuit_dispatch_enabled()` 为 true 时，才在 `_process` 的 `scripts/game_root.gd:1926-1927` 调用 dispatcher。生产模式由 `Enemy.configure_pursuit_process_budget_mode` 默认保持 `immediate`；`dispatched` 是另一条明确配置的 process callback 入口，不应在本审计中假定已启用。

同一 owner 的同一 process epoch 行为：第二个 outer `begin_pursuit_turn` 明确返回 0（`decision_budget.gd:563-570`）；不同内部 kind 只有通过 active outer lease 的 `borrow_pursuit_turn` 才能继续。legacy `begin()` 在检测到 active pursuit lease 时转为 `legacy_<kind>` borrow（`decision_budget.gd:971-974`），同 kind 重复借用被拒绝，`nested_process_*` 只有存在对应 pending process kind 时才消费该 pending。end 必须 LIFO，且 process kind 在 outer 完成前不会被标记 serviced。静态上没有发现同一 actor 每 physics 重开第二个 optional lease 的路径。

边界与验证建议：保留一个真实 Enemy/FrameBudget 专项，必须从 `_retarget_internal` 进入，覆盖 deadline 未到时攻击与已提交移动继续、deadline 到达时一次 observation、同 tick 的 poll/neighbor 不开第二 outer、FrameBudget denial 不推进 deadline；不应直接调用 budget helper 代替 Enemy 入口。当前没有新的 runtime 结论，建议状态仍记为 **NOT_RUN**。

## B03-004：summon queue capacity 与 enqueue 顺序

结论：**PASS（接受/拒绝边界已可解释）；产品合同选择为 BLOCKED**。生产 queue 明确区分“release 请求被拒绝”和“已接受 job 后 materialization 失败”，但当前用户合同没有声明容量满时是否必须把一次合法 release 延后重试。

实际顺序位于 `scripts/monster_ai_package/m30/summon_queue.gd:151-216`：

1. `_sync_world`、transition/bootstrap、source identity、正式 `_hc_m30_summon_request_valid`、serial 和 source slot 先校验。source 需要仍是 GameRoot 直属、当前 map/generation、存活且未 control/charm/dormant/burrowed 的 Enemy（`:151-174`）。
2. serial duplicate guard 后，代码在 `:190-192` 写入 `m30_last_queued_release=(life,serial)`，随后才检查全局 `_jobs.size() >= MAX_PENDING_BATCHES`（常量 256，`:4-14`）。容量满时递增 `capacity_rejected` 并直接返回，没有创建 job、reservation 或 child；这不是“已接受 job 丢失”，而是 release admission 被拒绝。
3. 容量未满后，按 spawn slot 计算 `allowed = min(count, effective_max - active - reserved)`；ordinary/elite cap 为 5，Boss 保留 authored `max_active`（`:42-43`, `:181-188`, `:194-201`）。`allowed<=0` 同样不创建 job。
4. 只有 `allowed>0` 才写 `_reserved`、追加 job、启用 physics process，并增加 `admitted_children`。job 的每次 landing probe、materialization 和同步 factory claim 都在 `pump()` 的 bounded `8 probes / 1 materialization / 1000 usec` 入口内执行；`claim_birth` 在 `EnemyActor.setup/add_child` 之前消费 ordinal，避免重入重复 claim（`:222-284`、`:351-490`）。

因此已证明的行为是：容量满时不会制造半个 job，也不会让旧 serial 在同一 release 上重复排队；下一次新的 release serial 可以重新进入。尚未证明、也不能从当前源码擅自推导的产品选择是：一次容量满的合法 release 是否应该在下一 physics tick 自动重试。若合同要求“不丢 release”，当前 `m30_last_queued_release` 在 capacity check 之前写入就是风险点；若合同允许“满额拒绝、下一 serial 再尝试”，当前顺序是可接受的显式拒绝，不能把 `capacity_rejected` 报成 queue corruption。

另外，`allowed<=0` 是 per-slot active/reserved cap 拒绝，与全局 `MAX_PENDING_BATCHES` 不同；二者应在回归 receipt 中分开计数。已接受 job 的 source death、map transition、generation 变化会由 `_job_source`/`_callback_world_current` 取消剩余 reservation；这属于已接受 job 的生命周期收尾，不是 enqueue 前 capacity admission。

最小必要验证建议：使用真实 boss/ordinary source 和真实 GameRoot queue，先制造一个合法 release，记录 `requests`, `capacity_rejected`, `admitted_children`, `pending_batches`, `reserved_by_slot`；再填满 256 个 pending batches，验证本次 release 是明确 rejection 且无新增 job/reservation，随后用新的 release serial 验证下一次请求的行为。不要强制 drain、复制 queue、直接改 `_jobs`，也不要把失败 landing/materialization 与 admission rejection 合并。若用户选择必须保留 release，则需先确认 retry owner/serial 合同，再单独施工；本报告不建议在没有该选择前修改 production。

## 分诊状态

| 项目 | 状态 | 结论 |
|---|---|---|
| 300 ms optional lease 是否被 Enemy 正式入口使用 | PASS | `project.godot` 配置与 `_retarget_internal → _owner_decision_window_due → begin_pursuit_turn` 链闭合。 |
| 攻击/物理推进是否被 300 ms gate 阻塞 | PASS（静态） | immediate contact、受击、已提交 movement leg 在 gate 前/等待分支继续。 |
| 同 process 多 physics 重开 second outer | PASS（静态） | active outer 返回 0；内部 kind 只经 borrow，重复 kind 被拒。 |
| summon queue 满额是否创建半 job/泄漏 reservation | PASS（静态） | capacity 检查在 job/reservation 前；拒绝只增加统计并返回。 |
| 满额 release 是否必须自动重试 | BLOCKED | 当前源码没有足够产品合同证据；需用户决定“拒绝即丢弃”还是保留一次 release。 |
| 本轮 native/runtime 验证 | NOT_RUN | 按任务要求未运行。 |
