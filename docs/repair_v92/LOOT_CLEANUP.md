# 掉落历史概率依赖净化

## 主控后续动态闭环

下文是净化子任务交回时的历史快照，其中 6144 槽和 `6314ea67...` 哈希早于用户随后要求的衣服单槽处理，不代表最终权威。主控已串行运行三个待测场景：`runner_results_adhoc_20260922_173005_531_10728.json` 中 `loot_runtime_item_policy_test`、`progression_loot_20260913/drop_balance_test`、`loot_ui_20260914/runtime_followup_test` 均 PASS。该批另一个技能 context 测试当时 FAIL，后续独立修复，不能将该批写为全绿。

衣服单槽经正式编译后为 6042 槽，最终掉率权威原始 SHA256 `9F6E27418C742C9338CE4B60D752202E50549B48BBC2E066D91C760E6EF43B56`。其他 5791 槽、168 overlay 和六暗最高级衣服的源值保持；保留 15 件上限和优先级。桌面 Excel 已重新计算落地真实概率。最终完整回归和 APK 仍需单独绑定当前源码。

## 交回时快照（历史）

- 复核日期：2026-09-22（UTC+08）。
- 集成基线：`b961cedff8040c9fc81534e094241ad9fa2330ad`；本报告对应其上的共享工作树修改，未创建提交。
- 范围：只移除生产服务不再使用的历史概率入口，保留历史测试的实质校验，并将当前生产断言对准用户编译表。
- 最新用户决定：保留最多 15 件地面输出及既有优先级筛选。本次未修改上限、排序、筛选、随机调用或掉率表。
- 状态：静态/内容/数学复核 **PASS**；本子任务 Godot 动态、设备、APK 验证 **NOT_RUN**。主控独占串行 Godot 和最终验收。

## 修改内容

1. `scripts/layers/runtime/loot_runtime_service.gd` 删除 `_user_balance` 的 eager 实例化、7 个旧分类常量和5个无生产消费者的概率函数。
2. 新增 `tests/helpers/legacy_drop_probability_policy.gd`，明确标识 TEST ONLY；原样保留5个旧函数，以及原 v80 的 `apply`、`extend_profile` 数学和身份校验。历史 v80/v81 组合顺序按原实现恢复，分类取自精确旧 catalog。
3. 新增 `tests/fixtures/legacy_loot_v80/catalog.json.gz`，保存完整旧 catalog 的确定性 gzip，未新增13 MB原始 JSON。
4. `tests/loot_runtime_item_policy_test.gd` 的旧普通怪/精英/Boss 分类数学交由 test-only adapter；真实服务的物品身份、地面显示、当前概率消费、预热及 lean cache 校验继续使用生产服务。
5. `tests/progression_loot_20260913/drop_balance_test.gd` 分开验证782行历史概率、17条精确复制槽，以及当前编译表的概率、输出、RNG和15件上限。
6. `tests/loot_ui_20260914/runtime_followup_test.gd` 分开验证 v81 历史2/3关系与当前用户表，保留 Fate Blade 真实 materialized reward → item instance → inventory 接收链。

未改当前表、生成器、provider、v80/v81 数据、旧 `user_drop_balance.gd` 文件、当前 catalog、生产 item identity 或任何冻结数据。旧 balance 文件保留为历史源码和编译器 provenance；仅移除生产加载依赖。

## 符号引用证据

先对 `scripts`、`tools`、`tests` 做纯文本符号搜索，覆盖直接访问和 `call("符号")` / `has_method("符号")` 字符串；随后复核 `.gd/.tscn/.ps1/.py/.json` 和 `project.godot` 的路径/常量引用。

| 符号 | 改前消费者 | 改后处置 |
| --- | --- | --- |
| `_apply_drop_probability_policy` | 旧函数组内部；3个历史测试中的概率预期 | 只在 test-only adapter 和对应历史测试 |
| `_apply_small_monster_probability_policy` | `loot_runtime_item_policy_test.gd` | 只在 test-only adapter 和该测试 |
| `_apply_denominator_multiplier` | 上述两个旧函数 | 原样移入 adapter |
| `_drop_denominator_multiplier` | `_apply_drop_probability_policy` | 原样移入 adapter |
| `_small_monster_denominator_multiplier` | 旧分类函数组 | 原样移入 adapter |
| `_user_balance` | 服务 eager 初始化；v80/v81旧测试 | 服务/测试均不再访问该成员；历史测试使用明确的 adapter |
| `_chance_denominator` | `tools/monster_drop_p1a_runtime_export.gd:81,831`；`tests/monster_drop_p1a_runtime_contract_test.gd:30,121,196`，包含动态字符串调用 | 服务第731行仍保留，函数体完全不变 |
| `_user_additions` | 服务第83–84行 `owns/reward`；第413行 `item_identity(110)` | 保留真实 Fate Blade 身份/奖励依赖 |
| `_sheet_authority` | 服务第37–45行生产 profile/probability 入口 | 保持唯一当前生产概率源 |

