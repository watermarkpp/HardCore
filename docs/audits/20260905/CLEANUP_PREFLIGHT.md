# 清理预检（只读）

日期：2026-09-05

范围：`C:\Users\Administrator\Documents\HardCore-android-staging\*`、`C:\Users\Administrator\Documents\HardCore-worktrees\` 下名称含 `build`/`hotfix`/`perf-device-build` 的目录，以及 `C:\Users\Administrator\Documents\HardCore-patch-build-9ffdf01b`。
主树基线：`9e2e1d8724d4fbb5015a28902117f0cb7dbb8040`（`C:\Users\Administrator\Documents\HardCore`）。

本报告只证明候选状态，不授权删除。预检期间未删除、移动、改分支、修改 Git ref、修改主树或 cache，也未启动 Godot/build。最终清理仍须在主树合并、远端身份和证据核验之后由主控逐项执行。

## 方法与口径

- 使用 `git worktree list --porcelain` 固定注册工作树、HEAD 和 detached 状态；使用 `git status --porcelain=v1 --untracked-files=no` 检查 tracked dirty，使用 `git ls-files --others --exclude-standard` 统计 untracked。
- 对每个候选执行双向祖先关系检查：`HEAD_is_ancestor_of_MAIN` 表示候选 HEAD 是否为主树基线的祖先；`MAIN_is_ancestor_of_HEAD` 表示主树基线是否为候选 HEAD 的祖先。
- 字节统计使用目录递归，但遇到 `ReparsePoint` 只记录并跳过，不进入 junction/symlink 目标。因此是“候选目录内、排除共享链接目标”的逻辑文件大小，不等于最终物理释放空间；硬链接、压缩和重复 APK 未去重。
- untracked 分类中，`.uid`、`reports/skill_comparison_matrix.*.translation`、`.godot/**`、`outputs/**`、`android/**` 的 Gradle/Godot 导出产物属于可再生成/构建产物候选；APK/AAB 即使可生成也单独列为必须保留的黄金包，不能随工作树清理。

## 注册 detached 工作树清单

以下 12 个路径均在 `git worktree list` 中注册、状态为 detached，tracked dirty 均为 `0`，且均满足 `HEAD_is_ancestor_of_MAIN=true`、`MAIN_is_ancestor_of_HEAD=false`。这说明当前记录的 HEAD 没有超出主树基线的提交，但不替代远端合并、证据和未跟踪物核验。

| 精确路径 | HEAD | untracked 条目 | 不跟随 reparse 的文件数 / 字节 | 黄金 APK 字节 | 预估上限（总字节−需保留 APK） |
|---|---|---:|---:|---:|---:|
| `C:\Users\Administrator\Documents\HardCore-android-staging\406b3cf4-teleport` | `406b3cf4a2e72cd063ad203660e369187d50bc13` | 308 | 38,323 / 2,196,349,787 | 0 | 2,196,349,787 |
| `C:\Users\Administrator\Documents\HardCore-android-staging\702b6062d4f0-20260831-201713-405d2656` | `702b6062d4f0f7bbad06b9ec4e7561ba861de6e7` | 11,103 | 85,937 / 5,511,748,458 | 893,918,970 | 4,617,829,488 |
| `C:\Users\Administrator\Documents\HardCore-android-staging\7f0d9f2d4c48-20260905-033432-f184f37c` | `7f0d9f2d4c48a5ae6d05987b70f4088bb59ff9b8` | 1,336 | 54,582 / 2,921,924,268 | 0 | 2,921,924,268 |
| `C:\Users\Administrator\Documents\HardCore-android-staging\7f0d9f2d4c48-20260905-034604-b1d31e43` | `7f0d9f2d4c48a5ae6d05987b70f4088bb59ff9b8` | 1,336 | 54,582 / 2,921,924,518 | 0 | 2,921,924,518 |
| `C:\Users\Administrator\Documents\HardCore-android-staging\7f0d9f2d4c48-20260905-035304-4b88aaab` | `7f0d9f2d4c48a5ae6d05987b70f4088bb59ff9b8` | 1,344 | 54,590 / 2,921,924,641 | 0 | 2,921,924,641 |
| `C:\Users\Administrator\Documents\HardCore-android-staging\a90e405aad17-20260903-171503-ac14e4b2` | `a90e405aad17e5600731f86ac44d8140c6bd79e5` | 11,197 | 86,739 / 6,028,950,308 | 895,686,708 | 5,133,263,600 |
| `C:\Users\Administrator\Documents\HardCore-android-staging\f559463df6f3-20260829-180059-fe46c7bb` | `f559463df6f36142c24f5f34d0370ec17b844395` | 11,038 | 91,295 / 7,304,198,470 | 889,955,152 | 6,414,243,318 |
| `C:\Users\Administrator\Documents\HardCore-patch-build-9ffdf01b` | `ae09a1fdec40ff0c8d5704b8bd7554fde1581cb3` | 299 | 37,996 / 2,215,043,809 | 0 | 2,215,043,809 |
| `C:\Users\Administrator\Documents\HardCore-worktrees\device-hotfix-74297ac2` | `74297ac2cd97b31606b98ef4417a208c2d0631bb` | 309 | 38,464 / 2,213,430,024 | 0 | 2,213,430,024 |
| `C:\Users\Administrator\Documents\HardCore-worktrees\hotfix-e2014fe5` | `e2014fe58c8a2b196e105346433777f40a0c9808` | 309 | 38,330 / 2,210,113,762 | 0 | 2,210,113,762 |
| `C:\Users\Administrator\Documents\HardCore-worktrees\perf-device-build-82aa5c83` | `82aa5c8320937ee482588bdd82ddd6f603ce1fe4` | 311 | 38,469 / 2,213,603,049 | 0 | 2,213,603,049 |
| `C:\Users\Administrator\Documents\HardCore-worktrees\perf-device-build-final-7f0d9f2d` | `7f0d9f2d4c48a5ae6d05987b70f4088bb59ff9b8` | 314 | 38,478 / 2,213,741,959 | 0 | 2,213,741,959 |

合计（包含下方未注册空壳路径的 0 字节，不进入共享 junction）：

- 逻辑文件大小：`40,872,953,053` bytes（约 `38.066 GiB`）。
- 已明确需保留的六个黄金 APK：`2,679,560,830` bytes（约 `2.496 GiB`）。
- 若将所有候选都证明为可回收，且先保留上述 APK，理论上限约 `38,193,392,223` bytes（约 `35.570 GiB`）；这不是承诺释放量，也未扣除证据/备份/文件系统重复块。

## 未注册目录与共享 junction

`C:\Users\Administrator\Documents\HardCore-worktrees\device-hotfix-45ebf844` 不在 `git worktree list`，根目录没有 HardCore `.git`，只有一个 junction：

`C:\Users\Administrator\Documents\HardCore-worktrees\device-hotfix-45ebf844\tools\godot-4.7` → `C:\Users\Administrator\Documents\HardCore\tools\godot-4.7`

在该路径执行 Git 时会向上解析到无关的 `C:\Users\Administrator\.git`，因此其 HEAD、dirty 和祖先关系均为 N/A，不能当作 HardCore 工作树处理。按不跟随 reparse 的统计为 `0` 文件、`0` bytes、跳过 `1` junction；删除这个目录即使获批也只会移除 junction entry，不能回收共享 Godot 工具。

已发现的其他 junction 均指向同一共享目标 `C:\Users\Administrator\Documents\HardCore\tools\godot-4.7`，均未计入字节并且不得沿链接删除：

- `C:\Users\Administrator\Documents\HardCore-android-staging\406b3cf4-teleport\tools\godot-4.7`
- `C:\Users\Administrator\Documents\HardCore-patch-build-9ffdf01b\tools\godot-4.7`
- `C:\Users\Administrator\Documents\HardCore-worktrees\device-hotfix-74297ac2\tools\godot-4.7`
- `C:\Users\Administrator\Documents\HardCore-worktrees\hotfix-e2014fe5\tools\godot-4.7`
- `C:\Users\Administrator\Documents\HardCore-worktrees\perf-device-build-82aa5c83\tools\godot-4.7`
- `C:\Users\Administrator\Documents\HardCore-worktrees\perf-device-build-final-7f0d9f2d\tools\godot-4.7`

其余 Android staging 目录本次未发现 reparse point。

## untracked 非可生成物与必须保留包

在 12 个注册候选中，没有发现位于项目源码、真实存档或源素材位置的 untracked 非可生成文件。untracked 清单由以下可再生成类别组成：

- Godot 导入产生的 `*.uid`（主要在 `assets/`、`scripts/`、`tests/`、`tools/`）。
- 导入/翻译生成的 `reports/skill_comparison_matrix.*.translation`。
- Android/Gradle 导出和中间产物（`android/**`，包括 `.jar`、`.gdc`、`.remap`、`.json`、`.webp` 等构建产物）。
- `android/build`、`.godot`、`outputs` 等缓存或输出目录内容。

这不等于可以无条件删除：`outputs` 中的验收日志、报告和安装包仍须先由主控保留必要证据；`.uid`/translation 也只表示可再生成，不表示当前工作树可以直接清空。

以下六个 APK 是本次扫描到的黄金/安装包候选，必须在任何工作树清理前逐个核验并保留；同一树中的 `android/build` 与 `outputs` 各有一份副本，不能仅凭文件名删除：

- `C:\Users\Administrator\Documents\HardCore-android-staging\702b6062d4f0-20260831-201713-405d2656\android\build\build\outputs\apk\standard\debug\android_debug.apk`（446,959,485 bytes）
- `C:\Users\Administrator\Documents\HardCore-android-staging\702b6062d4f0-20260831-201713-405d2656\outputs\hardcore\HardCore-isolated-debug.apk`（446,959,485 bytes）
- `C:\Users\Administrator\Documents\HardCore-android-staging\a90e405aad17-20260903-171503-ac14e4b2\android\build\build\outputs\apk\standard\debug\android_debug.apk`（447,843,354 bytes）
- `C:\Users\Administrator\Documents\HardCore-android-staging\a90e405aad17-20260903-171503-ac14e4b2\outputs\hardcore\HardCore-isolated-debug.apk`（447,843,354 bytes）
- `C:\Users\Administrator\Documents\HardCore-android-staging\f559463df6f3-20260829-180059-fe46c7bb\android\build\build\outputs\apk\standard\debug\android_debug.apk`（444,977,576 bytes）
- `C:\Users\Administrator\Documents\HardCore-android-staging\f559463df6f3-20260829-180059-fe46c7bb\outputs\hardcore\HardCore-isolated-debug.apk`（444,977,576 bytes）

## 清理裁决前置条件

这些目录可进入“候选”队列，但本报告不把它们标为已批准删除：

1. 主树完成合并与远端身份核对，确认上述 detached HEAD 没有需要保留的独有 commit/ref。
2. 对六个 APK、测试日志、审计报告和任何人工保存数据完成 hash/备份/归档核验；确认保留路径后才可计算实际可回收空间。
3. 对每个 worktree 再检查当时的 tracked/untracked 现场，使用 `git worktree remove` 等受控动作逐项处理，不使用宽泛递归删除。
4. 清理时继续跳过所有 reparse point，不能沿任何 `tools/godot-4.7` junction 进入或删除 `C:\Users\Administrator\Documents\HardCore\tools\godot-4.7`。
5. 保留主树、O01 当前树、B07/B08 启动安全树、地图安全审计树和永久专业树；本预检没有触碰这些路径。
