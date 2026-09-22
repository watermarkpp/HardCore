# Ground manifest provenance 字节复核

- 复核时间：2026-09-22T16:21:11+08:00。
- 工作树：`C:/Users/Administrator/Documents/HardCore`，分支 `codex/integration`。
- HEAD：`b961cedff8040c9fc81534e094241ad9fa2330ad`。现场有主控及其他子任务未提交修改，本报告仅覆盖下列正式 registry 的 67 个目标。
- 范围：正式 registry、67 份 `ground_manifest.json`、对应 visual provenance 字段、HEAD/index blob、Git 属性、正式发布与隔离构建读写路径。
- 本子任务只新增本报告；未修改地图、manifest、`.gitattributes`、生产或测试文件，未创建工作树，未启动 Godot，未 stage/commit/push。

## 结论

**原 FAIL 的直接原因是工作区的换行转换，不是地图内容、PNG、几何或碰撞发生了变化。** 初始独立核对：67/67 工作区 manifest 为 CRLF，67/67 HEAD 与 index blob 为 LF；每份工作区文件仅把 CRLF 换成 LF 后，字节均与其 HEAD/index blob 完全一致。对应 visual 记录要求 66 份 LF，只有 `world_bich_province` 要求 CRLF。

报告生成期间主控已实施精确路径属性及行尾恢复。本子代理随后独立重验：67/67 raw 匹配原 visual 记录，HEAD/index blob 仍 67/67 不变；当前属性为 67 个精确文件规则（66 LF、1 CRLF），未采用涵盖非正式文件的通配。下方完整矩阵的 Raw 列记录恢复后的字节，CRLF 列同时保留初始工作区哈希。

| 核对项 | 结果 |
| --- | --- |
| Registry 中正式地图与对应 manifest | 67 / 67 存在 |
| HEAD blob 等于 index blob | 67 / 67 |
| 工作区 LF 归一结果逐字节等于 HEAD/index blob | 67 / 67 |
| 工作区与 HEAD JSON 语义完全相同 | 67 / 67 |
| LF 字节 SHA256 等于 visual 记录 | 66 / 67 |
| CRLF 字节 SHA256 等于 visual 记录 | 1 / 67，仅比奇 |
| 无法由两种换行表示解释的记录 | 0 |
| 初始 Git 属性 | 67 目标全部 text/eol/filter/working-tree-encoding 未指定 |
| 主控修复后 Git 属性 | text=set 67；eol=lf 66；eol=crlf 1；filter/working-tree-encoding 未指定 |
| 主控恢复后原始字节匹配原 visual 记录 | 67 / 67 |
| 当前属性下 Git checkout-filter 模拟：autocrlf=true / false / input | 每种设置均 67 / 67 |

当前 `.git/config` 的 `core.autocrlf=true`；`core.eol`、`core.safecrlf`、`core.attributesFile` 无显式值。修复前 `git check-attr` 对本次全部 67 个路径返回 `text/eol/filter/working-tree-encoding: unspecified`，`.git/info/attributes` 不存在，workspace 未找到下级 `.gitattributes`。因此 Git 可将仓库 LF blob 检出为 Windows CRLF；语义和 Git clean 状态保持不变，按原始文件字节计算的 provenance 却改变。

比奇是反向例外：记录 `3f06c3b3b5c4ecaf638a3438070958014e0fc8659470d27ed8e803d5b01b9905` 正好等于当前 CRLF；其 LF/blob SHA256 为 `461b9ca3ec394366305df8f8ac7b246edfa6f65eb4090f3c1e16b56e728002c0`。现有测试注释称比奇有历史漂移，但本机当前 raw 实际匹配。不能因为已有例外而把其余 66 份加入例外，更不能跳过 raw SHA256 检查。

## 生产与构建证据

- `tests/map_release_identity_matrix_test.gd:150-156` 按 map key 精确读取 manifest，以 `_file_sha` 对完整原始字节计算 SHA256，与 `visual.source_ground_manifest_sha256` 比较；`205-210` 只扣除历史比奇例外。stderr 列出的 66 个失败与本次 LF 匹配集合完全一致。
- `tools/map_editor/publish_formal_map_releases.gd:227-228` 明确冻结 workspace，仅直接读取既有烘焙数据；`264` 用 `FileAccess.get_sha256(manifest_path)`，`334` 将该 raw 哈希写入 visual。发布程序没有隐含换行归一规则。
- `scripts/map_editor/map_editor_build_runtime_service.gd:1056-1079` 的 authoring candidate binding 也包含 `ground_manifest_sha256` 原始文件哈希。不能通过改为语义 hash 或清空字段掩盖 checkout 表示变化。
- `.gitattributes` 已对 runtime JSON 和 wall plan 使用 `text eol=lf`，并对其他有冻结 Windows 字节合同的数据使用精确 `text eol=crlf`；这是仓库现有且合适的跨工作树机制。ground manifest 原先没有覆盖规则，主控本轮已追加 67 个精确路径规则。
- `tools/build_android_isolated.ps1:203` 从指定提交执行 `git worktree add --detach`，阶段源码来自 Git checkout，不是复制主树文件；`291-319` 只生成 build_info 和可选版本覆盖，`322-323` 检查 wall binding 后启动 Godot import。脚本没有转换 ground manifest 换行的专门处理。
- `tools/generate_build_info.ps1:23-46` 检查 Git 身份/dirty 状态，`74` 只写生成的 build_info。Git clean 不能证明所有 raw-hash authority 在不同 core.autocrlf 设置下字节一致。

