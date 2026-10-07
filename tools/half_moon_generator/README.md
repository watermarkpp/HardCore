# 2026-10-07 补入状态：历史素材编辑与预览工具

完整保留旧主树独有的工具与原始素材，用于历史 authoring 和本地预览。此次迁移回归为 62 项：48 PASS、13 FAIL、1 ERROR。旧工具的 approved 烘焙输出哈希/像素、manifest override 合同与当前正式素材不兼容；旧主树正式素材也不能满足这些失败断言。当前正式素材继续以第三树版本为准。

此目录没有获得当前 runtime 素材验收。不要按下方历史“approved”描述覆盖正式数据；预览实验应继续留在独立本地项目。逐项失败与源哈希见 `docs/retired/20261007/HALF_MOON_COMPATIBILITY_REVIEW.json`，原始日志在 `outputs/half_moon_promotion_tests.log`。下方为原工具说明，保留其历史上下文。

---

# Half Moon original-material editor

Start from the HardCore repository root with Python 3.12, Pillow and NumPy:

```powershell
& 'C:\Windows\py.exe' -3.12 -m tools.half_moon_generator.server --port 8765
```

Open `http://127.0.0.1:8765/`. The loopback server creates or selects one `HM_ORIGINAL_WORK` candidate in the ignored local project at `dev_art_sources/vfx/half_moon_generator/half_moon_project.json`. It derives all 48 frames from the archived original at `tools/half_moon_generator/source/wide_hit_original.png`, checking its SHA256 before rendering. Older SW-image and procedural candidates remain in the project file as an archive and are not exposed in the editor.

