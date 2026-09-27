# R4 基线（T0 固定现场）

- integration/BASE: f5d6308f53162509bffd30f6981987cbfe80fa68
- R3 测试源码: 3e05e7035d0e4f58c36fb054f82e6b8c120dc4bc
- R3 交付 HEAD: 2aede2fba4cf312a7251cc3db0c395a92428c5a9（=远端）
- 施工树 mct-r1-f5d6308f 开工 dirty=0；无用户未提交改动需要隔离
- 四个审查反例复制到 tests/hc_monster_combat_r4/ 并已 git 跟踪；Godot 行为级 RED 全部确认
  （4/4 FAIL，均 non_zero_exit_code_1 带具体行为输出，无解析/导入错误）
- probe_r3_verifier 八样例：R3 已修 5 例保持满足；3 个新结构漏洞仍放行（重复行/空身份/删drop_policy）
- 审查者声明的 Godot NOT_RUN 已由本轮运行闭环；审查者的 8 例 Python 实跑结果与本地一致

逐条事实见 RESULT_LEDGER.json。
