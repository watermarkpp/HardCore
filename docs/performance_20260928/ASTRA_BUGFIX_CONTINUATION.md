# Astra 精确恢复点 — 2026-09-28

## 当前状态

本轮基线21b40ddae663997f8e9f267585988e6a7c63db6a，codex/integration，单主控串行。全部本轮源码/定向修复已完成，39个不同相关场景最后结果PASS。正式说明及原始证据见 `VERIFICATION.md`、`evidence/latest_results.json` 和源码LF哈希。不要再按旧检查点重新做已经关闭的问题。

## 已关闭

- 药剂/油/书/增益/卷轴立即使用，人物档顺序后台保存；处理拾取收据和立即消费交错、失败提示及退出。
- 工作台任意先后顺序放取、无效组合/多放/缺材料/缺金币按钮不启用；真实锻造/合成结算无同步落盘等待。
- 仓库最终三次文件提交后台化，入口等待跨帧化，保留双档事务、失败回滚、提交中切后台一致性。
- 背包/仓库未变化格子不重复写图文；圣物/徽章/碎片32px显示边界；loading文字居中。
- 玩家和怪物Ground GU严格八方向，真实脚印路径；镜头每帧一次平滑。
- 硬直/毒/圣物等相关回归PASS，不改战斗时机和公式。

## 最新交付指令

用户改为：完成后构建**完整新APK放桌面，包含主树全部新改动和本轮修复**。不再只交热补丁。使用正式隔离构建脚本、versionCode95升级94，包名/签名保持。构建源码已提交为7076bc465dbf7dc837381f267fa8eb9e151bf001；当前未push。既有主树先前修改已在21b40ddae祖先内，不能从v93重起。

## 保护

`AGENTS.md`与`tests/cangyue_area_test.gd`为接管前dirty，及大量无关untracked，禁止覆盖/全量stage。人工地图/assets/project/export_presets未动。测试new immediate_item_save曾为runner门禁stage，最终提交前重新选择性stage。新脚本warehouse_commit_operation、world_camera_follow必须纳入。

## 构建交付完成 — 2026-09-29

源码7076bc465dbf7dc837381f267fa8eb9e151bf001已完成隔离导入、Android构建和签名/版本/资源检查。完整APK已复制桌面并复核SHA256，详见 `APK_DELIVERY.md`。39项相关场景PASS，包内9684项冻结数据/纹理与v94逐字节相同；六项Sol热补丁资源已核验继承。旧补丁在新APK启动时按源码身份拒绝挂载，避免覆盖新修复。

首次导出因Windows JDK本机通信异常FAIL，同一隔离stage使用进程级临时目录参数后重试PASS；没有把第一次失败写成成功。正式验证和原始日志已保存。

唯一后续验收：用户自行覆盖安装桌面 `HardCore-v95-full-fixes-debug.apk`，实际检查跑动吃药、工作台、仓库、八向移动/镜头和loading。DEVICE TEST: NOT_RUN。不要重新安装旧补丁，不用旧存档覆盖手机新进度。不自动安装或push；当前后续文件仅交付证据，APK源码仍固定7076。

手机最后adb不在线。旧stopdiagnostics nonce bd8de724c2a3429c9956702fada818d7，若以后连接先取outbox避免覆盖旧命令；不录屏/截图/覆盖旧存档。手机已消耗药剂，禁止用旧备份回写。

仓库100件批量完成仍约0.3秒，但最大帧间隔从86–115ms降至19.5–24.9ms；不要把两个指标混淆。其余详情/失败裁定/精确runner身份见VERIFICATION。
