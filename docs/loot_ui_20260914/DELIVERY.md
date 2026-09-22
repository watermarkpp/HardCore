# hardcore 1.0 正式版 v81 交付

## 源码与范围

APK 固定源码：`4f4462ad027714acf657c7a2ac28fa4f15a6e293`。基线：`d35519f87e5ccfc020ed2b8ead3651006ac8b01c`；专项分支 `codex/loot-ui-followup-20260914`。已快进合并至 `codex/integration`。后续证据文档提交不改变 APK 源码身份。

本轮按最新 Word 及用户最终文字裁决：物品详情的各行仍左对齐，以最长实际文字行确定正文宽度，再把整块正文居中；名称本身单行居中，★独立，标题20/正文14不变。零至三位数自动测宽，未使用固定向右位移。设置布局已经用户验收，正式功能已复验。详细生产路径、数据来源和中途失败说明见 [IMPLEMENTATION.md](IMPLEMENTATION.md)。

同时包含：持久单独增加不算 JP、地面图标层级及事件驱动的名称防重叠、十项精确装备分类、沃玛教主命运之刃槽、共用 Buff 行与神水图标。命运之刃新增槽为 `dpv2.user.v81.m76.fate_blade`，引用炼狱最终概率的 2/3（当前 1/24）；旧 108 槽和概率、优先级、15 件上限均保留。

## 功能证据

- 31 个不同场景分批最终 PASS，索引见 [test_index.json](evidence/test_index.json)。不是一次干净最终 HEAD 的全量运行。188 个 ID 的仓库背包测试因单场景超过 60 秒，改为五个不重叠窗口覆盖全部 188 项；原超时记录保留。
- 固定 APK 源码后 4/4 PASS，0 engine errors，见 [fixed_source_tests.json](evidence/fixed_source_tests.json)：自适应详情、12 类神水到期、掉落与分类真实运行、设置功能。
- 神水通过真实使用入口和正式计时 `_process(delta)` 边界验证：到期前有效，到期后全部计算属性恢复基线、图标消失；续时正常。这是确定性计时验证，不声称在手机等待数分钟完成测试。
- 正式渲染截图见 [visual](visual/)，渲染日志见 [presentation_capture.txt](evidence/presentation_capture.txt)。战神盔甲详情宽187，名称及最长正文行中点均93.5，正文14/标题20。
- 地面150项名称布局桌面单次约0.75毫秒；空闲帧无重复布局。此项不是安卓帧率证据。

复验命令：

```powershell
& tools/run_godot_tests.ps1 -TestPaths @(
  'tests/loot_ui_20260914/detail_adaptive_test.tscn',
  'tests/loot_ui_20260914/buff_expiry_test.tscn',
  'tests/loot_ui_20260914/runtime_followup_test.tscn',
  'tests/loot_ui_20260914/settings_function_test.tscn'
) -TimeoutSeconds 30
```

## APK 与集成

APK BUILD：PASS。桌面文件 `C:/Users/Administrator/Desktop/HardCore-1.0-v81-release.apk`，版本81 / `hardcore 1.0 正式版`，品牌HardCore，包名 `com.personal.mafaoffline`，466,010,045 bytes，arm64-v8a，minSdk24 / targetSdk36。

SHA256：`6AF911A381AA5D567B6086D698EC4480FAC9316192D4E6BAEE50B96E4705D89E`。

- 同签名覆盖资格、包名/版本/build-info、运行时资源探针：PASS，见 [apk_identity.txt](evidence/apk_identity.txt)。证书 SHA256 `C62D0F8239B926F819038845C302143FD24DCFD75ED8D877ED846C430C6F3FCC` 与桌面v80相同，APK v2签名验证通过。沿用项目隔离 debug 导出和现有签名；“正式版”为用户指定版本名，build-info仍准确标记 development。
- 13个改变/新增运行时脚本和3份JSON与固定源码对应；228个其他运行时脚本、8983个其他资源项与v80字节相同，包内不含tests/docs，见 [apk_payload.json](evidence/apk_payload.json)。
- 手工布局原哈希、39脚本/4个SVG导入闭包/8个纹理验证PASS，见 [apk_resources.txt](evidence/apk_resources.txt)。
- 独立构建目录保留：`C:/Users/Administrator/Documents/HardCore-android-staging/4f4462ad0277-20260914-131806-da05c01b`。导入的16条错误均为8个未改动的runner故障夹具重复解析，无生产错误，见 [import_log_classification.json](evidence/import_log_classification.json)；[Android导出stdout](evidence/android_export_stdout.txt)含完成标志，stderr为空。
- 远端交付包含专项分支、主分支和源码里程碑 `milestone-hardcore-1.0-v81`。标签剥离后的提交必须等于上述APK源码，主分支可包含后续证据文档；交付前用 `git ls-remote` 核对这三个ref与本地精确一致，不能将仅本地合并称为推送完成。

## 保留与实机边界

已验收的人物属性布局、手工校准表、装备主表、怪物与地图数据、旧掉率权威不改；冻结证明见 [frozen_scope.json](evidence/frozen_scope.json)。原 v80 及更旧 APK、旧标签、用户修改的 AGENTS.md 和68个既存未跟踪文件保留。

安卓设备测试：NOT_RUN。当前没有连接 ADB 设备。旧版冷 UI、仓库事务失败回滚延迟及多怪安卓性能债务仍须区分记录；不能由本轮功能 PASS 或导出成功推出全部卡顿已经消除。
