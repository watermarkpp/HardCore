# R2 固定基线（BASELINE）

- 分支：`codex/monster-combat-r1-20260925`
- R2 起点（CANDIDATE_SOURCE_SHA）：`9a399c242c51dd4068d2dc155829449f6159c3f1`（= R1 审查对象，未漂移；fetch 后 origin 同 SHA）
- BASE：`f5d6308f53162509bffd30f6981987cbfe80fa68`（origin/codex/integration 同步确认）
- 工作树状态：tracked 干净；untracked 75 项（.uid 噪声/输出/本地工具），未覆盖未清理
- 工具链：Godot 4.7-stable console（tools/godot-4.7 junction）、Python 3、PowerShell runner（每树互斥锁）；测试树 `.godot/runtime_appdata` 隔离
- 基线对照树：`mct-r1-baseline-check`（junction tools/godot-4.7 + --import，f5d6308f），保留用于 R2 配对与分类复证
- R1 交付物勘误：DELIVERY.md 写 HEAD 5401a0bc/push 未执行已过期（实际推送 9a399c24）——R2 交付文档以实际 SHA 重写

## T0 缺件闭合记录

| 缺件 | 根因 | 处置 | 提交 |
|---|---|---|---|
| `tests/hc_monster_combat_r1/monster_crowd_scale_performance_probe_test.gd` 未交付 | `.gitignore:39 *_probe*.gd` 在 `git add` 目录时静默吞掉该文件（E12/E13 坐实） | 路径精确 `!` 例外 + 强制跟踪（字节 sha256 8F8A592B…60FC 与本地验证件一致） | `ab7b0bc0` |
| 三份分享原文 | 6ab690f6/6ab693ae 本地主树存在；6ab71c78 无副本 | 前两份归档 + SHA256；第三份 SOURCE_UNAVAILABLE | 本目录 evidence/original_requirements/ |
| R1 critical/基线 30 项/vertical_slice ×3 原始 JSON | 未随 R1 交付 | 已归档 `evidence/r1_raw/`（critical 239KB 全量含逐项结果） | 本目录 |
