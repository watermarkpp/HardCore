# DPV2 V5 远端审查候选报告

**本报告不是全量完成证书；没有执行的验收一律保持 NOT_RUN。**

- BASE_SHA: `ffcdc76b360d5976eef2ce17a45664ddaf550590`
- CODE_SHA: `NOT_RECORDED_YET`
- REPORT_PARENT_SHA: `ffcdc76b360d5976eef2ce17a45664ddaf550590`
- FINAL_SHA / REMOTE_HEAD_SHA: 以 PUSH_REVIEW.ps1 提交后打印并核对的 SHA 为准，避免文档自引用。

## 执行结果

| 项目 | 状态 |
|---|---|
| python_build | FAIL_BLOCKED_PARTIAL |
| godot_v5 | NOT_RUN |
| critical | NOT_RUN |
| apk_build | NOT_RUN |
| device_test | NOT_RUN |
| world_item_node_creation_performance | NOT_RUN |
| actual_duplicate_death_award_test | NOT_RUN |
| actor_death_map_spawn_trace_context | NOT_CONNECTED |

## 来源与平衡

来源覆盖：{}
覆盖身份数量：0
本次通过网页证据生成的修正候选数量：0
优先级审计物品数量：NOT_RUN
优先级修改物品数量：0
技能书启用身份：[]
K 状态：NOT_RUN
K：NOT_RUN
沃玛最终无装备率 before/after：NOT_RUN / NOT_RUN
新衣服最坏情况保留证明：`balance.json#armor_retention_proof`；已生成 0 条。
离线模拟身份数量：0
离线模拟失败项：["NOT_RUN"]

## 明确未关闭的后续工作

1. 网页解析失败、来源冲突、物品或重复槽数量差异：以下精确清单；Flash 不补写解析器、不猜分母、不改 6809 等冻结数量。
2. 真实 actor 的 death_event_id/map_id/spawn_id 接线没有在本包中完成。新增调试日志只称 roll event，不冒充死亡事件。
3. 10/20/50 次实际掉落服务调用的耗时不等于真实地面节点创建耗时、峰值帧时间或引怪 AOE 实机验收。
4. 真实重复死亡发奖、拾取闭环与 Android 设备验证没有自动取得 PASS；必须有独立实测证据才能关闭。
5. 现有 Critical 若因冻结测试夹具或其他原因失败，保持失败，不允许 Flash 删除、放宽或改写断言。

## 精确阻碍清单

### 执行异常
```json
{
  "error": "Repository bootstrap failed; no production code or data was changed.",
  "state": "BLOCKED_BOOTSTRAP",
  "base_sha": "ffcdc76b360d5976eef2ce17a45664ddaf550590"
}
```

```json
[]
```

## 审查入口

`source_audit.json`、`overflow_audit.json`、`balance.json`、`simulation.json`、`ARTIFACT_HASHES.json`、`EXECUTION_STATUS.json`、各阶段日志。

只有审查分支允许推送；本包没有授权自动合并 codex/integration。