`_build_attempt` 中的 `pre_user_balance_*` / old-policy 等既有审计输出字段仍原样保留；字段名称不代表恢复旧概率执行。全文符号搜索没有发现其他生产消费者，也没有发现生产对 `tests/helpers/legacy_drop_probability_policy.gd` 的加载。

当前保留 `scripts/drop/user_drop_balance.gd` 的证据引用包括 `tools/loot_sheet_compiler/evidence/SOURCE_BINDINGS.json`；它不是运行时实例化入口。

## 历史 fixture 的精确来源和验证

旧 ledger 对 catalog 绑定的 SHA 为：

`e3c1144dc3576d070e1575668851f432b0a5afcda679acdb06a81fcced9c4799`

当前 catalog 的规范化 SHA 是 `cd0494090f93aa572f17a09d1b480a5354fbd76bb30ea498ae159f711d9b207e`。因此直接把旧 ledger 绑定到当前 catalog 本来就不成立；没有允许任意缺失/任意当前哈希的 allowlist，也没有把 ledger 自报 SHA 当作验证成功。

真实原文取自 Git：

- commit：`fa4a1ffa88f7d2ec20d83a8548afc2d4b99d1393`
- blob path：`assets/data/runtime/canonical_monster_catalog.json`
- 原始字节数：13,285,937。
- 原始完整字节 SHA256：`e3c1144dc3576d070e1575668851f432b0a5afcda679acdb06a81fcced9c4799`。
- gzip 字节数：525,445。
- gzip SHA256：`a8703453dbdd5527f7686532c536e57fd563dbd511e2f72427a38fb7aba2da49`。
- gzip 参数：`compresslevel=9, mtime=0`；本机解压后重压逐字节一致。

重建命令（仓库根目录、Python；不写原始JSON）：

```python
import gzip
import hashlib
import pathlib
import subprocess

ref = "fa4a1ffa88f7d2ec20d83a8548afc2d4b99d1393"
path = "assets/data/runtime/canonical_monster_catalog.json"
raw = subprocess.check_output(["git", "show", f"{ref}:{path}"])
assert len(raw) == 13285937
assert hashlib.sha256(raw).hexdigest() == (
    "e3c1144dc3576d070e1575668851f432b0a5afcda679acdb06a81fcced9c4799"
)
packed = gzip.compress(raw, compresslevel=9, mtime=0)
target = pathlib.Path("tests/fixtures/legacy_loot_v80/catalog.json.gz")
target.parent.mkdir(parents=True, exist_ok=True)
target.write_bytes(packed)
print(len(packed), hashlib.sha256(packed).hexdigest())
```

不同 Python/zlib 版本可能产生不同合法 gzip 字节；原始解压字节 SHA 是历史内容权威，本次压缩 SHA 另行记录供文件复核。

adapter 按顺序执行原 ledger seal → contract ID → gzip存在/16 MiB上限解压 → 完整原始字节SHA → 全部5项 source_bindings（原CRLF规范化规则）→ catalog结构/分类索引 → `valid=true`。任何失败保持 `valid=false`，历史测试会明确失败，不能用当前目录补齐或忽略绑定。除catalog使用精确历史字节外，剩余4项绑定仍从原路径完整读取验证：

- `single_player_balance_v80_policy.json`
- `dpv2_direct_baseline_v2.json`
- `dpv2_single_player_effective_probability_v1.json`
- `dpv2_single_player_item_boost_classification_v1.json`

catalog 仅在历史 adapter 中用于分类；当前生产仍读取当前 catalog。现有 Android export 配置排除 `tests/*`；本次未改打包配置，也未执行导出验证。

## 历史断言与当前生产断言

历史断言没有改为“存在即可”：

- 全部782行逐行验证原 `after` 分子/分母；保留原输入分数漂移、monster/item identity 检查。
- 17个复制槽逐个对照 monster158 的完整 source slot，只有约定 UID 和 `user_balance_source_uid` 变化；monster159原前缀完整一致。
- monster76历史原108槽不变，新 Fate Blade 恰好追加1槽。
- 历史参考槽为1/16、Fate Blade为1/24；base/effective/selected/final各阶段保持2/3关系；历史SPB关闭时仍验证关系。
- 原普通怪装备/神水、精英/Boss太阳水倍率断言仍严格保留在历史 adapter 测试。

当前生产断言直接读取 compiled JSON 的每个目标槽作为 expected，避免再次把旧规则算到用户表上：

