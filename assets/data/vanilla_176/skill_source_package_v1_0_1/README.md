# MIR2 1.76 33技能唯一真源 Codex v1.0.1

## 文件

- `MIR2_176_33技能_Codex施工规格_v1.0.1.md`：完整人类可读规范。
- `mir2_176_skills_source_of_truth_v1.json`：机器唯一真源。
- `mir2_176_skills_schema_v1.json`：JSON Schema。
- `mir2_176_skill_test_manifest_v1.json`：自动测试清单。
- `MIR2_176_当前差异与迁移清单_4b6ea4e0.md`：迁移顺序。
- `CODEX_施工总指令_v1.md`：可直接交给Codex。
- `Mir2SkillFormulaReference.gd`：公式参考。
- `source_evidence_matrix.md`：来源边界。
- `validation_report.json`：包内自检。
- `manifest.json`：文件校验。

## 使用

先把整个目录交给Codex，并要求严格执行`CODEX_施工总指令_v1.md`。
第一次只能做只读审计。确认审计后再进入施工阶段。

## 最重要的判断

本包不是把任一私服、Crystal或Mir3数据库冒充盛大1.76。
它把能够历史确认的部分固定为`historical_verified`，
把经典源码公式标为`source_formula_reference`，
把无法唯一恢复但项目必须施工的数值明确冻结为`project_canonical`。
