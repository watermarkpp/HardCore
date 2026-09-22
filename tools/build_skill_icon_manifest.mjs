#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const sharp = require("sharp");

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OUTPUT_ROOT = path.join(
  ROOT,
  "assets",
  "ui",
  "gothic_hud",
  "v2",
  "runtime",
  "skill_icons",
  "generated_v2",
);
const SKILLS_PATH = path.join(ROOT, "assets", "data", "vanilla_176", "skills.json");
const MANIFEST_PATH = path.join(OUTPUT_ROOT, "skill_icon_manifest.json");

const explicitReferences = {
  "warrior.basic_swordsmanship": "assets/art/characters/warrior/male/warrior_attack.png",
  "warrior.slaying_swordsmanship": "assets/ui/gothic_hud/v2/runtime/skill_icons/skill_power_hit.png",
  "warrior.thrusting": "assets/ui/gothic_hud/v2/runtime/skill_icons/skill_long_hit.png",
  "warrior.half_moon": "assets/ui/gothic_hud/v2/runtime/skill_icons/skill_wide_hit.png",
  "warrior.wild_rush": "assets/ui/gothic_preview/icons/runtime_v2/skill_wild_rush.png",
  "warrior.fire_sword": "assets/ui/gothic_hud/v2/runtime/skill_icons/skill_fire_hit.png",
  "taoist.spiritual_warfare": "assets/ui/gothic_preview/icons/runtime_v2/function_attack.png",
  "taoist.entrapment": "assets/art/characters/taoist/skill_icons/binding_circle.png",
};

function referenceFor(skillId) {
  if (explicitReferences[skillId]) return explicitReferences[skillId];
  const [profession, slug] = skillId.split(".");
  return `assets/art/characters/${profession}/skill_icons/${slug}.png`;
}

const skillsRoot = JSON.parse(await fs.readFile(SKILLS_PATH, "utf8"));
const rankZeroRecords = skillsRoot.records.filter((record) => record.skillLevel === 0);
const entries = [];

for (const record of rankZeroRecords) {
  const skillId = record.skill_id;
  const relativeOutput = `assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/${skillId.replaceAll(".", "_")}.png`;
  const absoluteOutput = path.join(ROOT, ...relativeOutput.split("/"));
  const fileBytes = await fs.readFile(absoluteOutput);
  const metadata = await sharp(fileBytes).metadata();
  if (metadata.width !== 128 || metadata.height !== 128 || !metadata.hasAlpha) {
    throw new Error(`invalid final icon contract for ${skillId}: ${metadata.width}x${metadata.height}, alpha=${metadata.hasAlpha}`);
  }
  entries.push({
    skill_id: skillId,
    display_name: record.display_name,
    description: record.description,
    animation_reference: referenceFor(skillId),
    design_method: "animation_shape_plus_name_plus_description_to_gothic_physical_subject",
    output: relativeOutput,
    width: metadata.width,
    height: metadata.height,
    has_alpha: metadata.hasAlpha,
    sha256: crypto.createHash("sha256").update(fileBytes).digest("hex"),
  });
}

const manifest = {
  schema_version: 3,
  contract_id: "ui.skill_icons.gothic_physical.v3",
  skill_authority: "assets/data/vanilla_176/skills_source_of_truth_v1.json",
  description_authority: "assets/data/vanilla_176/skills.json rank 0",
  generation_mode: "built_in_imagegen",
  visual_direction: "gothic, photorealistic physical objects and magic entities, no cartoon styling",
  final_asset_contract: {
    width: 128,
    height: 128,
    format: "PNG",
    background: "true RGBA transparency",
    fallback_forbidden: ["skill book icon", "generic item icon", "combat-frame icon"],
  },
  skill_count: entries.length,
  skills: entries,
};

await fs.writeFile(MANIFEST_PATH, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
console.log(`SKILL_ICON_MANIFEST_PASS: ${entries.length} entries -> ${MANIFEST_PATH}`);