- 覆盖11个明确存在的 monster profile；校验概率分子/分母、source slots、RNG draw count、attempt数及其概率。
- audit/lean从同一 RNG state 开始；比对最终 state、items、gold_drops、item_records、成功数、地面输出数与丢弃数。
- 保留地面输出 <=15。
- monster18在当前表明确为空：配置有效、0 draw、0输出、不前进 RNG。
- monster199有历史数据但当前表缺失：明确拒绝回退、配置无效、错误原因精确为 `dpv2_direct_profile_unresolved`、0 draw/输出且不前进 RNG。旧测试把它列为当前有效profile属于过时预期。
- 当前 monster76 为85槽；reference1/5、Fate Blade1/15，不再误断言旧1/16、1/24或2/3关系；旧SPB开关不能改变当前生产结果。
- Fate Blade150次固定种子8100的真实roll仍检查产出ID110并进入背包；另比对audit/lean最终 RNG state。
- 10个既有套装ID与命运之刃颜色/拾取阈值仍验证；未新增或改动稳定ID。

## 行为不变证据和验证状态

| 检查 | 结果 | 证明范围 |
| --- | --- | --- |
| 改前工作树快照 vs 改后服务函数拆分比较 | PASS | 29个保留函数体逐字一致（仅规范化CRLF/LF及函数之间尾部空白）；包含roll、概率、奖励、item record、overflow、shuffle、cache和chance |
| 5个移出概率函数 vs adapter函数体 | PASS | 数学和元数据写入原样保留 |
| 原balance的apply/extend_profile vs adapter | PASS | 完整身份/输入漂移/分数及复制规则原样保留 |
| 5项历史绑定、原始catalog SHA、gzip重建 | PASS | 精确原文及完整绑定，没有放宽验证 |
| Python Fraction独立逐行复算 | PASS | 782行before/after与原分类倍率、17条完整复制槽；历史108槽/1/16/1/24；当前85槽/1/5/1/15；当前全表6144槽 |
| scoped git diff / diff --check | PASS | 差异仅本子任务允许文件；无空白错误，Git仅提示将LF转CRLF |
| 本子任务运行Godot解析/专项/回归 | NOT_RUN | 主控正在独占串行Godot，动态结果由主控最终报告 |
| 设备实测/APK导出/包内容验证 | NOT_RUN | 本任务没有构建或设备运行 |

静态复算输出：

```text
LOOT_ARCHIVE_STATIC_PASS bindings=5 records=782 copies=17 v81_base_slots=108 history_reference=1/16 history_fate=1/24 current_m76_slots=85 current_sheet_slots=6144 m199_absent=true m18_empty=true gzip_reproducible=true
```

本次概率行为保持由“所有保留生产函数体不变 + 当前表/provider/Fate身份依赖哈希不变 + 被删代码仅剩历史测试消费者”支持。动态固定种子、输出与 RNG 状态断言已写入测试，但本子任务没有执行，不能将静态证据当作Godot RNG验收。

主控待运行（均使用现有runner，普通场景30秒；不得与现有critical并行）：

- `tests/loot_runtime_item_policy_test.tscn`
- `tests/progression_loot_20260913/drop_balance_test.tscn`
- `tests/loot_ui_20260914/runtime_followup_test.tscn`
- 当前 compiled authority、SPB ledger decoupling、P1A runtime contract 相关现有回归。

## 交付时文件哈希

以下均为原始文件 SHA256（非Git blob ID）：

| 文件 | SHA256 |
| --- | --- |
| `scripts/layers/runtime/loot_runtime_service.gd` | `e02c30d0886ff80e8dead2b407bb608bbd9b71646febf44b8cf70299610efc87` |
| `tests/helpers/legacy_drop_probability_policy.gd` | `ecd31c0e41e66b5dca6a39b2d19bce57d7d14942c812ac6c4327da146b1bb135` |
| `tests/loot_runtime_item_policy_test.gd` | `c6744757f1ed6b8c54b04b8bc02aed7d32ee76a6d98a05f29def2adb250db833` |
| `tests/progression_loot_20260913/drop_balance_test.gd` | `0ac35675810f00e75d7bf9c5f51903811867bfc0aff1ed19f10b7e67abee2746` |
| `tests/loot_ui_20260914/runtime_followup_test.gd` | `94081542989eb99e913a290ee0023c8d1322bc76fb0b63546b65244c2b23854e` |

以下依赖前后未改：

| 文件 | SHA256 |
| --- | --- |
| `scripts/drop/user_loot_sheet_provider.gd` | `8e921b7773659707443490c0425cdad4bfcc906b90c5b7c06831adfd9517b7bd` |
| `scripts/drop/user_drop_additions_v81.gd` | `d8a702aca39cedf952b1c95c0bd3fff1f8d08060ee66f71e5e1ea92a3a2f6cce` |
| `scripts/drop/user_drop_balance.gd` | `686db3082b741646685697c3de92d710780e8772a79795246b6af20e48713883` |
| `assets/data/drop/dpv2_user_loot_sheet_authority_v1.json` | `6314ea67e689a1d65862b6d0c23e92499529dc06f62e454f17fa0b9a1ce690d3` |

未运行git stage/commit/push；没有改动其他施工者文件。主控最终动态测试、整合和提交后，应以最终工作树/提交重新绑定证据。
