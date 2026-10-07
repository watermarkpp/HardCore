# 第三树升为唯一主树：2026-10-07

用户授权：第三树新版优先；旧主树、第二树和临时树的独有代码、素材、人工数据和证据补入；冲突旧实现与远端独有历史归档，不覆盖新版。附件 Pro 报告作为核验材料，不自动扩大施工范围。

## 当前源码与补入

唯一工程入口为 `C:/Users/Administrator/Documents/HardCore`，分支 `codex/integration`。生产基线为第三树快照 `b3d144061b9b0aef419ce6b746ddc476023fd912`，父提交 `fedce38a379325005adb5d03db2db40eae231b92`。包含原 B01 canonical rejection 未提交工作；不回退到旧主树或第二树。

补入旧主树缺失的 `assets/art/characters/caster_skill_sources`、`tools/half_moon_generator`、`docs/vfx/half_moon_generator_v1` 及相关交接、保存安全补丁。逐文件字节与 SHA256 见 `SUPPLEMENT_MANIFEST.json`。第二树未发现候选缺失的生产代码，其独有审计脚本和所有 dirty 内容归档保留。旧主树两个 zombie 诊断测试以 `.txt` 存在 `unique_tests/`，避免自动激活过时夹具。

18 个已有掉落权威/地图编辑保存 JSON 的快照 blob 本身含 CRLF，现有 text 清洗会产生假 dirty。仅为这 18 个精确路径增加 `-text` 属性，保持快照原始 SHA256；没有改写人工数据或生成物。

## 历史与本地材料

`BRANCH_HISTORY_ARCHIVE.json` 保存全部原远端/本地分支与 SHA。历史 commit 通过一个空树归档提交作为新主树的第二父链完整可达；主树第一父链继承第三树，历史源码不会覆盖生产树。`git show <历史SHA>:<路径>` 可取回任一旧内容。

本地完整资料保留在 `outputs/retired/20261007/`：校验通过的 `HISTORY_BEFORE.bundle`、旧树 dirty/index/patch、人工源数据、原始日志和 APK 证据。该目录忽略导入、忽略 Git 上传。共享 `dev_art_sources` 与本地工具链继续原路径，不进入 Git。退役目录仅保留必要资料或历史差异；可重建的未改动 tracked 文件按明确清单裁减。

## 清理与验证边界

本地已登记的第二树与 11 个 Android 临时树已退役，原第三树残留已逐文件保全后移除。Git 现只登记主入口一个工作树。

远端整理目标为仅保留 `codex/integration`，并将 GitHub 默认分支切换至它；所有原 release tags 原样保留。实际完成结果由后续 `CLEANUP_VERIFICATION.json` 记录，不用计划替代远端核验。

本次仅整理工作区，不改变玩法、包名、版本或签名。既有 A01—A04 与 B01 局部证据保留；Pro 报告的 49/358 为静态阅读覆盖数量，不是功能完成比例。架构升级、完整回归及 APK/设备验收仍未全部完成。DEVICE TEST: NOT_RUN（本次）。

迁移专项：bootstrap PASS；补入的旧素材编辑器回归为 62 项/48 PASS/13 FAIL/1 ERROR，失败已按旧 approved 输出和 manifest 合同分类，原断言与正式素材不变。详见 `HALF_MOON_COMPATIBILITY_REVIEW.json`。原始日志本地保留；不将失败掩盖为工具全面兼容。

## 实际清理结果

远端原 196 分支已整理为 1 个 `codex/integration`；195 个旧分支按期望 SHA 原子删除，8 个 release tags（16 个含 peeled ref 行）原样保留。主分支非强推。旧本地 248 个分支引用已删除，所有原远端/本地 HEAD 通过归档父链完整可达。已登记 12 个 linked 工作树退出，原第二树及第三树旧路径不存在，当前只登记唯一主入口。

档案已汇入 `outputs/retired/20261007/`；裁减 620201 个可重建的重复 tracked 文件、39099211521 字节，534 个 dirty 原始哈希通过。共享素材库 38882 个文件、14468597602 字节与原清单一致。详细 Git bundle 大小/SHA、哈希保全与源绑定见 `CLEANUP_VERIFICATION.json`。

新路径首次资源导入已完成，但编辑器退出码为 -1073741819，保留 FAIL 原日志。导入后 B01 首次失败定位到 Git 将 `socketing_fixture_items.json` 的 LF 改成 CRLF，导致身份注册源哈希失配；恢复第三树已有 blob 的原始字节并精确加 `-text` 属性后，15 个身份注册源哈希吻合，B01 PASS/24 检查/0 引擎错误。此为 checkout 元数据修复，不修改 JSON 值或重生成权威。
