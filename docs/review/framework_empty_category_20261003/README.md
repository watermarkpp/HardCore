# 空任务身份与无阻挡者标记分离

本次在第三树沿用户既定范围串行施工。唯一生产增量是FrameBudget私有阻挡结果用null表示无阻挡者，保持空字符串是一个可登记的String身份。不会新增业务ID或放开重复释放；不改变1200us、首次服务公平、余量机会使用、嵌套、necessary、暂停、生命周期或被冻结的资源协调器。

小可爱独立二审指出窄边界后，先在正式console/headless原生入口复现：同一139项检查，旧实现5FAIL（不可运行空名被准入、空名较老任务不阻挡named peer、拒绝原因与计费偏离），最小修复后139全部PASS。原126项全部保留，新增13项也验证空名正常服务、已服务后余量、下一epoch恢复、necessary超额计费、耗尽拒绝及排空。

最终同字节相关回归包含预算协议、生产者准入、实际周期迟到、世界退出、暂停保存、原13资源轮询、30死亡/严格到期live/cold、自然移动战斗/独立cold/四轮恢复、合法退出live/cold。每个runner原生退出、完整receipt、source/run/invocation/handoff都按索引核对；冷启动是XP与保存恢复，不是地面掉落重建。

父阶段同内容a607400e完整239次/215场景/4221检查及R3/反馈、两受控强杀边界、ABBA另归档在../framework_layered_critical_20261003。其受测源码与本次只差这两个文件，但不是本次源码重新执行239次。ABBA只证明PC headless移动CPU尾部无两轮分离，三个帧间隔例外原样保留：10cold/static P95+0.616%、P99+3.799%，20warm/static P95+0.465%；不声称自然60fps、全性能无退步或Android/GPU已验收。

主树v97、第二树、真实存档、真实HEAD/index均保护；原v97 B输入仍MISSING，Android/GPU/热机、物理掉电和有效旧primary整体外部替换仍NOT_RUN；本次不是主树合入或APK发布。新提交是受测内容快照，不称干净checkout运行。原生完整source ZIP与Git换行规范化映射可逐字节核验；审计读取当前固定SHA，并保留父阶段各自范围。

机器核验：

```json
{
  "parent": "c2d3ac514e7d3f2015aff9bc19a5ef2c3aac3104",
  "content_sha256": "b234e922a238898b34f44db910942e6bc73d991dea13994ffc0ff960d0f06b5d",
  "engine_sha256": "d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c",
  "status": "PASS",
  "delta": {
    "scripts/layers/runtime/execution/frame_budget.gd": "f047dc1b9905b582aa0484b8009fe407489502f49c4ea4462510c170515b4114",
    "tests/framework/frame_budget_test.gd": "de68344b09d59b87b3b7c7f9568043c0d5fa244635735aba48cc2f4a3ffab4fb"
  },
  "source_files": 3566,
  "native_attempts": 27,
  "unique_scenes": 27,
  "framework_receipts": 14,
  "framework_checks": 876,
  "red_checks": 139,
  "red_failed": 5,
  "green_checks": 139,
  "prior_stage_sha256": "a607400e0d745852ac41e8bbbfc5d169ecc916e71fe9c5e286a118a0673211ca",
  "prior_stage_native_attempts": 239,
  "prior_stage_unique_scenes": 215,
  "prior_stage_framework_checks": 4221,
  "scope": "Final two-file sentinel increment, directly related regression; previous239 attempts remain at their original source, not relabeled as this source."
}
```
