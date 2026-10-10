# B07A-003 装备生成器双写安全修复

## 结论

`PASS`（范围限定为装备生成器的两个正式双写入口和相关 Python 回归）。

原实现的 `build()` 与 `apply_female_armor_correction_only()` 都先写
`equipment_attribute_master.json`，再写 `vanilla_176/items.json`。第二个写入一旦
失败，第一份正式数据已经变更，形成 MASTER/ITEMS 不一致。该行为已经用固定
`684824ac7bb59ac903054b26b3435441b8a2f152` 的完整旧源码、完整 authority JSON 副本和
第二写入 I/O 故障注入复现；证据见
`outputs/wake_drop_v108_review_followup_20261009/b07a_equipment_writeset/OLD_ENTRYPOINT_FAILURE_EVIDENCE.json`。

## 修复边界

`tools/build_equipment_attribute_master.py` 新增共享的 `publish_equipment_write_set()`。
两个双写入口先在内存中完成全部序列化，然后为每个目标创建同目录临时文件并
`fsync`。替换前和每次替换前都比较目标的原始字节；检测到新的人工内容时立即
失败，不覆盖人工内容。若后一个替换失败，前面已替换的文件只有在仍保持本次
写入字节时才回滚；原本不存在的文件恢复为不存在。临时写集和回滚文件在所有
路径清理。单输出的 `project_current_master_items()` 保留原有限投影规则。

这项修复只改变 I/O 发布边界，没有改变装备属性、概率、掉落、身份或生成资料。
进程终止／断电恢复仍单独标为 `NOT_RUN`，没有借此引入新的 journal 或第二权威。

## 验证

执行：

`python -m unittest tests.equipment_generator_publish_failure_test tests.equipment_correction_check_only_test tests.test_equipment_current_master_projection -v`

结果：`PASS`，15 项通过，退出码 0。覆盖正常双文件发布、首步失败时两文件不变、
第二步失败回滚、首文件原本缺失时的恢复、发布期间人工改动保护、回滚替换失败
时保留原字节备份、回滚读取失败时继续其他目标并保留原字节备份，以及既有
check-only 和限定投影回归。还用完整临时 authority
JSON 直接调用了真实 `apply_female_armor_correction_only()` 的成功路径和第二步
失败路径。
原始输出和 receipt：

- `outputs/wake_drop_v108_review_followup_20261009/b07a_equipment_writeset/equipment_generator_publish_failure_test.stdout-stderr.v3.txt`
- `outputs/wake_drop_v108_review_followup_20261009/b07a_equipment_writeset/TEST_RECEIPT_v3.json`

进程终止／断电恢复仍为 `NOT_RUN`。本子任务没有运行 Godot、Android 或设备测试，也没有 commit/push。