本问题与 wall plan 的旧 `source_runtime_json_sha256` 失效分开处理：本次 ground 数据的工作区 LF 结果与 Git blob 67/67 相同，不需要任何重新生成；不能以修复此行尾问题为由重建 runtime 地图、PNG、碰撞或人工编辑数据。

## 最窄修复建议

1. 在 `.gitattributes` 固定本次正式 manifest 的检出字节：66 份 LF，`map_editor_workspace/world_bich_province/ground/ground_manifest.json` 显式 CRLF。规则保留 `text`，使仓库 blob 继续规范化为现有 LF；不需要改任何 manifest 的 Git blob 或 visual 记录。
2. 当前主树只对 registry 精确枚举的 67 个目标进行有条件字节恢复。每个目标先计算 raw/LF/CRLF、检查 LF 字节等于已核对 HEAD/index blob，并检查所选表示恰好等于 visual 记录，全部通过后才写入所选表示；已有正确字节的比奇无需写入。遇到任何内容差异或非预期 hash 立即停止，不从 HEAD 覆盖当前文件、不重新 JSON 序列化、不重新发布人工地图。
3. 恢复后证明 67/67 raw SHA256 等于原 visual 记录，HEAD/index blob 不变，`git diff --numstat -- <67 manifest paths>` 无语义差异，geometry/PNG/runtime source 不变。只修改属性及当前工作区行尾表示，不修改 provenance 的标准答案。
4. 主控按 runner 跑 `map_release_identity_matrix_test.tscn`，再验证修复提交在隔离检出时的属性和 67 个 raw hash。构建脚本只会使用被指定提交内的 `.gitattributes`，主树尚未提交的属性不能修复某个旧提交的隔离构建。

若主控决定以 manifest 文件域设定默认规则，可使用以下两行，具体例外必须放在默认规则之后：

```gitattributes
map_editor_workspace/*/ground/ground_manifest.json text eol=lf
map_editor_workspace/world_bich_province/ground/ground_manifest.json text eol=crlf
```

**范围边界：** workspace 中实际有 135 份同形路径，本次只审计 registry 的 67 份。上述通配会影响另外 68 份未来 checkout 的换行表示，未证明那些文件的其他 raw-hash 引用。因此严格遵守本轮冻结范围时，应为本报告表格中的 67 个精确路径分别设定属性；若采用域默认规则，本地恢复操作仍必须严格限于正式 67 个目标，不对整个 workspace 批量归一。

主控实际采用了 67 个精确路径。读到的非正式样例 `map_editor_workspace/between_life_and_death/ground/ground_manifest.json` 仍为 `text/eol: unspecified`。恢复后样例文件曾在 `git status` 中暂列 M，但 `git diff` 与 `git diff --numstat` 均为空；`git ls-files --eol` 为 `i/lf w/lf attr/text eol=lf`，并且本报告直接读取 index/HEAD 与工作区验证字节相同。该状态由主控后续正常 index 流程处理，本子代理未刷新或写入 index。

**后续编辑边界：** `scripts/map_editor/map_editor_ground_service.gd:421` 使用 `JSON.stringify(...)+"\n"`，Godot 自己写入的是 LF；Git 属性只控制 Git 转换，不会改变运行中的写入函数。这不阻塞当前冻结 release 的 checkout 修复，但未来授权重新保存/烘焙比奇时，必须同时明确 writer 字节合同或通过正规重新发布迁移这个历史 CRLF 例外，不能宣称两条属性规则永久解决所有未来 authoring 写入问题。本次未实施该扩展。

## 验证状态

- 静态 67 文件 raw/LF/CRLF/record/HEAD/index 字节矩阵：**PASS**。
- 初始工作区正式 provenance 一致性：**FAIL**，66 份纯 CRLF 转换差异。
- 主控修复后工作区 raw hash 独立验证：**PASS**，67/67 与原记录相同。
- 当前属性下 Git checkout-filter 验证：**PASS**，对全部 67 目标分别运行 `git -c core.autocrlf=<true|false|input> cat-file --filters HEAD:<manifest path>`，201/201 结果匹配原 visual 记录。本命令只读现有 blob 与当前工作树属性，不创建工作树、不改 Git 设置；它证明当前属性转换规则，不代替修复提交的实际隔离检出。
- 修复提交的隔离 checkout / APK：**NOT_RUN**。
- Godot targeted/critical：**NOT_RUN**，子代理禁止启动进程；原失败日志已读取。
- DEVICE TEST：**NOT_RUN**。

## 完整 67 文件矩阵

每行路径均为 `map_editor_workspace/<map_key>/ground/ground_manifest.json`。下表 `LF / Git blob SHA256` 同时是工作区 LF 转换、HEAD blob 字节及 index blob 字节的 SHA256（已逐字节证明相等，并非 Git 对象 ID）。`CRLF SHA256` 为同一 LF 内容转换成 CRLF 后的哈希。`Raw SHA256` 是本报告采样时工作区真实字节；记录列原样来自对应 `<map_key>.visual.json`。全部文件 JSON 语义不变。

