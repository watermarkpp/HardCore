# 人物属性与稀有度复核（2026-09-13）

集成基线 `db9010209128f82969211cfd9b01a1046ac257b6`；分支 `codex/ui-character-review-20260913`。
用户已在校准器确认“从 ok 开始整体上移 50 px”的候选并答复“鉴定完毕 合格”。
随后明确数字只需覆盖零至三位数；不为四位以上数字缩小字体。

## 最终行为

- 恢复人物属性标题，角色名、职业与完整等级链接相对二级装饰框水平居中。
- 角色名字号 19、职业等级 17、属性正文 16；职业与等级四个空格。
- 正文按最长完整行测量宽度，整块居中，保留原有十行及各行左对齐；数值变化不换行、不缩字、无滚动条。校准重放不能覆盖动态几何。
- 点击“等级：数字”的任意位置查看实时经验；再次点击、切换属性、刷新或关闭界面均关闭说明。
- 用户分类文档为《传奇1.76装备稀有度分类_21CQ核对版.docx》，SHA256 `651940DC77814B604659BAEA7D699544ACEEA8CAA919B1B78F9310BF6BAFA4A1`。已读全部正文与 15 张表；仅作为显示分类 authority。
- 按明确覆盖：战神盔甲、恶魔长袍、幽灵战衣男女六项 ID 128–133 均为祖玛橙色；其余按文档。175 项装备精确 ID 全覆盖，83 普通、15 沃玛、37 祖玛、18 赤月、22 极其稀有。文档勋章类别没有正式装备主表 ID，不虚构新装备。
- 沃玛亮金 `#FFD86B`，祖玛橙 `#FF943D`，赤月紫 `#C48CFF`，极其稀有红 `#C83B35` 配暗金描边 `#B08A3E`。背包、仓库、商店详情/商品名、地面名和拾取提示共用精确 ID 样式；复用控件时普通物品清除稀有描边。
- 运行时校准表未变：SHA256 `0EA858C9FE5867B8B7057DFC16FF32FB06DF68A7A6862992A702E45D470CBF10`。装备数值、掉率和其他玩法数据冻结。

## 验证与失败分类

- 最终三位数布局与两组商店全 ID 矩阵：3/3 PASS、0 engine errors。报告 `outputs/test_logs/runner_results_adhoc_20260913_155249_466_5496.json`。
- 名称地面/拾取管线、商店选择身份/样式复用、详情合同：3/3 PASS，报告 `outputs/test_logs/runner_results_adhoc_20260913_153821_887_10408.json`。
- 背包真实输入、说明关闭、188 ID 背包矩阵、拾取提示：4 项 PASS，见 `outputs/test_logs/runner_results_adhoc_20260913_154419_597_6228.json` 中各场景。该批同时记录了下述旧测试失败，不把整批称为 PASS。
- 商店矩阵旧断言要求详情含价格，与用户已接受的去重复价格合同冲突。替换为真实商品卡报价正确且详情无重复价格；两组 188 ID 已复验 PASS。
- 仓库单场景 188 ID 在 30 秒上限内未完成，无已报告断言失败；使用既有 id_from/id_to 机制拆为五个连续、互不重叠区间，每场景上限 60 秒，完整覆盖不减少。
- 最新截图通过生产 UI 校准器采集至 `outputs/ui_calibration/presentation_review_20260913`；99/999 属性与屠龙、圣战头盔、恶魔长袍配色。

## 发布

版本码 79，名称仍为 `hardcore 1.0 正式版`；保留桌面 v78 APK 与 `milestone-hardcore-1.0` 标签。
- APK 源码：`98b38830ea074084cde49e964b3ca1da15263417`，独立干净构建；后续文档提交不改变包内源码。
- 桌面文件：`C:/Users/Administrator/Desktop/HardCore-1.0-v79-release.apk`，465,961,383 bytes。
- SHA256：`3FEE8F55D649090C52C8C5165DF9CBC1ABD006FEADA09CD3F07536CD0FABCDA8`。
- Android 版本 79 / `hardcore 1.0 正式版`，包名 `com.personal.mafaoffline`、可见名 HardCore、arm64-v8a，原 debug 签名保留；与 v78 覆盖安装资格校验 PASS。
- APK 资源专项 PASS；包内 6 个预期脚本改变，其余 228 个运行时脚本和 603 项数据与 v78 字节一致。两个显示分类 JSON 与固定提交一致；无 tests/docs 测试材料进入包体。
- 导入期 16 条报错来自 8 个故意损坏的 runner fixture，已逐条分类，非生产脚本失败；导出 stderr 为空。完整构建目录保留以供诊断。
- 最终源码提交专项 3/3 PASS，合并 integration 后冒烟 1/1 PASS；原始结果与源码身份均在同名 evidence 目录。
- 源码已快进合并至 `codex/integration`；补充标签 `milestone-hardcore-1.0-v79` 指向 APK 源，保留原 `milestone-hardcore-1.0`。
- 手机未连接，新 APK 实机安装/体验 `NOT_RUN`；不把自动测试和打包成功作为手机验收。
- 用户未提交的 `AGENTS.md` 与既有未跟踪 UID/translation 文件保留，未进入本轮提交。

- 仓库分段最终结果：5/5 PASS、0 engine errors，188 个不重复 ID；原始 runner 与覆盖 ID 清单保存在 `ui_character_review_20260913_evidence/`。
