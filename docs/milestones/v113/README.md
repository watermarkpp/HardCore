## 当前发布方向与113修订（2026-10-12）

用户明确授权对113留档同步修复掉落槽。当前旧游戏维护树为 `bd73a256493bf41f9c75c19998c84792f74e2262`，修订标签 `milestone-hardcore-1.0-v113-loot-slots-20261012`；52953个tracked文件只读、worktree锁保持。原始113标签、APK和完整留档保持不动，下文原始冻结记录保留为历史。

| 发布线 | 工作树/分支 | Android包名 | 安装与存档 |
| --- | --- | --- | --- |
| 旧游戏，113修订后继续114、115 | `codex/milestone-v113-frozen` | `com.personal.mafaoffline` | 覆盖更新旧游戏；保留原签名和旧存档兼容 |
| 新游戏，资料片施工 | 主树 `codex/integration` | `com.personal.hardcore.next` | 与旧游戏并存；独立应用数据；不读取或迁移旧存档 |

本次宝箱226–234、蜜蜂144、角蝇126按普通6槽；未知暗殿39、57、74、77、90、121、137、142按精英9槽。暗之牛魔王225暂不处理。原怪物身份与行为、逐条爆率和小极品点数规则保持。6个修复文件在两树逐字节一致；新游戏安装配置仅在主树修改。

旧游戏下次打包从当前维护分支或修订标签取源码，不再使用原始c1780711；以114为例：

```powershell
tools/build_android_isolated.ps1 -Commit codex/milestone-v113-frozen -VersionCode 114 -BaselineApkPath <现有113APK> -OutputApk <114APK路径>
```

正式入口会创建独立构建树，不在只读维护树里导入或测试。后续旧游戏修复在该线按用户授权修改，版本验收后重新冻结；主树新游戏的技能/数据升级不得自动并入旧游戏。

本次没有重新出包，保留的113APK不包含此次修复。Python3项和19编号正式掉落专项PASS。两个旧回归在原始源码与修订源码均FAIL，完整保留证据：旧表计数6084/6083不符；死亡队列post-roll fixture未得PLANNED。DEVICE TEST: NOT_RUN。

修订留档：`C:\Users\Administrator\Downloads\HardCore_v113_掉落槽修订_20261012`，包含差异补丁、增量Git bundle、逐文件指纹和冻结回执。新bundle以原始c1780711为前提，可在原完整bundle恢复后导入。原完整留档为 `C:\Users\Administrator\Downloads\HardCore_v113_里程碑留档_20261012`。

---

# HardCore 113 里程碑留档

冻结时间：2026-10-12T07:36:42.920482+00:00。113是游戏数据大范围升级前的固定基线；后续资料片在 `codex/integration` 开发。

| 用途 | 固定入口 |
| --- | --- |
| 113源码 | `c178071165078f386ec1e57012c1ce56d0bced95` |
| 113源码树 | `fc4fa78d79115a40c5d589cc958446aa4a73e45a` |
| 冻结分支 | `codex/milestone-v113-frozen` |
| 里程碑标签 | `milestone-hardcore-1.0-v113` |
| 资料片主分支、远端默认分支 | `codex/integration` |
| 本地冻结工作树 | `C:\Users\Administrator\.codex\worktrees\milestone-v113-frozen\HardCore` |
| 本地完整留档 | `C:\Users\Administrator\Downloads\HardCore_v113_里程碑留档_20261012` |

冻结树的52952个tracked文件已设为只读，工作树已锁定，逐文件SHA256见本地 `FROZEN_FILES.json`。原始里程碑标签保持指向上述打包源码；当前维护分支的用户授权修订以本文顶部为准，不用新游戏资料片覆盖旧游戏安装包。只读属性和worktree锁为可逆保护；本轮没有更改GitHub服务器的权限或分支保护设置。

APK `HardCore-v113-save-recovery-debug.apk`：500034259字节，versionCode 113，兼容包名 `com.personal.mafaoffline`，原签名。SHA256：`57eac296ef083c9dbc1a736aec6e3ddde40055d3705feb44aa02d667d46c959e`。APK及完整验证压缩包保存在本地留档，Git远端保存源码、标签、冻结清单和本目录的原始验证回执压缩包。

113的打包提交仍为上述c1780711。随后主分支上的里程碑说明提交只维护文档，不是重新打包，也不改变113游戏数据。固定源码、存档恢复专项和APK包身份已有验证记录，归档期间不重复运行游戏测试。传统原生4项的框架receipt仍为MISSING；`DEVICE TEST: NOT_RUN`，同学真实存档仍为MISSING，不能把留档认定为真实手机存档恢复验收。

主树原有未提交内容单独保存于 `MAIN_WORKING_OVERLAY.zip`、原索引和二进制patch；它们是现场保全，不代表113 APK额外包含了这些内容。冻结树原Git status有一项 `armor_single_slot_directive_v92.json` 的历史CRLF clean-filter差异；已经证明其工作文件与Git blob原始字节完全一致（SHA256 `2122a9721e49b20086a4de85fe107eb75629db1508d0ad5a289e53df0b35e207`），没有修改该权威文件。

远端两条退役审查分支的独有历史已分别保全为 `archive/codex/crowd-pro-review-20261008` 和 `archive/codex/v108-runtime-bug-review-20261009` 标签。历史发布标签继续保留；审查材料不自动并入资料片生产源。

## 恢复与核对

优先从远端固定标签创建新的可写工作树（不要解除原留档只读再开发）：

```powershell
git fetch origin --tags
git worktree add --detach <新的恢复目录> milestone-hardcore-1.0-v113
git rev-parse milestone-hardcore-1.0-v113^{commit}
```

若远端不可用，`V113_SOURCE_AND_RETIRED_REFS.bundle`包含113及两条退役审查尖端的完整历史，已通过 `git bundle verify`。可以在新目录 `git clone <bundle路径> <新的恢复目录>`，随后检出固定标签。`FREEZE_RECEIPT.json`记录各备份SHA256，可用 `Get-FileHash -Algorithm SHA256` 核对。

需要重新封装时，仍从固定提交调用正式 `tools/build_android_isolated.ps1 -Commit c178071165078f386ec1e57012c1ce56d0bced95 -VersionCode 113`，提供已登记的Godot/Android工具和基线APK路径。引擎、SDK、签名私密数据和真实玩家存档不复制到Git留档；构建另建临时树，不在冻结树运行导入或测试。重建包的逐字节SHA可能因时间戳不同而变化，保留的原113 APK才对应上述指纹。

完整证据入口：[FREEZE_MANIFEST.json](FREEZE_MANIFEST.json)、[VERIFIED_RELEASE_RECEIPTS.zip](VERIFIED_RELEASE_RECEIPTS.zip)。主树历史状态文档的旧日期条目保留为历史，本条和当前Git引用为最新入口。

新游戏配置验证补充：独立包名/PC存档目录、PowerShell安装身份判定及5项打包接线检查PASS，新配置下19编号掉落原生专项PASS。品牌专项在新旧身份均因同一旧启动源码顺序断言FAIL；原断言保留，未冒称品牌/全量回归通过。尚未生成新游戏APK或验证两应用同机安装。
