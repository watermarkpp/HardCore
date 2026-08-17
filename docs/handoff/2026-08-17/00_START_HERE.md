# HardCore 项目交接 — 2026-08-17

> 本目录是 Sol 接手项目的完整文档入口。

## 阅读顺序

1. [SOL_HANDOFF.md](../../SOL_HANDOFF.md) — **必读第一入口**（精炼版）
2. [01_REPOSITORY_DIRECTORY_MAP.md](./01_REPOSITORY_DIRECTORY_MAP.md) — 项目目录结构
3. [02_WORKTREE_BRANCH_REGISTRY.md](./02_WORKTREE_BRANCH_REGISTRY.md) — 工作树/分支清单
4. [03_GOLDEN_RUNTIME_AUTHORITY.md](./03_GOLDEN_RUNTIME_AUTHORITY.md) — Golden APK 真值
5. [04_GOLDEN_SOURCE_MAP.md](./04_GOLDEN_SOURCE_MAP.md) — 源码溯源锁定表
6. [05_CURRENT_DEVELOPMENT_STATE.md](./05_CURRENT_DEVELOPMENT_STATE.md) — 当前开发状态
7. [06_OPEN_ISSUES_AND_PRIORITIES.md](./06_OPEN_ISSUES_AND_PRIORITIES.md) — 未闭环问题
8. [07_VALIDATION_AND_LAUNCH_COMMANDS.md](./07_VALIDATION_AND_LAUNCH_COMMANDS.md) — 测试/启动命令
9. [08_REMOTE_BRANCH_REGISTRY.md](./08_REMOTE_BRANCH_REGISTRY.md) — 远端分支清单
10. [09_GENERATED_DATA_AND_AUTHORITY_POLICY.md](./09_GENERATED_DATA_AND_AUTHORITY_POLICY.md) — 数据权限策略
11. [10_MONSTER_RUNTIME_CLOSURE_STATE.md](./10_MONSTER_RUNTIME_CLOSURE_STATE.md) — 怪物闭环状态
12. [11_POST_GOLDEN_DEVELOPMENT.md](./11_POST_GOLDEN_DEVELOPMENT.md) — Post-Golden 后续开发
13. [handoff_manifest.json](./handoff_manifest.json) — 机器可读清单

## 关键事实速查

- **Golden APK**: `HardCore-1.18.3-runtime-fix-9d6435bc-debug.apk`
- **SHA256**: `B74F58FC1E17A28D2A0FAE7E709085E410F4C48FF6141DD6C293596DDEF341CB`
- **Base Commit**: `9d6435bc`
- **Hotfix**: 32 个 PCK（均不含怪物数据）
- **源码丢失数**: 0
- **Godot 版本**: 4.7 stable
- **远端**: `watermarkpp/HardCore` (main)