| runtime ID / map key | Raw SHA256 | LF / Git blob SHA256 | CRLF SHA256 | visual 记录 | 记录要求 |
| --- | --- | --- | --- | --- | --- |
| 910001 / `world_bich_province` | `3f06c3b3b5c4ecaf638a3438070958014e0fc8659470d27ed8e803d5b01b9905` | `461b9ca3ec394366305df8f8ac7b246edfa6f65eb4090f3c1e16b56e728002c0` | `3f06c3b3b5c4ecaf638a3438070958014e0fc8659470d27ed8e803d5b01b9905` | `3f06c3b3b5c4ecaf638a3438070958014e0fc8659470d27ed8e803d5b01b9905` | CRLF |
| 910002 / `world_snake_valley` | `0c3e9eb8a8d2964aacbda03c302e6aa7b2e360b79edfbfded85a90a6d31cc9f7` | `0c3e9eb8a8d2964aacbda03c302e6aa7b2e360b79edfbfded85a90a6d31cc9f7` | `26acf42b2113d4dba8ba05cb0396ae354f07965e64b91965aa6cf36cd3a209bd` | `0c3e9eb8a8d2964aacbda03c302e6aa7b2e360b79edfbfded85a90a6d31cc9f7` | LF |
| 910003 / `world_mengzhong_province` | `d2bee4b89b8bfe6b6919ba309ab69b168394cbbe9f3fc1ab211a0423ed233ee2` | `d2bee4b89b8bfe6b6919ba309ab69b168394cbbe9f3fc1ab211a0423ed233ee2` | `95fb4afd449d29efe4bbee9ffa5f32c7085edc9a49fa9ef1c7ba9da7bec8e84e` | `d2bee4b89b8bfe6b6919ba309ab69b168394cbbe9f3fc1ab211a0423ed233ee2` | LF |
| 910004 / `world_wooma_forest` | `db4baab9855fdaff166d2a43b8baedfc2183349bbc8ec25a8951887c5b44c90a` | `db4baab9855fdaff166d2a43b8baedfc2183349bbc8ec25a8951887c5b44c90a` | `eeff67a3004cb0eaa3fdcf7f0356ae9b4fd440b781ece437cb6c3b0954d99e10` | `db4baab9855fdaff166d2a43b8baedfc2183349bbc8ec25a8951887c5b44c90a` | LF |
| 910005 / `world_fengmo_valley` | `238301f21e160ec5bfe213fdf7816f1cc71ceac979f11ad710c4cd8c894735c9` | `238301f21e160ec5bfe213fdf7816f1cc71ceac979f11ad710c4cd8c894735c9` | `43b30293f3e1429da12382c88c11781b022e959e3011f064d289c9ddcf4d7a19` | `238301f21e160ec5bfe213fdf7816f1cc71ceac979f11ad710c4cd8c894735c9` | LF |
| 910006 / `world_white_day_gate` | `83cd2fcbcb56986390a894caac3caf57b31cf121b8bc9bbaf823679b1d1207b2` | `83cd2fcbcb56986390a894caac3caf57b31cf121b8bc9bbaf823679b1d1207b2` | `333e3f8649fcfe254b0ef4c3bb9589dbc62758a2979763f020d458804f12fc41` | `83cd2fcbcb56986390a894caac3caf57b31cf121b8bc9bbaf823679b1d1207b2` | LF |
| 910007 / `world_cangyue_island` | `e85ac999dc2ee0b800653aa933b1a2ea26f68012b56ac2831db05b5c44c70e21` | `e85ac999dc2ee0b800653aa933b1a2ea26f68012b56ac2831db05b5c44c70e21` | `aef2439a311054cbc6f264181bdbb65a02b472a1644d10aabec5229ed1722e4f` | `e85ac999dc2ee0b800653aa933b1a2ea26f68012b56ac2831db05b5c44c70e21` | LF |
| 911001 / `bich_orc_tomb_f1` | `c989be3d26993767ed54f0ccfd447250e6f9a0fe749b8d94f1df6cadcedfbf25` | `c989be3d26993767ed54f0ccfd447250e6f9a0fe749b8d94f1df6cadcedfbf25` | `659858baf02b3d1ec2fbfc6b2c27c9de984c31f5eac94fd9a08c6ad24763ff0c` | `c989be3d26993767ed54f0ccfd447250e6f9a0fe749b8d94f1df6cadcedfbf25` | LF |
| 911002 / `bich_orc_tomb_f2` | `4d94f48602115c50adabc8f94901ee40b95df185d19f58b20a5793334b007d2b` | `4d94f48602115c50adabc8f94901ee40b95df185d19f58b20a5793334b007d2b` | `f4aa29f8dd558df8ae8a60a8e8a39b101aa9402d002afb3acc09f54699f3a006` | `4d94f48602115c50adabc8f94901ee40b95df185d19f58b20a5793334b007d2b` | LF |
| 911003 / `bich_orc_tomb_f3` | `ef046036372991dd490e025ec3d6d37cf95ed7132910e76c4cb271d75570cd95` | `ef046036372991dd490e025ec3d6d37cf95ed7132910e76c4cb271d75570cd95` | `0bae701f1e9c9957af81532892a434f57410c0841fccd3e469c8ca245d7110a0` | `ef046036372991dd490e025ec3d6d37cf95ed7132910e76c4cb271d75570cd95` | LF |
| 911101 / `bich_mine_f1` | `2e7bc6a51289c459004c25cbbff9aa3ae602fbee702ff56a4eb20d7bfde27e56` | `2e7bc6a51289c459004c25cbbff9aa3ae602fbee702ff56a4eb20d7bfde27e56` | `762618e5d0536d0ad25008ba1d3d5916c23505db873a85f1bbf8ddf812ba8e5c` | `2e7bc6a51289c459004c25cbbff9aa3ae602fbee702ff56a4eb20d7bfde27e56` | LF |
| 911102 / `bich_mine_f2` | `409747ec11a36127d01701aa0ce48cf6ab5ece94d6612d27151e1c1621b6b5f9` | `409747ec11a36127d01701aa0ce48cf6ab5ece94d6612d27151e1c1621b6b5f9` | `4912b6e3541bf92e821d54a7e21903aedc41e7d7fac59da1c14b7187735ae644` | `409747ec11a36127d01701aa0ce48cf6ab5ece94d6612d27151e1c1621b6b5f9` | LF |
| 911103 / `bich_corpse_king_hall` | `f80d83e3dd3a451e390e28ab160f334edc59acbda9625efa86cafb3982d0b4a5` | `f80d83e3dd3a451e390e28ab160f334edc59acbda9625efa86cafb3982d0b4a5` | `29069ab0ccaddc39a3fb4e3659db7e8dba2ace4fd74040a6cbc01c67ebc6e1c2` | `f80d83e3dd3a451e390e28ab160f334edc59acbda9625efa86cafb3982d0b4a5` | LF |
| 912001 / `snake_mine_passage_1` | `1426f62eaf2523c3ccb46d18181f871c0f95ced7d6afef8ffe9203477fc88c67` | `1426f62eaf2523c3ccb46d18181f871c0f95ced7d6afef8ffe9203477fc88c67` | `70062af07641b5b08202e5471c332246468c92439917669bd8b61f9d0b104a43` | `1426f62eaf2523c3ccb46d18181f871c0f95ced7d6afef8ffe9203477fc88c67` | LF |
| 912002 / `snake_mine_passage_2` | `4545a70f5f30c2ae16dd9f19656e75e8f325f198236aa5bc18bb3c5d1c07bf9b` | `4545a70f5f30c2ae16dd9f19656e75e8f325f198236aa5bc18bb3c5d1c07bf9b` | `fcfe4f6e95b7193a831a4750e042a8f35a9c149dc3c84ec493d334aed53e827b` | `4545a70f5f30c2ae16dd9f19656e75e8f325f198236aa5bc18bb3c5d1c07bf9b` | LF |
| 912003 / `snake_unknown_dark_palace` | `a209c08a5dbedc1f99c2b4b9e591c666723e783fc5c9b00098f718a18d43fb5b` | `a209c08a5dbedc1f99c2b4b9e591c666723e783fc5c9b00098f718a18d43fb5b` | `e0f81eddb41623c2b93f92d7c61dcb96d6f54add1e7f445c7f067ab0ead4e238` | `a209c08a5dbedc1f99c2b4b9e591c666723e783fc5c9b00098f718a18d43fb5b` | LF |
| 913001 / `mengzhong_stone_tomb_f1` | `4a002d338887a4e64049244a14ea9e64841dd9af70d9cfa15d101da56d5a3291` | `4a002d338887a4e64049244a14ea9e64841dd9af70d9cfa15d101da56d5a3291` | `8e50b52b99fd0bdfb56348487fef07c382f6c18dd7c9c9c2b877b98709ba8ae7` | `4a002d338887a4e64049244a14ea9e64841dd9af70d9cfa15d101da56d5a3291` | LF |
| 913002 / `mengzhong_stone_tomb_f2` | `6f6b67e49bb1997b83687eed902f1bab2fa088a1a9b70618fe347082c182f6c4` | `6f6b67e49bb1997b83687eed902f1bab2fa088a1a9b70618fe347082c182f6c4` | `36bccd91f3cab82b3985b6a4efa4c64e04b2d7cfcbdeb2842b6830d322b83c5b` | `6f6b67e49bb1997b83687eed902f1bab2fa088a1a9b70618fe347082c182f6c4` | LF |
| 913003 / `mengzhong_stone_tomb_f3` | `b7e28c27d481c2dd37d50dd63235149810a8117175e74aace89e6b2883fde6cb` | `b7e28c27d481c2dd37d50dd63235149810a8117175e74aace89e6b2883fde6cb` | `c37e87a2a84d1b358317377cb99b90e4d1b37e4a2ffdf5f35a258d62936ff0a9` | `b7e28c27d481c2dd37d50dd63235149810a8117175e74aace89e6b2883fde6cb` | LF |
| 913004 / `mengzhong_stone_tomb_f4` | `db62dfd46c6d8952c0a06e6b577aab29dec98964cecb3e97ed9a2578ec298cc6` | `db62dfd46c6d8952c0a06e6b577aab29dec98964cecb3e97ed9a2578ec298cc6` | `8afd23ef97e9e58b980dd617195b8bd240194ef3820105e5b4a807c71dc20c66` | `db62dfd46c6d8952c0a06e6b577aab29dec98964cecb3e97ed9a2578ec298cc6` | LF |
| 913101 / `mengzhong_zuma_temple_f1` | `cb1910ea32e481d5aaf02369503edf2bb173dad81dbc8261b538348a68ec89fa` | `cb1910ea32e481d5aaf02369503edf2bb173dad81dbc8261b538348a68ec89fa` | `248063201f8e69638bb4d845bb03b565dd532aa8bda938f628081dab64871223` | `cb1910ea32e481d5aaf02369503edf2bb173dad81dbc8261b538348a68ec89fa` | LF |
| 913102 / `mengzhong_zuma_temple_f2` | `a92e2b3cff650d5f4512311f1fa07af46aa6479ee82619a5034b92c9a24a05fd` | `a92e2b3cff650d5f4512311f1fa07af46aa6479ee82619a5034b92c9a24a05fd` | `92253d14851d79447bc3c33de34ff9393ddbb5119cd46d9f7b4b62485818b2df` | `a92e2b3cff650d5f4512311f1fa07af46aa6479ee82619a5034b92c9a24a05fd` | LF |
| 913103 / `mengzhong_zuma_temple_f3` | `fb7353dc588b09e9ea1e24b443f31b5b52048ebd070918b4234435c9e46e8f84` | `fb7353dc588b09e9ea1e24b443f31b5b52048ebd070918b4234435c9e46e8f84` | `66323a7ee4cc4dcc01f1b40b0a959f1d6f03b0ec1263c515386962b051da4dbb` | `fb7353dc588b09e9ea1e24b443f31b5b52048ebd070918b4234435c9e46e8f84` | LF |
| 913104 / `mengzhong_zuma_temple_f4` | `3f536a33e81874e8d4e35cf1e6169e305d56f302bb6319de6cc4b2399eceb6cb` | `3f536a33e81874e8d4e35cf1e6169e305d56f302bb6319de6cc4b2399eceb6cb` | `00848acec67be540e36eac69a01309183785ede2d5143bcb10746bead4a49eff` | `3f536a33e81874e8d4e35cf1e6169e305d56f302bb6319de6cc4b2399eceb6cb` | LF |
| 913105 / `mengzhong_zuma_pavilion` | `6600ccb722aacbcdd231475e25eddc2e0da573e0bf1ce2f5b8c7536c8e211759` | `6600ccb722aacbcdd231475e25eddc2e0da573e0bf1ce2f5b8c7536c8e211759` | `cbb792d092d4bff0f1bf9d410be6fc21fc4be27f7e73297bf98bda76303e38b5` | `6600ccb722aacbcdd231475e25eddc2e0da573e0bf1ce2f5b8c7536c8e211759` | LF |
| 913106 / `mengzhong_zuma_leader_home` | `71c473c74615deb997dc7578b9fd38afd4e1f4bba5a07803efaa73ccba9f9e9b` | `71c473c74615deb997dc7578b9fd38afd4e1f4bba5a07803efaa73ccba9f9e9b` | `f8c528ec7adda958b6399fd635bf4823980c0729c4db5cc888fad72cfecbdb6b` | `71c473c74615deb997dc7578b9fd38afd4e1f4bba5a07803efaa73ccba9f9e9b` | LF |
| 913201 / `mengzhong_death_valley_dungeon` | `7b4f202391f08d2e6e68ae768b047c9188607417c837ac6aacded681120c290b` | `7b4f202391f08d2e6e68ae768b047c9188607417c837ac6aacded681120c290b` | `ccaa619121ae621a11b79d599c20339ed80c153dc90d9135c445a1cb59f0fe55` | `7b4f202391f08d2e6e68ae768b047c9188607417c837ac6aacded681120c290b` | LF |
| 913202 / `mengzhong_stone_coffin_room` | `5fa7df120b4cbc2d435daefda36329bcb9065ddd0de6e3fd5371e3964b6d8c3d` | `5fa7df120b4cbc2d435daefda36329bcb9065ddd0de6e3fd5371e3964b6d8c3d` | `3a24e5acf4b4d9023776432f5bc7dbedf2674ebd6fc582c242b5c6d04b3a86f9` | `5fa7df120b4cbc2d435daefda36329bcb9065ddd0de6e3fd5371e3964b6d8c3d` | LF |
| 913203 / `mengzhong_dark_area` | `9ed5ff0d7ee975a5cc5a6b4f0c58a86c5b1266541a7f0d25686c15231570937b` | `9ed5ff0d7ee975a5cc5a6b4f0c58a86c5b1266541a7f0d25686c15231570937b` | `dc3730d2e0d0904ebaad2a7020ab76f53deae30ae1e48c4521112beb5751709d` | `9ed5ff0d7ee975a5cc5a6b4f0c58a86c5b1266541a7f0d25686c15231570937b` | LF |
| 913204 / `mengzhong_between_life_and_death` | `06655a4a2ca93c97b44f78e1d8df8609e9c00235bac60ea5426fcdaab9120ae8` | `06655a4a2ca93c97b44f78e1d8df8609e9c00235bac60ea5426fcdaab9120ae8` | `168923e4bfdd403e3def9bef0935b6949e9eaf036238f7885c549dc6fa6316cb` | `06655a4a2ca93c97b44f78e1d8df8609e9c00235bac60ea5426fcdaab9120ae8` | LF |
| 913205 / `mengzhong_terror_space` | `5a74e45ecffa564f2b35928c844ba8881aee49e36bb11ecd0e67a2fbf8d62148` | `5a74e45ecffa564f2b35928c844ba8881aee49e36bb11ecd0e67a2fbf8d62148` | `1344738c8219db40a8869ea26305dedec5720d011926a63366282bdb3071ba0e` | `5a74e45ecffa564f2b35928c844ba8881aee49e36bb11ecd0e67a2fbf8d62148` | LF |
| 913206 / `mengzhong_thin_sky_passage` | `7aee243a2bc05b0e5cd9636d2fd54a55c5756ae8477cdfbc92ede22501664eff` | `7aee243a2bc05b0e5cd9636d2fd54a55c5756ae8477cdfbc92ede22501664eff` | `d6ae1a1e24dd055e47bbdcce5b97972e1590e9dd14ea3fb95e2958b645f58cfb` | `7aee243a2bc05b0e5cd9636d2fd54a55c5756ae8477cdfbc92ede22501664eff` | LF |
| 913207 / `mengzhong_death_coffin` | `90adddd89cb04010d716874ff3b540847533a802ab9b340a96bdcef77e684501` | `90adddd89cb04010d716874ff3b540847533a802ab9b340a96bdcef77e684501` | `5e4cd67a31b0bec6ebc8901419fe7acaef7410c43da9d5cce710fd734b1df03e` | `90adddd89cb04010d716874ff3b540847533a802ab9b340a96bdcef77e684501` | LF |
| 914001 / `fengmo_forked_path` | `70765b7c129eada78ad3d683daa5f6173cb25b66dc2553aee63df73af505901f` | `70765b7c129eada78ad3d683daa5f6173cb25b66dc2553aee63df73af505901f` | `1ee1847f9ab71fcb7449bc83421a498d48147a52ca2f49769163f40ab665eaea` | `70765b7c129eada78ad3d683daa5f6173cb25b66dc2553aee63df73af505901f` | LF |
| 914002 / `fengmo_light_corridor` | `af8402287ce36c5edb59e651582b1da17090dd68318a3eb9ac9638f9292a645b` | `af8402287ce36c5edb59e651582b1da17090dd68318a3eb9ac9638f9292a645b` | `c9e95f8a9bdfef20e0d1a275f81354f112c9f43207b5e32adc6d56b59d817c65` | `af8402287ce36c5edb59e651582b1da17090dd68318a3eb9ac9638f9292a645b` | LF |
| 914003 / `fengmo_thunder_road` | `f0bb660cfe1a26a44aa23b16ac5c45259aba2dad9332bdeea50888e15a69d703` | `f0bb660cfe1a26a44aa23b16ac5c45259aba2dad9332bdeea50888e15a69d703` | `574581ef2654c38e647ffb54d53a95bf1f64ced4207f933aeec16add046ad83f` | `f0bb660cfe1a26a44aa23b16ac5c45259aba2dad9332bdeea50888e15a69d703` | LF |
| 914004 / `fengmo_bazhe_hall` | `7b3a7f1be9091487b528d5d430a6d1396f7220932278f04fd4c6f001b7052528` | `7b3a7f1be9091487b528d5d430a6d1396f7220932278f04fd4c6f001b7052528` | `1ae74bc41bbf7f817bc0f69a4e8287741f2e318fae4277cb43697a718673d0f2` | `7b3a7f1be9091487b528d5d430a6d1396f7220932278f04fd4c6f001b7052528` | LF |
| 914005 / `fengmo_zonghengdao` | `41a611b4ef41642dc6b191365762558c209bbfa6719495bdc0368e178f6d8d45` | `41a611b4ef41642dc6b191365762558c209bbfa6719495bdc0368e178f6d8d45` | `5433e4155b847175abc49da7d543e55ee84df706b30dc8d3851cef13b761a26d` | `41a611b4ef41642dc6b191365762558c209bbfa6719495bdc0368e178f6d8d45` | LF |
| 914006 / `fengmo_mohun_hall` | `71e8c6f4c11a2de40608e0f5e2b004ea5a4266d7badc03bcbbb58e16286488b5` | `71e8c6f4c11a2de40608e0f5e2b004ea5a4266d7badc03bcbbb58e16286488b5` | `308b94d1fe14d999952cf96405b15b429da2df90d014ea9a8efff7fd11456551` | `71e8c6f4c11a2de40608e0f5e2b004ea5a4266d7badc03bcbbb58e16286488b5` | LF |
| 914007 / `fengmo_purgatory_corridor` | `1c6b916185fec808c34064593eb1cd0cab876335fc54042accb9993a407ebaa5` | `1c6b916185fec808c34064593eb1cd0cab876335fc54042accb9993a407ebaa5` | `1514ff96bd9c646dd0cf11a6327e338b44d5d76e8a09a23a3d820a39da2cb37f` | `1c6b916185fec808c34064593eb1cd0cab876335fc54042accb9993a407ebaa5` | LF |
| 914008 / `fengmo_final_hall` | `b11169aca63a7e318f3846e61c8f830eed1030fef505c452056022ce1cdd2bb0` | `b11169aca63a7e318f3846e61c8f830eed1030fef505c452056022ce1cdd2bb0` | `3aff91e659ec13607d649dde453cdd8fdf2f8475c944dfaf1364b9bf6ae98388` | `b11169aca63a7e318f3846e61c8f830eed1030fef505c452056022ce1cdd2bb0` | LF |
| 915001 / `wooma_temple_f1` | `02ecc8f7e97c421d54ff5623406ceb440769ab824b10a660b261726189594d93` | `02ecc8f7e97c421d54ff5623406ceb440769ab824b10a660b261726189594d93` | `49cdb67575c82cac3cab65b87397ad8693ff2f952672ad5b3746c6f85c56d25b` | `02ecc8f7e97c421d54ff5623406ceb440769ab824b10a660b261726189594d93` | LF |
| 915002 / `wooma_temple_f2` | `4934ab09bb645647966660ba514882463c4b252fae34dd97c8dfbede4769e9cb` | `4934ab09bb645647966660ba514882463c4b252fae34dd97c8dfbede4769e9cb` | `16fee9aaab64d6f6c33aa069fc1f295c0db3c216a159d6d17916f4eae23425b7` | `4934ab09bb645647966660ba514882463c4b252fae34dd97c8dfbede4769e9cb` | LF |
| 915003 / `wooma_temple_boss_hall` | `4a6f0399ec2643d529f18115da636a25bf989616eda4d79893b4934ba9271699` | `4a6f0399ec2643d529f18115da636a25bf989616eda4d79893b4934ba9271699` | `d92391a6a0019012c983e87cce2f4a3d2ec5dfda9f5fbbbaed0e26af23aa805a` | `4a6f0399ec2643d529f18115da636a25bf989616eda4d79893b4934ba9271699` | LF |
| 916001 / `chiyue_valley` | `f0072698111d9ac1dfbeb6ce3844d6dd9bde657b5bed996fa3bda7b1fe37ee4c` | `f0072698111d9ac1dfbeb6ce3844d6dd9bde657b5bed996fa3bda7b1fe37ee4c` | `3dc48dae12737d0a9fddd2657c60355998aaac60959ad41d9bb20708bc2cb009` | `f0072698111d9ac1dfbeb6ce3844d6dd9bde657b5bed996fa3bda7b1fe37ee4c` | LF |
| 916002 / `chiyue_valley_square` | `3a65146c226e5a9a89555a4594a4faf1f2322f272a634c43658f25a7df10e8ea` | `3a65146c226e5a9a89555a4594a4faf1f2322f272a634c43658f25a7df10e8ea` | `27fbb3f860fd16b0c455de6621158925c339c708354c91771aec9b0380bddbb7` | `3a65146c226e5a9a89555a4594a4faf1f2322f272a634c43658f25a7df10e8ea` | LF |
| 916003 / `chiyue_choice_land` | `6bf7f8f2c49211ffe3055639cbe80e0cd9886b720f56c233e7ee6b124e6cb966` | `6bf7f8f2c49211ffe3055639cbe80e0cd9886b720f56c233e7ee6b124e6cb966` | `caec90f1047d1172bb4332f542159a1aa95c72ad4bfc5dae0488152e55aa8eca` | `6bf7f8f2c49211ffe3055639cbe80e0cd9886b720f56c233e7ee6b124e6cb966` | LF |
| 916004 / `chiyue_valley_secret_passage_a` | `3946918a9ff475977ce9452238ca9dc24b2d0bc051630004afb9d3bcd458b4f8` | `3946918a9ff475977ce9452238ca9dc24b2d0bc051630004afb9d3bcd458b4f8` | `27ef96599242934cc7bd89d5b2913496d91d1135122a79d43ec765c3a6b36cd9` | `3946918a9ff475977ce9452238ca9dc24b2d0bc051630004afb9d3bcd458b4f8` | LF |
| 916005 / `chiyue_valley_secret_passage_b` | `b339da1ba7bac7246e9a8c90524d91d31070e5890e7c6a3b5aa0c48c8ae68e3a` | `b339da1ba7bac7246e9a8c90524d91d31070e5890e7c6a3b5aa0c48c8ae68e3a` | `cc70d50b1ff91f1b3ade4bc1299d810c2f83acd06a68456046408b5f2bb6cf84` | `b339da1ba7bac7246e9a8c90524d91d31070e5890e7c6a3b5aa0c48c8ae68e3a` | LF |
| 916006 / `chiyue_demon_altar` | `8c40d5985eaeb7fb4afd1ca166cbc56728a31e99c9953afdc9a6e9566065dd33` | `8c40d5985eaeb7fb4afd1ca166cbc56728a31e99c9953afdc9a6e9566065dd33` | `0d63ce0684194ef9ec1f47cd041a3817ad76f210f885b9aef372c27dbe9ee7b3` | `8c40d5985eaeb7fb4afd1ca166cbc56728a31e99c9953afdc9a6e9566065dd33` | LF |
| 916007 / `chiyue_red_moon_lair` | `38b8c61bd7b3b1625c57259d3d9853808af93749ebecc09f91874da27b56b4a7` | `38b8c61bd7b3b1625c57259d3d9853808af93749ebecc09f91874da27b56b4a7` | `3b52697184114c75fb9e18767650eb1fc8753e4cad25f32f144911ab1df77139` | `38b8c61bd7b3b1625c57259d3d9853808af93749ebecc09f91874da27b56b4a7` | LF |
| 917001 / `cangyue_bone_cave_f1` | `c222b95c821bb7d164508b8be5ab2101322947cd84304aaa159c821f933bf429` | `c222b95c821bb7d164508b8be5ab2101322947cd84304aaa159c821f933bf429` | `76ecc4064d059d6d4b202a5f8ce7e9d838c0aa4094f3fc262ec47b815bbbd3eb` | `c222b95c821bb7d164508b8be5ab2101322947cd84304aaa159c821f933bf429` | LF |
| 917002 / `cangyue_bone_cave_f2` | `9d1d818624e009016a957234e63d58072d41b96f8f4f2c72c34959af2b5fbd43` | `9d1d818624e009016a957234e63d58072d41b96f8f4f2c72c34959af2b5fbd43` | `8ea19cbb7cf8b71b20ec19b348c3739792619eb2e3c079635b36220177dce2d6` | `9d1d818624e009016a957234e63d58072d41b96f8f4f2c72c34959af2b5fbd43` | LF |
| 917003 / `cangyue_bone_cave_f3` | `d0976f563b34f9797904bd4c1721601ea1d09acb1c0160e407477244407c4030` | `d0976f563b34f9797904bd4c1721601ea1d09acb1c0160e407477244407c4030` | `a3ae4631954a467c65716c052cc530db320c57d482cfc9024fa9e11c676dbca0` | `d0976f563b34f9797904bd4c1721601ea1d09acb1c0160e407477244407c4030` | LF |
| 917004 / `cangyue_bone_cave_f4` | `8a981e9abb4e3fb91e8620bdcbec9771a04b1a9e2661ab14f0c15ec8d9d81ede` | `8a981e9abb4e3fb91e8620bdcbec9771a04b1a9e2661ab14f0c15ec8d9d81ede` | `571ce70e9a1fe2b84273c2dae16d3978de66540296905720da65ac99ebffe43a` | `8a981e9abb4e3fb91e8620bdcbec9771a04b1a9e2661ab14f0c15ec8d9d81ede` | LF |
| 917005 / `cangyue_bone_cave_f5` | `348c0a82a3f3a551f500d7b2d6df9016fcbd7a93f46b91b51cebe7f92c5a638b` | `348c0a82a3f3a551f500d7b2d6df9016fcbd7a93f46b91b51cebe7f92c5a638b` | `ab017d48014617441a60351f1a958588736a177b3b739b40f5fcc45de232da69` | `348c0a82a3f3a551f500d7b2d6df9016fcbd7a93f46b91b51cebe7f92c5a638b` | LF |
| 917101 / `cangyue_bull_temple_f1` | `7924f3deabe87a46ab40a6216770fdada83e1638ef0b2c784e077b6a56f0d6f2` | `7924f3deabe87a46ab40a6216770fdada83e1638ef0b2c784e077b6a56f0d6f2` | `c89c2a4b0b5e01eb337a86384e7c10226b07fe4f34f3506b91f1494d9583afa2` | `7924f3deabe87a46ab40a6216770fdada83e1638ef0b2c784e077b6a56f0d6f2` | LF |
| 917102 / `cangyue_bull_temple_f2` | `86968c2bdd4a96780a1f335e5123d0ce59cfd0ea7959fe98f33a35c5c7c2e1b7` | `86968c2bdd4a96780a1f335e5123d0ce59cfd0ea7959fe98f33a35c5c7c2e1b7` | `94533c835908ccd3d24f05483bab53f9fa031a1f596193ee55eba4599a78d691` | `86968c2bdd4a96780a1f335e5123d0ce59cfd0ea7959fe98f33a35c5c7c2e1b7` | LF |
| 917103 / `cangyue_bull_temple_f3` | `88e20a4527afba7d6d9be74c9972394654c252ac08e033e9b0ef1be0d8bb145f` | `88e20a4527afba7d6d9be74c9972394654c252ac08e033e9b0ef1be0d8bb145f` | `00ef976b38b69fe4a0ec83603999887f45817a13c04306d8cc035b0eff1ec998` | `88e20a4527afba7d6d9be74c9972394654c252ac08e033e9b0ef1be0d8bb145f` | LF |
| 917104 / `cangyue_bull_temple_f4` | `9b9f0e0da494bb9217aa829d868f7bb131d58686eb1d1678b74567043db62695` | `9b9f0e0da494bb9217aa829d868f7bb131d58686eb1d1678b74567043db62695` | `1b705f5de19e1956897e04b3e608fe99a8b938503c91087bd18fcc6da951ec33` | `9b9f0e0da494bb9217aa829d868f7bb131d58686eb1d1678b74567043db62695` | LF |
| 917105 / `cangyue_bull_temple_hall` | `5be000ad80c851cf576fa10f3876281a0bc4e9695026728b6f789287721de658` | `5be000ad80c851cf576fa10f3876281a0bc4e9695026728b6f789287721de658` | `01192b3b3086b11048e9f88621a58017072dc3fa34fb1af532e1b87798d449c9` | `5be000ad80c851cf576fa10f3876281a0bc4e9695026728b6f789287721de658` | LF |
| 918001 / `hidden_confusion_hall` | `3615b0b904a210f72041e48fbee3f3612a90459d76f8619825b5002fe65ab544` | `3615b0b904a210f72041e48fbee3f3612a90459d76f8619825b5002fe65ab544` | `6f88559f2d557184612831fbf5e2dfa816e64295f656ab38b8cd83276514a7f5` | `3615b0b904a210f72041e48fbee3f3612a90459d76f8619825b5002fe65ab544` | LF |
| 918002 / `hidden_hellfire` | `1e3f972cff1a29918466364c2a3f74bd6d43de009be19a8dff464ce058acf4b5` | `1e3f972cff1a29918466364c2a3f74bd6d43de009be19a8dff464ce058acf4b5` | `a7bf6aca1b12cbb2340581f14213445a1aa356796349bbc63af4928ee2135571` | `1e3f972cff1a29918466364c2a3f74bd6d43de009be19a8dff464ce058acf4b5` | LF |
| 918003 / `hidden_fallen_graveyard` | `162b330a2719a95559fbb79e61291543d83bd51bd461bb072dea160bb04dd45b` | `162b330a2719a95559fbb79e61291543d83bd51bd461bb072dea160bb04dd45b` | `e038b1573e5a2aab7f7bf131fa34122fbe86be4cc05216c756afe5c695582b8c` | `162b330a2719a95559fbb79e61291543d83bd51bd461bb072dea160bb04dd45b` | LF |
| 918004 / `hidden_death_temple` | `edbf86d838cc81c677163a3addde0ca2faf8cc84308cfb8cd9470dcbb75a8ef7` | `edbf86d838cc81c677163a3addde0ca2faf8cc84308cfb8cd9470dcbb75a8ef7` | `7b56b4514f0e9af7fe2f6bc7bca924067ddd396dd3ae045b5ece7cf3546b7006` | `edbf86d838cc81c677163a3addde0ca2faf8cc84308cfb8cd9470dcbb75a8ef7` | LF |
| 918005 / `hidden_abyss_domain` | `e3516baf51ee924d617cf6b253dfc64c4390ee83f74c231d7a68775632ae625e` | `e3516baf51ee924d617cf6b253dfc64c4390ee83f74c231d7a68775632ae625e` | `d6ee2aec17132fb7203cc81af3582fbdfd2ff8c01febeef7344086fdff859385` | `e3516baf51ee924d617cf6b253dfc64c4390ee83f74c231d7a68775632ae625e` | LF |
| 918006 / `hidden_pincer_nest` | `3d74ba08853fb767b5fcf890d463cad83e8b1f4ccac60a416301a4a9a0d3794a` | `3d74ba08853fb767b5fcf890d463cad83e8b1f4ccac60a416301a4a9a0d3794a` | `f280765d5435db50c4e2887da25d1144f698d787e1d3242f33ab6c25cd42dfb2` | `3d74ba08853fb767b5fcf890d463cad83e8b1f4ccac60a416301a4a9a0d3794a` | LF |
