# v106 怪物修复与封装前检查交付

2026-10-07T20:44:46.225750+08:00。唯一主树 `codex/integration`。

用户要求的封装前检查已执行。怪物自然发现玩家后的追击、已入战后遇短墙的真实绕行、窄道通行，以及30怪在开阔和墙边的包围与实际攻击均PASS。短墙检查发现真实过度绕行：通路恢复后仍走旧polygon面中心；修复只有在完整canonical两腿通过地形、WORLD和身体检查后恢复直接接近，不取消已提交移动。

相同运行内容的18项原生功能场景PASS、退出0、无引擎错误。受击仅推迟下一攻击，不停止移动；祖玛阶段召唤按正式行动时钟检查，Boss基础攻击间隔使用21CQ主属性；群怪追击与包围已按用户裁决简化。完整功能范围、历史FAIL及特殊行为MISSING见CURRENT_RESULT.md和FINAL_FUNCTIONAL_RECEIPTS.json。

## APK

- 版本：versionCode106，包名com.personal.mafaoffline，原签名证书与v105一致。
- 桌面：`C:\Users\Administrator\Desktop\HardCore-v106-monster-fixes-debug.apk`。
- 工程产物：`C:\Users\Administrator\Documents\HardCore\outputs\hardcore\HardCore-v106-monster-fixes-debug.apk`。
- 大小：491805682字节。
- SHA256：`895f9fe37cfb28e13570423dcb341fa4307dcc1a61ee5ec070a437f19e247c4a`。
- 包内固定构建源码：`78d0775b4b22f40ad1f54426639d867310dae41a`；怪物修复提交：`c8477058a0c2f67f7a9e39f3523f4ea7693bd5cd`；主机校验工具LF属性修复：`215f0b2f651a51e6855ee813ddd99221690311a1`。后续文档提交不改变包身份。

两遍正式封装、原生退出、冻结输入、签名/覆盖升级身份、版本、Android启动主题、最终seal内容门禁PASS。独立ZIP CRC、无重名成员、15个身份源、资源源字节、375个直接remap目标、8918条导入记录至少一个已导出变体PASS；七个修改生产脚本均存在新GDC且与v105不同。静态范围不能外推所有运行分支或Android实际行为。

## 构建失败与恢复

原始失败全部保留。Windows PowerShell模块目录用进程内PSModulePath修正；Java默认临时目录中的Selector回环失败用工程自有TEMP/TMP修正（实际Selector默认FAIL、工程目录PASS，实际Gradle任务PASS）；旧第三树keystore路径改为当前工具根，实际重签证书一致。JAVA_TOOL_OPTIONS启动提示曾触发PowerShell NativeCommandError，后改为TEMP/TMP环境，不放宽原生退出检查。

校验collector原始工作区CRLF与冻结Git LF字节不一致；恢复到精确已批准Git blob，SHA仍为684c2df187116bb39b2d684a09732a942d8eb8d4ca640f927b0c4d214c227b5b，并用.gitattributes固定LF；没有修改校验代码或预期SHA。实际封装映射专项PASS后，从已完成冷导入的同一隔离树新建封装epoch，重新执行原正式3项采集/生成回调、两遍导出和全部门禁，原失败采集另存。最终完整receipt见two-pass-build-receipt.json和final-export-identity-receipt.json。

临时构建树已逐一核对固定HEAD、独有状态、七个生产文件原始Git字节和共享联接；日志/实际中间APK/生成证据移入主树outputs后移除4个本任务构建树。只剩主树；共享引擎保留。退役映射见BUILD_STAGE_RETIREMENT.json。

## 设备及未关闭项

DEVICE TEST: NOT_RUN。本次交付时ADB没有连接设备，未安装；桌面与工程APK SHA一致。按用户裁决停止重复群怪性能采集，最终流畅度以原测试手机实际游玩体感验收。

祖玛现场快速掉血仍待用户复测；MC40/47夹具的36/44HP每秒一次结算不代表用户完整实际角色。特殊行为的逐ID生命周期/控制/地图组合仍有MISSING；旧召唤夹具B01 FAIL、169运行绑定MISSING、193吸血权威口径MISSING等边界保留。不能宣称全部架构升级完成。

Java临时目录属性的官方语义参考：[Oracle Java 17 networking documentation](https://docs.oracle.com/en/java/javase/17/core/java-networking.html)；本机故障与恢复结论来自保留的实际原生探针。
