# 比奇重复老兵单目标修复

用户授权：只去掉重复老兵，其余 NPC、82 条怪物刷新、位置、碰撞及素材不变。

- 专项基线：`42b8b4d914ac0cfad31ab20533869b8df873d721`。
- 专项提交：`5b737710258086c80c314b7e48244ba0330e2dd8`；主树接入：`518fa216`。
- 地图：`world_bich_province`，runtime ID `910001`。
- 删除：`npc_000008`；保留：`npc_000005`，包括原 facing=south、tile_anchor=[34,37]，不做锚点归一化。
- 发布 build SHA：`ceacbb54c1b994225e9a43a43e31769093f04bfc5a34d151d41b16f7c628049d`。

正式发布走单目标 candidate/approve/publish 入口。首次新树缺 class cache 的执行失败未写发布文件；随后完成隔离环境准备。审查发现删除最后一个数组元素留下尾逗号后，已修成严格 JSON 并重新发布，最终文件与 source hash 对应。中间发布使 approval_revision 增加两次，不代表额外内容更改。

主控独立从 Git 两个提交读取文件并用 Python 严格 JSON 解析、结构比较：编辑文档恰为删除一个指定 NPC；runtime 除同一 NPC 删除和三项 build/binding hash 外完全相同；其他 66 条正式 registry 记录及总表其他字段相同。worker 另核验 208 块地表哈希、碰撞、非 NPC 层、刷新与实例不变。完整差异未包含地表图片、碰撞或其他地图文件。

专项提交上运行：

```powershell
tools/run_godot_tests.ps1 -TestPaths tests/bich_content_1_test.tscn -TimeoutSeconds 30
```

结果：1/1 PASS，0 engine errors。专项树证据：`outputs/test_logs/runner_results_adhoc_20260905_154604.json`。主树接入后的地图相邻复验另行记录；本记录不代表 APK 已安装。

主树 `518fa216` 接入后 `bich_content_1_test` 再次 PASS；`runner_results_adhoc_20260905_154923.json` 的 14 项相邻复验为 8 PASS / 6 FAIL，7 engine errors，因此不能称该批全通过。失败为 progression 书商库存前提、边界夹具、phase1 类型解析、旧社区属性权威、古墓编辑稿 binding 和冲撞同级目标夹具，仍在分诊；不通过修改地图或降低断言绕过。比奇重复老兵本身的专项门禁已通过。
