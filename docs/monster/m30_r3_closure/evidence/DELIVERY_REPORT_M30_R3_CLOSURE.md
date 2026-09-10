# M30-R3 封板执行报告

- 裁决：采纳 `49501f19` 为生产精简候选（**非已合并 integration、非性能最终完成**）；报告线 `f7477361` 与全部旧日志保留
- 分支：`codex/m30-r4r3-evidence`（封板证据 @ 本报告提交）、`codex/m30-r4r3-prune`（@49501f19 原样）、**`codex/m30-r4r3-acceptance` = 真实合并 SHA `6a9e76b1`**（prune 49501f19 + 封板测试 b78baf3a 三方合入，enemy.gd=f74a044c 复核）+ 报告措辞修订 `43f31718`；未推 integration
- 包：`HardCore_M30_R3_封板审查与测试修正包.zip` SHA256SUMS 18/18 OK；离线 28 passed + 1 skipped（symlink 特权跳过）；apply_closure preview+apply **production_writes=0**，四目标全为 tests/（3 新 + 1 修改），生产目录 diff 为空

## 分项结论（功能 / cleanup / 相对性能 / 真机 分列）

| 维度 | 判定 | 说明 |
|---|---|---|
| 功能：freeze（synthetic Timer） | PASS | probe overall PASS、cleanup PASS（无泄漏）；大血量替换/不复活前提保持 |
| 功能：八方向 3 次预声明新进程 | **功能 PASS** | 三次全部 exit 0 + PASS marker（8/8、首攻外圈、≥2 行走样本、实时帧号+相位断言）；全部保存无重跑 |
| cleanup（同三次运行） | **FAIL** | 每次均 ObjectDB 泄漏 3 + resource 1（v2 runner 分层字段 functional=PASS / runtime=PASS / cleanup=FAIL / overall=FAIL） |
| 功能：safe --verbose 双生产对照 | 功能 PASS（双侧） | 泄漏身份双侧**完全一致**：泄漏 Node（remove_child 未 free、路径空）+ GDScript 持住 `res://scripts/layers/runtime/combat_runtime_service.gd`；属测试夹具清理债，非生产差异 |
| 清理债条目 | 独立归档 | 12 份旧档只读再分类 sidecar（reviewed_classification.json，未改旧 runner.json/日志）：仅 profile/freeze 无泄漏；所有实例化完整世界的场景同签泄漏。是否阻断集成由主控裁决 |
| 相对性能（统一口径） | **12/12 门槛 PASS，10/12 更低** | report_perf.py：6 轮第3、4值平均普通中位数；sustained@30 **−2.0295ms**（base 32.081 → 30.0515，gate 33.685，1 轮超门槛仍在门槛内计数）；原 upper-middle 文字表原样留档（perf_median_table.txt），本报告标记其被新表替代；147.203/192.870 离群轮未删；不宣称 30 怪 60FPS；R2 历史 9/12 与 fcc 0.131ms FAIL 原样保留 |
| 旧 R2 死亡定论修订 | 已按授权措辞修正 | "存活余量前提被破坏已证，guarded 下自然链通过，旧死亡链未完整追溯"；旧日志未回填 |
| 验收分支电池 | PASS | 合并后 11/11（core×2/geometry/path/epoch/母体烟测/AIA2×3/freeze），runner JSON 归档 |
| 真机 / 录屏 | NOT_RUN | 无设备 |
| MISSING | 无伪造项 | 无 .uid 需登记（headless 直跑不生成）；包字节零修改（GBK 本机沿用 PYTHONUTF8=1 环境适配） |

## 归档索引（docs/monster/m30_r3_closure/evidence/）

installer/{candidate.patch,manifest.json}、perf_report_r3closure.json（新口径）、reclassified_sidecars/（旧档侧车）、safe-verbose 双归档与 freeze/八方向三次运行位于 docs/monster/m30_r4r3/evidence/r3_2026*（run_probe 自动唯一目录，SHA256_MANIFEST 齐全）。
