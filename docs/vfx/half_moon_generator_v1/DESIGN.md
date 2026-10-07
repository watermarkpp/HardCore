# Half Moon Generator V1 · first visual review

## Outcome and boundaries

This is a local authoring workspace for `半月弯刀` / `wide_hit`. The current browser editor exposes one working version of the archived original eight-direction, six-frame atlas, a real-warrior preview, four cleanup controls, and whole-animation position adjustment. Earlier SW-derived and generated candidates remain in the ignored local project as history, but they are not used in the editor. The user-approved 150% dark-haze result is now the formal effect at the unchanged runtime path.

The tool is implemented in `tools/half_moon_generator/`. It runs a loopback browser interface backed by Python, Pillow and NumPy. The game runtime loads none of this code. The final runtime contract remains one 1440×1792 RGBA `wide_hit.png` sheet with eight direction rows and six frame columns.

## Authority and visual alignment

- Active skin: `classic_client`, resolved through `assets/data/layers/presentation_layer.json` and its skin manifest.
- Formal effect: `assets/art/characters/warrior/effects/wide_hit.png`; original SHA256 `AA0B29F13D5C9A196C5F2372AD47FEFA75F8B328684D4B8689A70F279C26276C`, approved 150% SHA256 `EF9196C3EAA7C9DCB9A01A831D87A4679E6B6D76E5309B7E3526AD236D70CEA4`.
- Formal size/mode: 1440×1792 RGBA, alpha extrema 0..255.
- Playback: `scripts/player_visual.gd` maps 半月弯刀 to `wide_hit`, 240×224 cells, origin (96,143). `scripts/warrior_combat_math.gd` keeps `CLIENT_EFFECT_FRAME = 2`.
- Direction order: logical S, SW, W, NW, N, NE, E, SE maps to rows 4,5,6,7,0,1,2,3 through `ArtSpec.mir2_client_direction_row()`.
- Actor preview reads the active skin's actual warrior attack atlas and three representative equipment overlays. Weapon foot anchors are resolved by exact path from `assets/data/warrior_wear_sources.json`. The preview composes six real attack samples on the same 240×224 effect cell and foot origin. It is an authoring proxy; final in-game acceptance remains a later gate.

## Rendering and retained history

`hmg.py` retains older preset and mutation code for reading and verifying previously saved candidates. The active editor uses the tracked `tools/half_moon_generator/source/wide_hit_original.png` as its exact master, without deriving directions from the separate six SW images. It checks the baseline file hash and processes every original cell deterministically.

The browser animates composite strips over black, gray, a transparency checkerboard or an actual Bich map ground chunk.

Historical `render_version=2` procedural candidates used a 120° facing-aligned fan capped at a 64-pixel source radius, corresponding to the canonical two-GU authoring envelope. They are retained for project compatibility and tests. This affects authoring pixels only; the combat 120°/2-GU geometry and release timing remain unchanged.

Historical candidates are saved in `dev_art_sources/vfx/half_moon_generator/half_moon_project.json`, a local ignored authoring area. The six user-supplied SW PNGs remain there unchanged as archived inputs. The active `original_cleanup_v4` candidate is created from the archived original atlas and selected without deleting any earlier candidate or saved offsets. This version preserves the original shape, timing, row mapping, and cell registration. Every color, transparency, or position edit stores prior values in the working candidate's `revisions` array.

The original atlas uses binary alpha: a pixel is either fully transparent or fully opaque. Its dark-gray opaque body can look dirty on the game's ground. The cleanup computes a local luminance detail signal for every cell, converts weak dark pixels into a smooth alpha gradient, lifts the blue-white body, strengthens the bright cutting edge, and increases local light/dark separation. It never imports pixels from the abandoned SW batch. Four bounded parameters control the pass. Dark-haze cleanup spans 0% to 200%: up to 100% it blends toward the original gradient, and above 100% it progressively suppresses darker alpha without changing RGB or the other controls. Setting cleanup to zero, body brightness to one, and highlight/detail to zero reproduces the original source bytes exactly. The editor saves these parameters in its local working version; it does not change the source PNG.

The user can select a direction and adjust the entire six-frame animation with keyboard arrows at 1 px per press or Shift+arrow at 10 px, without first focusing the preview. The adjustment is stored per direction in `direction_overrides` and can be undone. The old atlas's geometry and the per-direction presentation still require user visual approval.

## Output and publish boundary

“导出预览 PNG” writes only under `outputs/half_moon_generator/`; it validates cell count, dimensions, alpha, clipping and continuity warnings. The 8×6 contact sheet uses the same deterministic bake. The interface has no Publish action. The approved 150% profile was explicitly baked into the unchanged `wide_hit.png` runtime path. `tools/build_warrior_client_effects.py` reproduces it from the tracked original source and records its hash in the warrior art manifest. Player animation, combat math, target geometry and the active skin manifest were not changed.

The user accepted the 150% appearance and requested zero positional offset. The remaining package gate is to include this exact asset and the other skill-animation branch in a future APK built from their integrated, verified source state; the editor preview alone does not prove package contents or device appearance.
