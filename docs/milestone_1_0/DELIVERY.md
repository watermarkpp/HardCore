# hardcore 1.0 正式版交付

- APK：`C:/Users/Administrator/Desktop/HardCore-1.0-release.apk`
- 版本代码：78；版本名称：`hardcore 1.0 正式版`。
- 大小：465,955,859 bytes。
- SHA-256：`E687CB8F6A871B2BAD9B2BDDBF83A427FA24047FF16B7BDB57BD5ECA3E379E01`。
- 包内源码：`00ca013d032346fc2e0020388933de9ad23ec8dc`，build-info `git_dirty=false`。
- 里程碑标签：`milestone-hardcore-1.0`，固定上述 APK 源码；交付证据文档提交不改变包内源码。
- 主分支：`codex/integration`；主工作副本恢复为 `C:/Users/Administrator/Documents/HardCore`。原 `codex/m30-r3-integration` 分支及旧临时副本的提交均保留，未删除历史。

## 本轮结果

1. 人物属性完整利用原空白区域，无滑块；角色名、职业等级字号与空行按要求设置。属性可以点击说明，等级显示实时经验分子／分母；再次点击和界面关闭按共用规则清理。
2. 241 项精确 ID 名称分类补齐。沃玛／同档亮金、祖玛／同档橙、赤月和极稀有紫；界面、地面、拾取提示颜色一致。分类明细及生成规则见 IMPLEMENTATION.md 和 UI 配色策略。
3. 抗拒火环动画居中，并消除站在非整数格时的判定偏移。八格形状、面积、零伤害和击退公式保持原规则。

## 验证状态

| 门禁 | 结果 |
|---|---|
| 功能及相邻回归 | PASS，18 个不同专项场景分批通过 |
| 精确源码提交后的核心复验 | PASS，4/4，0 engine errors |
| 合并后主副本复验 | PASS；颜色与抗拒先通过，刷新旧类缓存后人物及共用说明 2/2 通过 |
| APK 导出 | PASS |
| 同签名、包名、递增版本、SDK、arm64 | PASS |
| 包内代码与冻结数据 | PASS；9 个预期脚本更新，225 个其余脚本及 603 项其余数据与 v77 字节一致 |
| 校准布局哈希、资源闭包、黑色启动页 | PASS |
| 手机安装及新功能人工审核 | NOT_RUN；ADB 无连接设备 |

完整来源、范围、规则及初始失败见 IMPLEMENTATION.md；原始 runner JSON 和校验日志在 evidence 中。没有声称本轮重新完成全 Critical 或多怪性能测量。

两项执行问题已关闭：W6 旧测试夹具不支持仅随机持久词条，改为明确注入非法 modifier 后仍验证拒绝；主副本旧 Godot 类缓存缺 UIActivationOnce，正式 headless import 后复验通过，APK 全新构建缓存原本正常。首次 Android 校验因 aapt 无法读取中文 APK 文件路径而失败；仅重命名为 ASCII 文件名后，签名／包内版本／资源全部重验通过，未重编译或修改包体。

保留原包名 `com.personal.mafaoffline` 与签名证书 SHA-256 `C62D0F8239B926F819038845C302143FD24DCFD75ED8D877ED846C430C6F3FCC`，可覆盖 v77。延续项目既有 Godot debug 签名 APK 工作流；“正式版”为本次用户指定的版本名和里程碑标识。

合并时 26 个会与正式源码重名的未跟踪 UID 已逐个确认内容一致，并移至各原工作副本的 `outputs/milestone_1_0_merge_uid_backup/` 保存；SHA 清单见 evidence/milestone_merge_preflight.json。主副本的用户 AGENTS.md 内容哈希保持一致，未将其改动提交；其余未跟踪文件与存档均保留。