The same server offers separate previews for [攻杀剑术](http://127.0.0.1:8765/power) and [刺杀剑术](http://127.0.0.1:8765/thrust). Both read their archived original PNG, align eight directions and six frames with the real warrior animation, and save sliders and undo history to separate ignored projects in `dev_art_sources/vfx/half_moon_generator/`. The user-approved 200% power-hit and 150% thrust cleanup are baked into the formal `power_hit.png` and `long_hit.png`; the editors continue to allow preview experiments without automatically replacing them.

[烈火剑法](http://127.0.0.1:8765/fire) uses four archived 1920×1920 source shards and the game's per-frame weapon-tip and ignition metadata. Its editor composites the fire onto real warrior sword or heavy-weapon frames. The user-approved 30% dark-fire cleanup is baked into the four formal `fire_hit_d*_f*.png` shards; the original shards remain archived and the editor does not publish later experiments automatically.

[火球术](http://127.0.0.1:8765/fireball) previews the 16 directions × 6 frames actually played by `CasterSkillAnimationPlayer` from `assets/art/characters/caster_skill_frames/fireball/`. It validates the original frames against primary `Magic.wil` and displays both the runtime 34-pixel fit and enlarged source detail. The approved 150% dark-fire cleanup is baked into those 96 same-name frames and the representative `wizard/effects/fireball.png`; exact original frame hashes and output hashes are in `assets/data/caster_skill_visuals.json`. `& 'C:\Windows\py.exe' -3.12 tools/build_caster_client_art.py --fireball-only` regenerates only fireball. Later 0–300% editor experiments stay in a separate ignored local preview project and do not republish automatically.

[抗拒火环](http://127.0.0.1:8765/repulsion) previews the ten primary `Magic.wil` frames at the game's source-pixel scale, using the sequence-bounds centering applied by `CasterSkillVisualEffect`. The approved 100% dark-fire cleanup is baked into those ten same-name frames and `wizard/effects/repulsion_ring.png`. `& 'C:\Windows\py.exe' -3.12 tools/build_caster_client_art.py --repulsion-only` regenerates only this skill; further editor experiments do not republish automatically.

[诱惑之光](http://127.0.0.1:8765/temptation) previews the 16 primary blue-white frames attached to a target actor. The approved 150% dark-blue/gray cleanup is baked into all 16 same-name frames and `wizard/effects/temptation_light.png`; source RGB, geometry and timing are unchanged. `& 'C:\Windows\py.exe' -3.12 tools/build_caster_client_art.py --temptation-only` regenerates only this skill.

[雷电术](http://127.0.0.1:8765/lightning) remains a comparison view of the original six `Magic2.wil` frames with 0–300% dark-blue/gray transparency and automatic looping playback. The user chose the new APNG material in the separate worktree as final for this skill; this historical preview does not bake or change either formal frame set.

[地狱火](http://127.0.0.1:8765/hellfire) reads the six original `Magic.wil` frames and previews the production `firegun_trail` sequence: one emission every 50 ms, each segment aging through six frames, centered on the sequence bounds and spread along a sample five-tile target line. The selector changes only the sample screen direction. Its geometric core band is illustrative; combat snapshot geometry remains authoritative. The approved 150% dark-area cleanup is baked into six same-name frames and the representative texture; RGB, timing and offsets remain unchanged. `& 'C:\Windows\py.exe' -3.12 tools/build_caster_client_art.py --hellfire-only` regenerates only this skill.

[瞬息移动](http://127.0.0.1:8765/teleport) previews original `Magic.wil` departure frames 1590–1599 and arrival frames 1600–1609 in one automatic loop at 30 ms per frame. The approved 100% dark-blue/gray cleanup is baked into all 20 same-name frames and the representative texture. The 0–300% slider continues to change only the local preview. `& 'C:\Windows\py.exe' -3.12 tools/build_caster_client_art.py --teleport-only` regenerates only this skill.

[大火球](http://127.0.0.1:8765/great-fireball) previews the 16 directions × six original `Magic.wil` frames 410–565 at production projectile scale and anchor. The approved 150% dark-area cleanup is baked into all 96 same-name frames and the representative texture. The 0–300% slider continues to change only the ignored local preview project. `& 'C:\Windows\py.exe' -3.12 tools/build_caster_client_art.py --great-fireball-only` regenerates only this skill.

[爆裂火焰](http://127.0.0.1:8765/exploding-flame) previews the twenty original `Magic.wil` frames 1660–1679 at production source-pixel size and world anchor. The approved 100% dark-area cleanup is baked into all twenty same-name frames and the representative texture. The enlarged game-ground stage keeps the full effect visible; the 0–300% slider changes only the ignored local preview project. `& 'C:\Windows\py.exe' -3.12 tools/build_caster_client_art.py --exploding-flame-only` regenerates only this skill.

[火墙](http://127.0.0.1:8765/fire-wall) previews one ground flame from the six original `Magic.wil` frames 1630–1635 at production source-pixel size and world anchor. The approved 100% dark-area cleanup is baked into all six same-name frames and the representative texture. The enlarged stage shows the full flame, and the 0–300% slider changes only the ignored local preview project. `& 'C:\Windows\py.exe' -3.12 tools/build_caster_client_art.py --fire-wall-only` regenerates only this skill.

[地狱雷光](http://127.0.0.1:8765/hell-lightning) previews the ten original `Magic.wil` frames 1680–1689 at source-pixel size with the production sequence-centred anchor. The live game can further fit the effect to its canonical geometry footprint. The approved 120% dark-area cleanup is baked into the ten same-name frames and representative texture; the 0–300% slider now changes only the ignored local preview project. `& 'C:\Windows\py.exe' -3.12 tools/build_caster_client_art.py --hell-lightning-only` regenerates only this skill.

[魔法盾](http://127.0.0.1:8765/magic-shield) previews the ten original `Magic.wil` frames 3880–3889 at source-pixel size with the production actor-footpoint anchor. The left stage uses the male wizard base idle frame from the game catalog and draws the shield in front of the actor, matching the formal game draw order. The approved 100% dark-gold cleanup is baked into the ten same-name frames and representative texture. The 0–300% slider changes only the ignored local preview project. `& 'C:\Windows\py.exe' -3.12 tools/build_caster_client_art.py --magic-shield-only` regenerates only this skill.

[圣言术](http://127.0.0.1:8765/holy-word) previews the sixteen original `Magic.wil` frames 3930–3945 at source-pixel size and target-actor anchor. The approved 150% dark-area cleanup is baked into the sixteen same-name frames and representative texture. The 0–300% slider changes only the ignored local preview project. `& 'C:\Windows\py.exe' -3.12 tools/build_caster_client_art.py --holy-word-only` regenerates only this skill.

[冰咆哮](http://127.0.0.1:8765/ice-storm) previews the twenty original `Magic.wil` frames 3850–3869 at source-pixel size and world anchor. The production PNGs use the approved 115% dark-area cleanup; further 0–300% slider changes affect only the ignored local preview project.

[冰咆哮混合对照](http://127.0.0.1:8765/ice-storm-blend) compares the approved 115% PNG with the same original WIL frames composited using an RGB screen blend approximation. It keeps production frames unchanged and does not emulate the classic client's final 256-color palette remapping.

The half-moon page exposes four reversible whole-atlas cleanup controls: dark-haze transparency, blue-white body brightness, edge highlight and texture detail. Its dark-haze transparency ranges from 0% to 200%. It also retains per-direction, whole-six-frame arrow-key placement. Shift+arrow moves ten pixels, and undo restores the previous parameter set. The power, thrust and fire pages expose dark-region transparency from 0% to 300%. A zeroed cleanup is byte-identical to the original frame pixels. Editors never modify formal assets automatically; half-moon preview bakes and contact sheets go to `outputs/half_moon_generator/`.

Run focused tests:

```powershell
& 'C:\Windows\py.exe' -3.12 -m unittest tools.half_moon_generator.test_hmg tools.half_moon_generator.test_power_editor tools.half_moon_generator.test_thrust_editor tools.half_moon_generator.test_fire_editor tools.half_moon_generator.test_fireball_editor tools.half_moon_generator.test_repulsion_editor tools.half_moon_generator.test_temptation_editor tools.half_moon_generator.test_lightning_editor tools.half_moon_generator.test_hellfire_editor tools.half_moon_generator.test_teleport_editor tools.half_moon_generator.test_great_fireball_editor tools.half_moon_generator.test_exploding_flame_editor tools.half_moon_generator.test_fire_wall_editor tools.half_moon_generator.test_hell_lightning_editor -q
```

The user-approved 150% half-moon, 200% power-hit, 150% thrust and 30% fire-sword settings have been baked into the original formal paths, dimensions and frame layouts. The editor has no automatic Publish action; later experiments will not overwrite any formal sheet. `tools/build_warrior_client_effects.py` rebuilds all seven approved atlases/shards from the archived original sources and records the overrides in `assets/data/warrior_client_art_sources.json`.

For the approved fireball, run `& 'C:\Windows\py.exe' -3.12 tools/audit_caster_skill_visual_sources.py --fireball-only` to check all 96 output pixels against the exact primary WIL and 150% cleanup. The full caster audit also checks unrelated skills-lane source hashes and may fail on an existing mismatch between the current skill source file and the hash recorded in the baseline manifest.
