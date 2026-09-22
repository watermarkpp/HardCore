#!/usr/bin/env node

/**
 * Generate the native HardCore skill-icon set.
 *
 * Every icon is authored as a 128x128 SVG string and rasterized by sharp at
 * that same 128x128 canvas.  There is intentionally no resize/downsample
 * step: the SVG viewBox, width, and height are all the native output size.
 */

import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const sharp = require("sharp");

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SKILLS_PATH = path.join(ROOT, "assets", "data", "vanilla_176", "skills.json");
const OUTPUT_DIR = path.join(
  ROOT,
  "assets",
  "ui",
  "gothic_hud",
  "v2",
  "runtime",
  "skill_icons",
  "generated_v2",
);
const MANIFEST_PATH = path.join(OUTPUT_DIR, "skill_icon_manifest.json");
const REVIEW_DIR = path.join(ROOT, "outputs", "skill_icon_review");
const NATIVE_CANVAS = 128;
const GENERATION_POLICY = "native_128_vector_raster_no_downsample";

const EXPECTED_SKILL_IDS = [
  "warrior.basic_swordsmanship",
  "warrior.slaying_swordsmanship",
  "warrior.thrusting",
  "warrior.half_moon",
  "warrior.wild_rush",
  "warrior.fire_sword",
  "wizard.fireball",
  "wizard.repulsion_ring",
  "wizard.temptation_light",
  "wizard.hellfire",
  "wizard.lightning",
  "wizard.teleport",
  "wizard.great_fireball",
  "wizard.exploding_flame",
  "wizard.fire_wall",
  "wizard.laser",
  "wizard.hell_lightning",
  "wizard.magic_shield",
  "wizard.holy_word",
  "wizard.ice_storm",
  "taoist.healing",
  "taoist.spiritual_warfare",
  "taoist.poison",
  "taoist.soul_fire_talisman",
  "taoist.summon_skeleton",
  "taoist.invisibility",
  "taoist.mass_invisibility",
  "taoist.magic_defense",
  "taoist.defense",
  "taoist.revelation",
  "taoist.entrapment",
  "taoist.mass_healing",
  "taoist.summon_divine_beast",
];

const DEFS = `
  <defs>
    <linearGradient id="steel" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#c9c4b2"/>
      <stop offset="0.3" stop-color="#77786f"/>
      <stop offset="0.58" stop-color="#34383a"/>
      <stop offset="1" stop-color="#11161a"/>
    </linearGradient>
    <linearGradient id="steelHi" x1="0" y1="0" x2="0.9" y2="1">
      <stop offset="0" stop-color="#e2dcc6"/>
      <stop offset="0.24" stop-color="#aaa995"/>
      <stop offset="0.7" stop-color="#595b58"/>
      <stop offset="1" stop-color="#202529"/>
    </linearGradient>
    <linearGradient id="brass" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#d2b975"/>
      <stop offset="0.3" stop-color="#9b723f"/>
      <stop offset="0.68" stop-color="#4f3325"/>
      <stop offset="1" stop-color="#211b1a"/>
    </linearGradient>
    <linearGradient id="crimson" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#c3694c"/>
      <stop offset="0.23" stop-color="#8a3533"/>
      <stop offset="0.63" stop-color="#4b1e29"/>
      <stop offset="1" stop-color="#1b171d"/>
    </linearGradient>
    <linearGradient id="ember" x1="0" y1="1" x2="0" y2="0">
      <stop offset="0" stop-color="#6c2a27"/>
      <stop offset="0.32" stop-color="#a44a32"/>
      <stop offset="0.72" stop-color="#be7139"/>
      <stop offset="1" stop-color="#d2a968"/>
    </linearGradient>
    <linearGradient id="arcane" x1="0" y1="1" x2="1" y2="0">
      <stop offset="0" stop-color="#253348"/>
      <stop offset="0.32" stop-color="#3d5368"/>
      <stop offset="0.66" stop-color="#687887"/>
      <stop offset="1" stop-color="#a8aa9f"/>
    </linearGradient>
    <linearGradient id="violet" x1="0" y1="1" x2="1" y2="0">
      <stop offset="0" stop-color="#251d32"/>
      <stop offset="0.38" stop-color="#49364e"/>
      <stop offset="0.74" stop-color="#726071"/>
      <stop offset="1" stop-color="#b1a4a8"/>
    </linearGradient>
    <linearGradient id="ice" x1="0" y1="1" x2="0.8" y2="0">
      <stop offset="0" stop-color="#26343a"/>
      <stop offset="0.42" stop-color="#48666c"/>
      <stop offset="0.76" stop-color="#7c9694"/>
      <stop offset="1" stop-color="#bfc4b5"/>
    </linearGradient>
    <linearGradient id="jade" x1="0" y1="1" x2="1" y2="0">
      <stop offset="0" stop-color="#1a302c"/>
      <stop offset="0.35" stop-color="#355148"/>
      <stop offset="0.7" stop-color="#647b69"/>
      <stop offset="1" stop-color="#a3a37b"/>
    </linearGradient>
    <linearGradient id="teal" x1="0" y1="1" x2="1" y2="0">
      <stop offset="0" stop-color="#19343d"/>
      <stop offset="0.4" stop-color="#3b5e5d"/>
      <stop offset="0.8" stop-color="#6a817b"/>
      <stop offset="1" stop-color="#b5b69a"/>
    </linearGradient>
    <linearGradient id="gold" x1="0" y1="1" x2="1" y2="0">
      <stop offset="0" stop-color="#453427"/>
      <stop offset="0.28" stop-color="#71563a"/>
      <stop offset="0.68" stop-color="#a2804d"/>
      <stop offset="1" stop-color="#d1bc82"/>
    </linearGradient>
    <radialGradient id="blueGlow" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="#91a7b0" stop-opacity="0.22"/>
      <stop offset="0.55" stop-color="#4b6071" stop-opacity="0.08"/>
      <stop offset="1" stop-color="#152255" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="violetGlow" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="#aa92a7" stop-opacity="0.2"/>
      <stop offset="0.58" stop-color="#5b485f" stop-opacity="0.07"/>
      <stop offset="1" stop-color="#27145d" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="jadeGlow" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="#a8b99a" stop-opacity="0.18"/>
      <stop offset="0.55" stop-color="#4d7466" stop-opacity="0.06"/>
      <stop offset="1" stop-color="#093c43" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="warmGlow" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="#c9a064" stop-opacity="0.2"/>
      <stop offset="0.5" stop-color="#8b4134" stop-opacity="0.08"/>
      <stop offset="1" stop-color="#8e2024" stop-opacity="0"/>
    </radialGradient>
    <filter id="glow" x="-30%" y="-30%" width="160%" height="160%">
      <feTurbulence type="fractalNoise" baseFrequency="0.16" numOctaves="2" seed="31" result="grain"/>
      <feColorMatrix in="grain" type="matrix" values="0 0 0 0 0.38 0 0 0 0 0.32 0 0 0 0 0.25 0 0 0 0.28 0" result="grainTint"/>
      <feComposite in="grainTint" in2="SourceGraphic" operator="in" result="grainOnShape"/>
      <feDisplacementMap in="SourceGraphic" in2="grain" scale="1.15" xChannelSelector="R" yChannelSelector="G" result="chipped"/>
      <feBlend in="chipped" in2="grainOnShape" mode="multiply" result="weathered"/>
      <feColorMatrix in="weathered" type="saturate" values="0.48" result="muted"/>
      <feComponentTransfer in="muted"><feFuncR type="linear" slope="0.78"/><feFuncG type="linear" slope="0.78"/><feFuncB type="linear" slope="0.78"/><feFuncA type="identity"/></feComponentTransfer>
    </filter>
  </defs>`;

function gothicizeBody(body) {
  return body
    .replaceAll('stroke-linecap="round"', 'stroke-linecap="square"')
    .replaceAll('stroke-linejoin="round"', 'stroke-linejoin="miter"')
    .replace(/stroke-width="([0-9.]+)"/g, (_match, value) => {
      const width = Math.max(1.15, Number(value) * 0.72);
      return `stroke-width="${width.toFixed(2)}"`;
    });
}

function weatheringOverlay(source) {
  let seed = 0;
  for (let index = 0; index < source.length; index += 1) seed = (seed * 33 + source.charCodeAt(index)) >>> 0;
  const paths = [];
  for (let index = 0; index < 16; index += 1) {
    seed = (seed * 1664525 + 1013904223) >>> 0;
    const x = 22 + (seed % 84);
    seed = (seed * 1664525 + 1013904223) >>> 0;
    const y = 22 + (seed % 84);
    seed = (seed * 1664525 + 1013904223) >>> 0;
    const dx = ((seed % 19) - 9) || 4;
    seed = (seed * 1664525 + 1013904223) >>> 0;
    const dy = ((seed % 19) - 9) || -4;
    const color = index % 4 === 0 ? "#d0bb87" : "#090b0d";
    const opacity = index % 4 === 0 ? 0.31 : 0.35;
    const midX = x + Math.round(dx * 0.55);
    const midY = y + Math.round(dy * 0.55);
    paths.push(`<path d="M${x} ${y}l${dx} ${dy}l${Math.round(-dy / 2)} ${Math.round(dx / 2)}l${Math.round(dx / 3)} ${Math.round(-dy / 3)}" fill="none" stroke="${color}" stroke-width="${index % 4 === 0 ? 1.45 : 1.8}" opacity="${opacity}" stroke-linecap="square"/>`);
    if (index % 4 === 1) paths.push(`<path d="M${midX} ${midY}l${Math.round(-dy * 0.5)} ${Math.round(dx * 0.5)}" fill="none" stroke="#8e3b31" stroke-width="1.2" opacity="0.34" stroke-linecap="square"/>`);
  }
  return `<g pointer-events="none" opacity="0.82">${paths.join("")}</g>`;
}

const svg = (body) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128" preserveAspectRatio="xMidYMid meet">${DEFS}${gothicizeBody(body)}${weatheringOverlay(body)}</svg>`;

const ICONS = {
  "warrior.basic_swordsmanship": svg(`
    <g filter="url(#glow)">
      <circle cx="64" cy="64" r="50" fill="url(#warmGlow)" opacity="0.2"/>
      <circle cx="64" cy="64" r="39" fill="none" stroke="#d39a51" stroke-width="2.5" opacity="0.7"/>
      <circle cx="64" cy="64" r="11" fill="none" stroke="#ffe3a0" stroke-width="3"/>
      <path d="M64 13v19M64 96v19M13 64h19M96 64h19" fill="none" stroke="#e9bb67" stroke-width="3.4" stroke-linecap="round"/>
      <path d="M65 16l9 11-6 39-4 44-4-44-8-39z" fill="url(#steelHi)" stroke="#d9ecff" stroke-width="1.7"/>
      <path d="M64 29v61" stroke="#26364e" stroke-width="2" opacity="0.7"/>
      <path d="M48 65h32M57 92h14" stroke="url(#brass)" stroke-width="5" stroke-linecap="round"/>
      <path d="M60 97l4 10 4-10" fill="#3e2630" stroke="#cc9347" stroke-width="2"/>
    </g>`),

  "warrior.slaying_swordsmanship": svg(`
    <g filter="url(#glow)">
      <circle cx="92" cy="35" r="26" fill="url(#warmGlow)" opacity="0.3"/>
      <path d="M16 106L93 18l14 14-83 79z" fill="url(#steel)" stroke="#d9e8f2" stroke-width="2"/>
      <path d="M28 101l66-76" stroke="#ffffff" stroke-width="2.5" opacity="0.65"/>
      <path d="M71 48l12 12M62 57l12 12" stroke="#222e43" stroke-width="3"/>
      <path d="M26 91l17 16M37 81l17 17" stroke="url(#brass)" stroke-width="7" stroke-linecap="round"/>
      <path d="M18 111l14-14M30 115l10-17M12 98l18 1" stroke="#ef7430" stroke-width="3" stroke-linecap="round"/>
      <path d="M94 13l3 12 10-7-7 11 13 4-14 2 6 12-11-8-4 14-2-14-12 6 8-11-11-8 14 3z" fill="url(#crimson)" stroke="#ffd27a" stroke-width="1.3"/>
      <path d="M100 40l12 9M103 48l7 12M90 27l5-13" stroke="#ff9c4c" stroke-width="2.2" stroke-linecap="round"/>
    </g>`),

  "warrior.thrusting": svg(`
    <g filter="url(#glow)">
      <path d="M13 64h89l17-9-6 9 6 9-17-9H13z" fill="url(#steelHi)" stroke="#dff2ff" stroke-width="1.8"/>
      <path d="M23 53v22M32 49v30" stroke="url(#brass)" stroke-width="5" stroke-linecap="round"/>
      <path d="M101 51l16 13-16 13" fill="none" stroke="#ffd47b" stroke-width="3"/>
      <circle cx="43" cy="64" r="21" fill="none" stroke="#a6d0e5" stroke-width="2.6" opacity="0.7"/>
      <circle cx="87" cy="64" r="22" fill="none" stroke="#ef8a42" stroke-width="2.8" opacity="0.9"/>
      <path d="M24 26l10 10M103 27l-10 10M24 102l10-10M104 102L94 92" stroke="#d89e4e" stroke-width="3.5" stroke-linecap="round"/>
      <path d="M64 13v14M64 101v14" stroke="#ffce72" stroke-width="2.8" stroke-linecap="round"/>
      <circle cx="43" cy="64" r="4" fill="#fff4bb"/><circle cx="87" cy="64" r="4" fill="#ff7840"/>
    </g>`),

  "warrior.half_moon": svg(`
    <g filter="url(#glow)">
      <path d="M14 96Q64 10 114 96Q64 69 14 96z" fill="url(#steelHi)" stroke="#dceeff" stroke-width="2"/>
      <path d="M18 91Q64 28 110 91" fill="none" stroke="#ffcf72" stroke-width="5" stroke-linecap="round"/>
      <path d="M28 101Q64 76 100 101" fill="none" stroke="#9d2e32" stroke-width="3" opacity="0.9"/>
      <path d="M25 83Q64 29 103 83M35 88Q64 48 93 88" fill="none" stroke="#eaf7ff" stroke-width="1.8" opacity="0.7"/>
      <path d="M20 100l-7 8M33 108l-2 8M108 100l7 8M95 108l2 8" stroke="#e35e2e" stroke-width="3" stroke-linecap="round"/>
    </g>`),

  "warrior.wild_rush": svg(`
    <g filter="url(#glow)">
      <path d="M18 74L29 48l25-16 30 10 26 25-16 25-33 10-32-14z" fill="url(#steel)" stroke="#d8eaf4" stroke-width="2"/>
      <path d="M30 50Q17 30 27 18Q41 25 49 39M98 53Q112 31 102 19Q88 26 79 43" fill="none" stroke="url(#brass)" stroke-width="8" stroke-linecap="round"/>
      <path d="M54 44l10-9 10 9-6 36H60z" fill="#26364e" stroke="#d6ecf5" stroke-width="2"/>
      <path d="M75 72l33-10M79 84l25 3" stroke="#f18a39" stroke-width="3.5" stroke-linecap="round"/>
      <path d="M18 61l-9 8 11 4-9 10 19-4M111 79l9-8-11-4 9-10-18 5" fill="none" stroke="#ffcb62" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M25 101l-12 8M39 108l-5 9M102 104l10 7" stroke="#a62b32" stroke-width="4" stroke-linecap="round"/>
    </g>`),

  "warrior.fire_sword": svg(`
    <g filter="url(#glow)">
      <circle cx="64" cy="60" r="44" fill="url(#warmGlow)" opacity="0.28"/>
      <path d="M66 112L58 67l-12-41 18 13 16-13-13 41z" fill="url(#steelHi)" stroke="#fff0c2" stroke-width="2"/>
      <path d="M64 36v61" stroke="#9c2730" stroke-width="3" opacity="0.75"/>
      <path d="M44 71h40" stroke="url(#brass)" stroke-width="7" stroke-linecap="round"/>
      <path d="M59 76l5 15 5-15-2 20-7 7-7-7z" fill="#381928" stroke="#d56e32" stroke-width="2"/>
      <path d="M64 16Q54 28 59 39Q46 30 43 45Q57 42 64 57Q71 42 85 45Q82 30 69 39Q74 28 64 16z" fill="url(#ember)" stroke="#ffd87c" stroke-width="1.5"/>
      <path d="M42 56Q31 66 39 77Q45 68 51 64M86 56Q97 66 89 77Q83 68 77 64" fill="none" stroke="#ef4d28" stroke-width="4" stroke-linecap="round"/>
      <path d="M20 82Q11 69 21 55M108 82Q117 69 107 55" fill="none" stroke="#8d3b2f" stroke-width="3" stroke-linecap="square"/>
    </g>`),

  "wizard.fireball": svg(`
    <g filter="url(#glow)">
      <circle cx="77" cy="61" r="31" fill="url(#warmGlow)" opacity="0.44"/>
      <path d="M56 87Q30 88 13 103Q27 82 45 74Q27 73 20 64Q42 64 57 51Q47 36 58 18Q68 31 68 43Q79 29 92 26Q87 42 88 49Q106 40 114 46Q101 59 98 70Q108 72 116 83Q96 80 85 87Q73 99 56 87z" fill="url(#ember)" stroke="#ffdf8c" stroke-width="1.6"/>
      <circle cx="76" cy="61" r="21" fill="url(#crimson)" stroke="#ffe89f" stroke-width="2"/>
      <circle cx="70" cy="54" r="7" fill="#fff6be" opacity="0.88"/>
      <path d="M48 83l-17 13M41 74l-20 2M49 64l-21-8" stroke="#ef6b2f" stroke-width="3" stroke-linecap="round"/>
    </g>`),

  "wizard.repulsion_ring": svg(`
    <g filter="url(#glow)">
      <circle cx="64" cy="64" r="26" fill="url(#blueGlow)" opacity="0.55"/>
      <circle cx="64" cy="64" r="17" fill="none" stroke="#bdefff" stroke-width="3"/>
      <circle cx="64" cy="64" r="30" fill="none" stroke="url(#arcane)" stroke-width="5" stroke-dasharray="20 8"/>
      <circle cx="64" cy="64" r="45" fill="none" stroke="#73d8ff" stroke-width="2.5" stroke-dasharray="10 17" opacity="0.82"/>
      <path d="M64 12l7 14-7 10-7-10zM116 64l-14 7-10-7 10-7zM64 116l-7-14 7-10 7 10zM12 64l14-7 10 7-10 7z" fill="url(#violet)" stroke="#d5bdff" stroke-width="1.5"/>
      <path d="M26 27l10 9M102 27l-10 9M26 101l10-9M102 101l-10-9" stroke="#69d7ff" stroke-width="3" stroke-linecap="round"/>
    </g>`),

  "wizard.temptation_light": svg(`
    <g filter="url(#glow)">
      <path d="M15 64L88 50l-13 14 13 14z" fill="url(#violet)" opacity="0.85"/>
      <path d="M15 64l76 0" stroke="#d5b3ff" stroke-width="3" stroke-linecap="round"/>
      <path d="M21 51l13 13-13 13M36 48l16 16-16 16M54 44l20 20-20 20" fill="none" stroke="#8b5fe5" stroke-width="2" opacity="0.75"/>
      <path d="M91 45Q106 48 114 64Q106 80 91 83Q78 75 78 64Q78 53 91 45z" fill="#25174c" stroke="#d4a9ff" stroke-width="2"/>
      <path d="M87 64Q96 55 106 64Q96 73 87 64z" fill="url(#arcane)" stroke="#e5d0ff" stroke-width="1.7"/>
      <ellipse cx="97" cy="64" rx="4" ry="9" fill="#0b153d"/><circle cx="98" cy="60" r="2" fill="#f8eeff"/>
      <path d="M18 91l9-6M30 104l5-10M106 98l-7-7" stroke="#7cdffb" stroke-width="3" stroke-linecap="round"/>
    </g>`),

  "wizard.hellfire": svg(`
    <g filter="url(#glow)">
      <path d="M14 102Q22 82 31 91Q38 54 47 82Q56 33 64 80Q73 49 81 82Q91 44 98 85Q108 73 114 102z" fill="url(#ember)" stroke="#ffda78" stroke-width="1.6"/>
      <path d="M20 102Q30 83 39 101Q47 66 56 101Q64 56 73 101Q83 72 92 101Q102 82 109 102" fill="none" stroke="#fff2ad" stroke-width="3" stroke-linecap="round"/>
      <path d="M16 108h96" stroke="#a3292c" stroke-width="5" stroke-linecap="round"/>
      <path d="M25 27v34M46 18v38M67 28v31M89 16v41M109 28v32" stroke="#ef5a2b" stroke-width="4" stroke-linecap="round" opacity="0.8"/>
      <path d="M25 27l7 9-7 10-7-10zM46 18l7 10-7 11-7-11zM89 16l7 10-7 11-7-11z" fill="#ffb84d"/>
    </g>`),

  "wizard.lightning": svg(`
    <g filter="url(#glow)">
      <path d="M21 40Q29 22 47 29Q56 13 73 28Q94 19 105 38Q114 43 110 53H25Q15 50 21 40z" fill="url(#violet)" stroke="#d4c4ff" stroke-width="2"/>
      <path d="M65 28L48 62h15l-8 47 31-61H70z" fill="url(#ice)" stroke="#efffff" stroke-width="2"/>
      <circle cx="55" cy="99" r="17" fill="url(#blueGlow)" opacity="0.7"/>
      <path d="M39 105h32M45 112h20" stroke="#8ddfff" stroke-width="3" stroke-linecap="round"/>
      <path d="M25 64l-10 10M102 64l11 10M27 87l-13 3M101 87l14 3" stroke="#9a76ff" stroke-width="2.8" stroke-linecap="round"/>
    </g>`),

  "wizard.teleport": svg(`
    <g filter="url(#glow)">
      <ellipse cx="64" cy="64" rx="48" ry="37" fill="url(#violetGlow)" opacity="0.38"/>
      <path d="M18 74Q25 37 64 31Q102 27 111 59Q116 87 82 98Q45 111 23 90Q14 82 18 74z" fill="none" stroke="url(#arcane)" stroke-width="4"/>
      <path d="M29 75Q39 48 67 45Q94 44 96 64Q98 84 72 87Q47 91 39 73Q34 61 51 55Q68 49 78 60Q84 71 70 77Q56 82 51 70Q50 61 61 60" fill="none" stroke="url(#violet)" stroke-width="5" stroke-linecap="round"/>
      <path d="M64 53l12 11-12 11-12-11z" fill="url(#ice)" stroke="#e1dcff" stroke-width="1.7"/>
      <path d="M21 27l7 10M103 25l-7 11M20 101l10-6M105 101l-10-6" stroke="#7adfff" stroke-width="3" stroke-linecap="round"/>
      <path d="M12 64l12-5M116 64l-12-5M64 12l-5 12M64 116l-5-12" stroke="#5b4a60" stroke-width="2.4" stroke-linecap="square"/>
    </g>`),

  "wizard.great_fireball": svg(`
    <g filter="url(#glow)">
      <circle cx="64" cy="64" r="48" fill="url(#warmGlow)" opacity="0.38"/>
      <path d="M64 16Q77 26 77 39Q93 31 102 43Q90 49 94 61Q111 61 116 73Q99 76 93 87Q95 101 82 108Q75 94 64 91Q53 105 38 108Q37 94 43 84Q28 82 14 72Q27 61 42 59Q35 48 31 38Q47 37 55 44Q53 27 64 16z" fill="url(#ember)" stroke="#ffe397" stroke-width="2"/>
      <circle cx="64" cy="64" r="28" fill="url(#crimson)" stroke="#ffd987" stroke-width="2.5"/>
      <circle cx="55" cy="53" r="9" fill="#fff8c3" opacity="0.9"/>
      <path d="M31 65l-17 0M97 65l17 0M64 31V14M64 97v17" stroke="#f47e35" stroke-width="3" stroke-linecap="round"/>
    </g>`),

  "wizard.exploding_flame": svg(`
    <g filter="url(#glow)">
      <circle cx="64" cy="64" r="28" fill="url(#warmGlow)" opacity="0.5"/>
      <path d="M64 12l8 28 22-20-11 28 31-3-25 16 27 15-31-3 9 29-24-21-8 32-8-32-24 21 9-29-31 3 27-15-25-16 31 3-11-28 22 20z" fill="url(#ember)" stroke="#ffe28e" stroke-width="1.8" stroke-linejoin="round"/>
      <path d="M64 39Q78 49 78 64Q78 79 64 88Q50 79 50 64Q50 49 64 39z" fill="url(#crimson)" stroke="#fff0ad" stroke-width="2"/>
      <circle cx="64" cy="62" r="8" fill="#fffac8"/>
      <g fill="#ffb84c" stroke="#ef5728" stroke-width="1.2">
        <circle cx="34" cy="37" r="6"/><circle cx="94" cy="37" r="6"/><circle cx="34" cy="91" r="6"/><circle cx="94" cy="91" r="6"/>
        <circle cx="17" cy="63" r="5"/><circle cx="111" cy="63" r="5"/>
      </g>
    </g>`),

  "wizard.fire_wall": svg(`
    <g filter="url(#glow)">
      <path d="M19 98Q24 79 32 89Q36 49 44 84Q51 57 58 86Q65 40 72 85Q80 56 87 84Q94 49 101 88Q108 79 112 98" fill="none" stroke="url(#ember)" stroke-width="8" stroke-linecap="round"/>
      <path d="M18 101h19M42 105h18M68 101h19M91 105h20" stroke="#f4a344" stroke-width="5" stroke-linecap="round"/>
      <path d="M27 101Q32 85 37 101M51 105Q56 88 61 105M77 101Q82 85 87 101M101 105Q106 88 111 105" fill="none" stroke="#ffe99c" stroke-width="2.5"/>
      <path d="M25 93l-8-13M51 88l-6-17M76 88l6-17M101 93l8-13" stroke="#ef6a2d" stroke-width="3" stroke-linecap="round"/>
      <path d="M14 111h100" stroke="#74212a" stroke-width="3" stroke-linecap="round" opacity="0.9"/>
    </g>`),

  "wizard.laser": svg(`
    <g filter="url(#glow)">
      <path d="M13 64h102" stroke="#c9f9ff" stroke-width="9" stroke-linecap="round" opacity="0.32"/>
      <path d="M13 64h102" stroke="url(#ice)" stroke-width="4.5" stroke-linecap="round"/>
      <path d="M19 64h92" stroke="#ffffff" stroke-width="1.7" stroke-linecap="round"/>
      <circle cx="32" cy="64" r="17" fill="none" stroke="#ae9dff" stroke-width="3"/>
      <circle cx="61" cy="64" r="23" fill="none" stroke="#69d8ff" stroke-width="3"/>
      <circle cx="93" cy="64" r="15" fill="none" stroke="#c7a5ff" stroke-width="3"/>
      <path d="M32 42v11M32 75v11M61 34v12M61 82v12M93 45v9M93 74v9" stroke="#ffffff" stroke-width="2" stroke-linecap="round"/>
      <path d="M14 46l10 8M14 82l10-8M114 47l-10 7M114 81l-10-7" stroke="#8be9ff" stroke-width="3" stroke-linecap="round"/>
    </g>`),

  "wizard.hell_lightning": svg(`
    <g filter="url(#glow)">
      <circle cx="64" cy="64" r="47" fill="url(#violetGlow)" opacity="0.36"/>
      <path d="M64 16l7 28 23-17-16 24 31 1-29 10 22 23-27-14-2 35-10-32-23 24 14-28-31-1 29-10-23-23 28 14z" fill="none" stroke="url(#arcane)" stroke-width="3.5" stroke-linejoin="round"/>
      <path d="M64 27L52 56h13l-7 31 22-39H67z" fill="url(#ice)" stroke="#efffff" stroke-width="2"/>
      <path d="M26 31l8 12M102 31l-8 12M23 96l12-8M105 96L93 88" stroke="#ba9cff" stroke-width="4" stroke-linecap="round"/>
      <path d="M64 12v12M64 104v12M12 64h12M104 64h12" stroke="#69dfff" stroke-width="3" stroke-linecap="round"/>
      <circle cx="64" cy="61" r="6" fill="#ffffff"/>
    </g>`),

  "wizard.magic_shield": svg(`
    <g filter="url(#glow)">
      <path d="M64 13Q88 22 106 36v34Q99 99 64 115Q29 99 22 70V36Q40 22 64 13z" fill="url(#blueGlow)" opacity="0.5"/>
      <path d="M64 15Q87 23 104 37v31Q97 96 64 111Q31 96 24 68V37Q41 23 64 15z" fill="none" stroke="url(#arcane)" stroke-width="5"/>
      <path d="M64 27Q80 35 91 44v20Q85 84 64 96Q43 84 37 64V44Q48 35 64 27z" fill="none" stroke="#b7eaff" stroke-width="2.5" opacity="0.85"/>
      <path d="M64 34l10 15-10 10-10-10zM64 67l10 10-10 10-10-10z" fill="url(#violet)" stroke="#e8d9ff" stroke-width="1.5"/>
      <path d="M27 48l10-5M101 48l-10-5M31 80l11-4M97 80l-11-4" stroke="#6bdcff" stroke-width="3" stroke-linecap="round"/>
    </g>`),

  "wizard.holy_word": svg(`
    <g filter="url(#glow)">
      <path d="M64 11v54" stroke="#fffce3" stroke-width="9" stroke-linecap="round" opacity="0.38"/>
      <path d="M64 11v58" stroke="url(#gold)" stroke-width="4" stroke-linecap="round"/>
      <path d="M45 69Q48 56 64 53Q80 56 83 69L80 103Q64 113 48 103z" fill="#273150" stroke="#e4d8ff" stroke-width="2.3"/>
      <circle cx="55" cy="76" r="7" fill="#0c1731" stroke="#9bbcf0" stroke-width="2"/>
      <circle cx="73" cy="76" r="7" fill="#0c1731" stroke="#9bbcf0" stroke-width="2"/>
      <path d="M54 94Q64 101 74 94" fill="none" stroke="#90b2df" stroke-width="3" stroke-linecap="round"/>
      <path d="M42 82l-14 8M86 82l14 8M45 100l-12 10M83 100l12 10" stroke="#d9a94f" stroke-width="3" stroke-linecap="round"/>
      <path d="M49 25l15 16 15-16M64 41v15" fill="none" stroke="#fff5bc" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
    </g>`),

  "wizard.ice_storm": svg(`
    <g filter="url(#glow)">
      <circle cx="64" cy="64" r="35" fill="url(#blueGlow)" opacity="0.34"/>
      <path d="M64 14l8 33 28-21-20 29 34 9-35 3 20 29-28-21-7 35-7-35-28 21 20-29-35-3 34-9-20-29 28 21z" fill="none" stroke="url(#ice)" stroke-width="3" stroke-linejoin="round"/>
      <path d="M64 27l8 27 24 10-24 10-8 27-8-27-24-10 24-10z" fill="url(#ice)" stroke="#efffff" stroke-width="2"/>
      <path d="M31 30l8 15M97 30l-8 15M26 89l15-8M102 89L87 81" stroke="#9beaff" stroke-width="4" stroke-linecap="round"/>
      <path d="M22 65h15M106 65H91" stroke="#d4f8ff" stroke-width="2.5" stroke-linecap="round"/>
      <circle cx="64" cy="64" r="7" fill="#ffffff"/>
    </g>`),

  "taoist.healing": svg(`
    <g filter="url(#glow)">
      <circle cx="64" cy="64" r="47" fill="url(#jadeGlow)" opacity="0.3"/>
      <path d="M64 18Q39 22 35 46Q33 66 52 73Q72 80 83 64Q92 50 80 42Q69 35 58 44Q48 53 56 61Q64 68 71 61Q76 55 70 51" fill="none" stroke="url(#jade)" stroke-width="7" stroke-linecap="round"/>
      <path d="M64 34l17 15-5 28-12 16-12-16-5-28z" fill="url(#teal)" stroke="#c1f6d3" stroke-width="2"/>
      <path d="M64 45v31M53 60h22" stroke="#ecffb0" stroke-width="2.4" stroke-linecap="round" opacity="0.9"/>
      <path d="M31 38l-12-8M31 91l-12 8M97 38l12-8M97 91l12 8" stroke="#e2bd5a" stroke-width="3" stroke-linecap="round"/>
      <path d="M12 64l12-6M116 64l-12-6M64 12l-6 12M64 116l-6-12" stroke="#577066" stroke-width="2.4" stroke-linecap="square"/>
    </g>`),

  "taoist.spiritual_warfare": svg(`
    <g filter="url(#glow)">
      <circle cx="66" cy="62" r="45" fill="url(#jadeGlow)" opacity="0.26"/>
      <path d="M24 104L91 20l13 13-75 84z" fill="url(#teal)" stroke="#c9f4de" stroke-width="2"/>
      <path d="M35 94l60-67" stroke="#efffc9" stroke-width="2" opacity="0.7"/>
      <path d="M49 72l14 14M42 78l14 14" stroke="url(#gold)" stroke-width="6" stroke-linecap="round"/>
      <circle cx="72" cy="49" r="18" fill="none" stroke="#c8ed9c" stroke-width="2.5" stroke-dasharray="5 5"/>
      <path d="M72 25v13M72 60v13M48 49h13M83 49h13" stroke="#65dcc0" stroke-width="2.5" stroke-linecap="round"/>
      <path d="M17 36l8 8M105 90l8 8M23 109l7-10" stroke="#d9a74b" stroke-width="3" stroke-linecap="round"/>
    </g>`),

  "taoist.poison": svg(`
    <g filter="url(#glow)">
      <path d="M28 32Q18 40 25 51Q32 60 42 51Q49 42 41 33Q35 27 28 32z" fill="url(#jade)" stroke="#b8ffad" stroke-width="2"/>
      <path d="M83 73Q73 81 80 92Q87 101 97 92Q104 83 96 74Q90 68 83 73z" fill="url(#crimson)" stroke="#ffbf70" stroke-width="2"/>
      <path d="M39 50Q58 67 78 75" fill="none" stroke="#83df77" stroke-width="5" stroke-linecap="round"/>
      <path d="M43 70Q58 53 74 57" fill="none" stroke="#ef6632" stroke-width="4" stroke-linecap="round"/>
      <path d="M47 25L64 42 81 25M47 103l17-17 17 17" fill="none" stroke="#d2a64e" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M55 62l9-13 9 13-9 15z" fill="#173f42" stroke="#b2f093" stroke-width="2"/>
      <circle cx="64" cy="59" r="3" fill="#f7e69c"/>
      <path d="M15 17Q30 19 24 32Q18 43 31 48M113 111Q98 109 104 96Q110 85 97 80" fill="none" stroke="#79d86e" stroke-width="3.2" stroke-linecap="round"/>
      <path d="M113 17Q98 19 104 32Q110 43 97 48M15 111Q30 109 24 96Q18 85 31 80" fill="none" stroke="#e95f35" stroke-width="2.8" stroke-linecap="round"/>
    </g>`),

  "taoist.soul_fire_talisman": svg(`
    <g filter="url(#glow)">
      <path d="M64 13L91 34 86 90 64 115 42 90 37 34z" fill="url(#gold)" stroke="#fff0a9" stroke-width="2"/>
      <path d="M64 25L80 39 76 82 64 98 52 82 48 39z" fill="#15545a" stroke="#8df0cc" stroke-width="2" opacity="0.9"/>
      <path d="M64 34Q52 48 61 58Q51 55 49 67Q59 64 64 78Q69 64 79 67Q77 55 67 58Q76 48 64 34z" fill="url(#ember)" stroke="#ffe39b" stroke-width="1.6"/>
      <path d="M25 37l9 8M103 38l-9 8M25 91l10-7M103 91l-10-7" stroke="#69d6b4" stroke-width="3" stroke-linecap="round"/>
      <circle cx="64" cy="21" r="4" fill="#fff6ba"/><circle cx="64" cy="106" r="4" fill="#7ce5bf"/>
    </g>`),

  "taoist.summon_skeleton": svg(`
    <g filter="url(#glow)">
      <ellipse cx="64" cy="97" rx="44" ry="14" fill="none" stroke="url(#jade)" stroke-width="4"/>
      <ellipse cx="64" cy="97" rx="28" ry="8" fill="none" stroke="#e2bd62" stroke-width="2.5" stroke-dasharray="7 6"/>
      <path d="M64 96L52 66Q48 55 53 43Q57 35 63 44L64 61 67 39Q71 30 76 40Q78 49 73 64L68 96" fill="#d6e3d9" stroke="#5e756e" stroke-width="2"/>
      <path d="M52 66l-9-18M48 70l-14-9M76 67l11-18M80 71l15-10" stroke="#cfdfd3" stroke-width="7" stroke-linecap="round"/>
      <path d="M28 94l-11-16M100 94l11-16M38 106l-12 7M90 106l12 7" stroke="#59d1ae" stroke-width="3" stroke-linecap="round"/>
      <circle cx="64" cy="31" r="6" fill="url(#jade)" opacity="0.8"/>
    </g>`),

  "taoist.invisibility": svg(`
    <g filter="url(#glow)">
      <path d="M64 15Q42 25 38 48L31 96Q47 108 64 112Q81 108 97 96L90 48Q86 25 64 15z" fill="none" stroke="url(#teal)" stroke-width="5" stroke-linecap="round" stroke-dasharray="28 9 8 11" opacity="0.9"/>
      <path d="M49 34Q63 25 78 35M44 57Q64 44 84 58M39 80Q64 66 89 81" fill="none" stroke="#b2f5dc" stroke-width="3" stroke-linecap="round" stroke-dasharray="12 7" opacity="0.8"/>
      <path d="M31 40l-14-7M29 68l-16 0M34 94l-13 8M97 40l14-7M99 68l16 0M94 94l13 8" stroke="#5ed4c1" stroke-width="3" stroke-linecap="round"/>
      <path d="M56 17l8 8 8-8" fill="none" stroke="#f0d78e" stroke-width="2.5" stroke-linecap="round"/>
    </g>`),

  "taoist.mass_invisibility": svg(`
    <g filter="url(#glow)">
      <path d="M31 28Q19 45 25 89Q37 101 49 104L48 45Q43 32 31 28z" fill="none" stroke="#5dd2be" stroke-width="4" stroke-dasharray="18 7 8 9"/>
      <path d="M64 16Q48 31 47 51L45 99Q64 112 83 99L81 51Q80 31 64 16z" fill="none" stroke="url(#teal)" stroke-width="5" stroke-dasharray="23 8 11 10"/>
      <path d="M97 28Q109 45 103 89Q91 101 79 104L80 45Q85 32 97 28z" fill="none" stroke="#7ee5cf" stroke-width="4" stroke-dasharray="18 7 8 9"/>
      <path d="M18 57l10-4M110 57l-10-4M18 81l10 4M110 81l-10 4" stroke="#d4f3a2" stroke-width="3" stroke-linecap="round"/>
      <circle cx="64" cy="26" r="5" fill="#f2d884" opacity="0.9"/>
      <path d="M12 36l13 8M116 36l-13 8M12 95l13-8M116 95l-13-8" stroke="#344d4b" stroke-width="2.4" stroke-linecap="square"/>
    </g>`),

  "taoist.magic_defense": svg(`
    <g filter="url(#glow)">
      <circle cx="64" cy="64" r="45" fill="url(#jadeGlow)" opacity="0.3"/>
      <path d="M64 17Q96 23 106 54Q105 86 78 105Q64 113 50 105Q23 86 22 54Q32 23 64 17z" fill="none" stroke="url(#teal)" stroke-width="5"/>
      <path d="M46 41Q35 57 43 76Q50 91 64 94Q78 91 85 76Q93 57 82 41" fill="none" stroke="#b9f6e4" stroke-width="3" stroke-linecap="round" opacity="0.8"/>
      <path d="M64 29v69M35 64h58" stroke="#47cdbb" stroke-width="2" opacity="0.7"/>
      <path d="M64 37l8 15-8 8-8-8zM64 68l8 8-8 9-8-9z" fill="url(#jade)" stroke="#f0f5b0" stroke-width="1.4"/>
      <path d="M21 31l10 8M107 31l-10 8M21 97l11-8M107 97l-11-8" stroke="#53b9cc" stroke-width="3" stroke-linecap="round"/>
      <path d="M12 64h13M116 64h-13M64 12v13M64 116v-13" stroke="#405f5e" stroke-width="2.4" stroke-linecap="square"/>
    </g>`),

  "taoist.defense": svg(`
    <g filter="url(#glow)">
      <path d="M29 88Q26 61 36 39L50 24h28l14 15q10 22 7 49L84 105H44z" fill="url(#gold)" stroke="#fff0a5" stroke-width="2"/>
      <path d="M51 25L43 55l21 15 21-15-8-30" fill="#8e5d28" opacity="0.8" stroke="#ffe59b" stroke-width="2"/>
      <path d="M64 33v36M48 51h32" stroke="#fff4c0" stroke-width="3" stroke-linecap="round"/>
      <path d="M19 63Q13 47 22 34M109 63Q115 47 106 34M27 103Q17 91 21 78M101 103Q111 91 107 78" fill="none" stroke="#d4a944" stroke-width="4" stroke-linecap="round"/>
      <path d="M38 98l-15 8M90 98l15 8" stroke="#55cfac" stroke-width="3" stroke-linecap="round"/>
      <path d="M12 56l9-12M116 56l-9-12M12 78l9 12M116 78l-9 12" stroke="#6f5734" stroke-width="2.4" stroke-linecap="square"/>
    </g>`),

  "taoist.revelation": svg(`
    <g filter="url(#glow)">
      <ellipse cx="64" cy="64" rx="45" ry="29" fill="url(#jadeGlow)" opacity="0.3"/>
      <path d="M17 64Q38 32 64 32Q90 32 111 64Q90 96 64 96Q38 96 17 64z" fill="none" stroke="url(#jade)" stroke-width="5"/>
      <path d="M36 64Q49 45 64 45Q79 45 92 64Q79 83 64 83Q49 83 36 64z" fill="#123d43" stroke="#b9f3bd" stroke-width="2.4"/>
      <ellipse cx="64" cy="64" rx="8" ry="14" fill="url(#gold)"/><circle cx="64" cy="60" r="3.5" fill="#fffbd0"/>
      <path d="M64 15v13M64 100v13M22 28l9 10M106 28l-9 10M22 100l9-10M106 100l-9-10" stroke="#6bdac0" stroke-width="3" stroke-linecap="round"/>
      <path d="M43 106Q64 114 85 106" fill="none" stroke="#efcc68" stroke-width="3" stroke-linecap="round"/>
    </g>`),

  "taoist.entrapment": svg(`
    <g filter="url(#glow)">
      <circle cx="64" cy="66" r="45" fill="none" stroke="url(#gold)" stroke-width="4" stroke-dasharray="11 7"/>
      <circle cx="64" cy="66" r="31" fill="url(#jadeGlow)" opacity="0.35"/>
      <path d="M64 99Q55 83 57 70Q47 77 40 67Q51 65 58 57Q51 50 58 42Q64 52 70 42Q77 50 70 57Q77 65 88 67Q81 77 71 70Q73 83 64 99z" fill="url(#teal)" stroke="#c5f4bf" stroke-width="2"/>
      <path d="M37 47l17 12M91 47L74 59M35 85l20-10M93 85L73 75" stroke="#d2a94d" stroke-width="4" stroke-linecap="round"/>
      <path d="M64 14v15M64 103v15M12 66h15M101 66h15" stroke="#6bd8ad" stroke-width="3" stroke-linecap="round"/>
    </g>`),

  "taoist.mass_healing": svg(`
    <g filter="url(#glow)">
      <path d="M64 19L83 54 64 89 45 54z" fill="none" stroke="#9cefc4" stroke-width="2.5" opacity="0.8"/>
      <circle cx="64" cy="34" r="18" fill="url(#jade)" stroke="#efffb1" stroke-width="2"/>
      <circle cx="36" cy="86" r="18" fill="url(#teal)" stroke="#b9f5db" stroke-width="2"/>
      <circle cx="92" cy="86" r="18" fill="url(#jade)" stroke="#f2d788" stroke-width="2"/>
      <path d="M64 24v20M56 34h16M36 76v20M28 86h16M92 76v20M84 86h16" stroke="#ffffff" stroke-width="2.3" stroke-linecap="round" opacity="0.9"/>
      <path d="M19 53Q12 64 19 75M109 53Q116 64 109 75" fill="none" stroke="#55d0b1" stroke-width="4" stroke-linecap="round"/>
      <path d="M33 23l7 7M95 23l-7 7" stroke="#e4c766" stroke-width="3" stroke-linecap="round"/>
    </g>`),

  "taoist.summon_divine_beast": svg(`
    <g filter="url(#glow)">
      <ellipse cx="64" cy="101" rx="45" ry="12" fill="none" stroke="url(#gold)" stroke-width="4"/>
      <path d="M64 88Q48 81 38 87Q31 77 35 63Q39 48 52 47L43 32Q56 33 64 42Q72 33 85 32L76 47Q89 48 93 63Q97 77 90 87Q80 81 64 88z" fill="url(#ember)" stroke="#ffe59e" stroke-width="2"/>
      <path d="M44 60Q34 53 25 58M84 60Q94 53 103 58" fill="none" stroke="#ffbe5b" stroke-width="6" stroke-linecap="round"/>
      <path d="M49 65Q55 58 64 65Q73 58 79 65Q74 78 64 82Q54 78 49 65z" fill="#7b202d" stroke="#ffca6e" stroke-width="2"/>
      <circle cx="55" cy="64" r="3" fill="#fff5ad"/><circle cx="73" cy="64" r="3" fill="#fff5ad"/>
      <path d="M64 12v19M28 22l12 13M100 22L88 35" stroke="#8ce9b0" stroke-width="3" stroke-linecap="round"/>
      <path d="M42 105l-13 8M86 105l13 8" stroke="#52d0ad" stroke-width="3" stroke-linecap="round"/>
    </g>`),
};

function fail(message) {
  throw new Error(`[skill-icon-generator] ${message}`);
}

function assertExpectedIds(actualIds, expectedIds, label) {
  const actual = [...actualIds].sort();
  const expected = [...expectedIds].sort();
  if (actual.length !== expected.length || actual.some((id, index) => id !== expected[index])) {
    const missing = expected.filter((id) => !actual.includes(id));
    const extra = actual.filter((id) => !expected.includes(id));
    fail(`${label} mismatch; missing=${missing.join(",") || "none"}; extra=${extra.join(",") || "none"}`);
  }
}

function alphaStats(raw, width, height) {
  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;
  let visiblePixels = 0;
  let partialPixels = 0;
  let opaquePixels = 0;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const alpha = raw[(y * width + x) * 4 + 3];
      if (alpha > 0) {
        visiblePixels += 1;
        minX = Math.min(minX, x);
        minY = Math.min(minY, y);
        maxX = Math.max(maxX, x);
        maxY = Math.max(maxY, y);
      }
      if (alpha > 0 && alpha < 255) partialPixels += 1;
      if (alpha === 255) opaquePixels += 1;
    }
  }
  return { minX, minY, maxX, maxY, visiblePixels, partialPixels, opaquePixels };
}

async function validatePng(buffer, label) {
  const image = sharp(buffer);
  const metadata = await image.metadata();
  if (metadata.format !== "png") fail(`${label} did not rasterize to PNG`);
  if (metadata.width !== NATIVE_CANVAS || metadata.height !== NATIVE_CANVAS) {
    fail(`${label} has dimensions ${metadata.width}x${metadata.height}, expected 128x128`);
  }
  if (metadata.channels !== 4) fail(`${label} is not RGBA (channels=${metadata.channels})`);
  const { data, info } = await image.ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  if (info.width !== NATIVE_CANVAS || info.height !== NATIVE_CANVAS || info.channels !== 4) {
    fail(`${label} raw raster contract failed: ${info.width}x${info.height}x${info.channels}`);
  }
  const stats = alphaStats(data, info.width, info.height);
  const corners = [
    data[3],
    data[(NATIVE_CANVAS - 1) * 4 + 3],
    data[((NATIVE_CANVAS - 1) * NATIVE_CANVAS) * 4 + 3],
    data[((NATIVE_CANVAS * NATIVE_CANVAS) - 1) * 4 + 3],
  ];
  if (corners.some((alpha) => alpha !== 0)) fail(`${label} corner alpha is not zero: ${corners.join(",")}`);
  if (stats.visiblePixels === 0) fail(`${label} has no visible pixels`);
  if (stats.partialPixels === 0) fail(`${label} has no antialiased/partial alpha pixels`);
  if (stats.opaquePixels === 0) fail(`${label} has no opaque pixels`);
  if (stats.minX <= 0 || stats.minY <= 0 || stats.maxX >= NATIVE_CANVAS - 1 || stats.maxY >= NATIVE_CANVAS - 1) {
    fail(`${label} visible bbox touches canvas edge: ${JSON.stringify(stats)}`);
  }
  const bboxWidth = stats.maxX - stats.minX + 1;
  const bboxHeight = stats.maxY - stats.minY + 1;
  const majorAxis = Math.max(bboxWidth, bboxHeight);
  const minorAxis = Math.min(bboxWidth, bboxHeight);
  if (majorAxis < 100 || minorAxis < 60) {
    fail(`${label} visible bbox too small (${bboxWidth}x${bboxHeight}); expected a readable 78-84% mark`);
  }
  return { width: metadata.width, height: metadata.height, alpha: stats };
}

function sha256(buffer) {
  return crypto.createHash("sha256").update(buffer).digest("hex");
}

async function readSkillRecords() {
  let parsed;
  try {
    parsed = JSON.parse(await fs.readFile(SKILLS_PATH, "utf8"));
  } catch (error) {
    fail(`cannot parse ${path.relative(ROOT, SKILLS_PATH)}: ${error.message}`);
  }
  if (!parsed || !Array.isArray(parsed.records)) fail("skills.json.records must be an array");
  const unique = new Map();
  for (const record of parsed.records) {
    const skillId = typeof record?.skill_id === "string" ? record.skill_id : "";
    if (!skillId) fail("skills.json contains a record without string skill_id");
    const displayName = typeof record.display_name === "string" ? record.display_name.trim() : "";
    const description = typeof record.description === "string" ? record.description.trim() : "";
    if (!displayName || !description) fail(`${skillId} is missing display_name or description`);
    if (!unique.has(skillId)) unique.set(skillId, { skill_id: skillId, display_name: displayName, description });
  }
  if (unique.size !== EXPECTED_SKILL_IDS.length) fail(`skills.json has ${unique.size} unique skill_id values; expected 33`);
  assertExpectedIds(unique.keys(), EXPECTED_SKILL_IDS, "skills.json unique skill_id");
  return unique;
}

async function renderIcons(skills) {
  assertExpectedIds(Object.keys(ICONS), EXPECTED_SKILL_IDS, "icon mapping");
  const rendered = [];
  for (const skillId of EXPECTED_SKILL_IDS) {
    const svgSource = ICONS[skillId];
    if (typeof svgSource !== "string" || !svgSource.startsWith("<svg")) fail(`${skillId} has no SVG mapping`);
    if (!svgSource.includes('width="128"') || !svgSource.includes('height="128"') || !svgSource.includes('viewBox="0 0 128 128"')) {
      fail(`${skillId} SVG is not authored on the native 128x128 canvas`);
    }
    // sharp/librsvg rasterizes this exact SVG canvas directly; no resize is called.
    const pngBuffer = await sharp(Buffer.from(svgSource, "utf8"), { density: 72 }).png({ compressionLevel: 9 }).toBuffer();
    const validation = await validatePng(pngBuffer, skillId);
    rendered.push({ skillId, pngBuffer, validation, filename: `${skillId.replaceAll(".", "_")}.png` });
  }
  return rendered;
}

async function writeOutputs(skills, rendered) {
  await fs.mkdir(OUTPUT_DIR, { recursive: true });
  const manifest = {
    schema_version: 1,
    generation_policy: GENERATION_POLICY,
    native_canvas: NATIVE_CANVAS,
    source: "assets/data/vanilla_176/skills.json",
    output_root: "res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2",
    icons: [],
  };
  for (const item of rendered) {
    const skill = skills.get(item.skillId);
    const output = `res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2/${item.filename}`;
    await fs.writeFile(path.join(OUTPUT_DIR, item.filename), item.pngBuffer);
    manifest.icons.push({
      skill_id: item.skillId,
      display_name: skill.display_name,
      description: skill.description,
      output,
      sha256: sha256(item.pngBuffer),
      width: item.validation.width,
      height: item.validation.height,
      native_canvas: NATIVE_CANVAS,
    });
  }
  if (manifest.icons.length !== EXPECTED_SKILL_IDS.length) fail(`manifest has ${manifest.icons.length} icons; expected 33`);
  await fs.writeFile(MANIFEST_PATH, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
  return manifest;
}

async function writeContactSheet(rendered) {
  const columns = 6;
  const tile = 156;
  const rows = Math.ceil(rendered.length / columns);
  const composites = rendered.map((item, index) => ({
    input: item.pngBuffer,
    left: (index % columns) * tile + 14,
    top: Math.floor(index / columns) * tile + 14,
  }));
  const sheet = sharp({
    create: {
      width: columns * tile,
      height: rows * tile,
      channels: 4,
      background: { r: 10, g: 14, b: 28, alpha: 1 },
    },
  }).composite(composites);
  await fs.mkdir(REVIEW_DIR, { recursive: true });
  await sheet.png({ compressionLevel: 9 }).toFile(path.join(REVIEW_DIR, "contact_sheet.png"));
}

async function main() {
  const skills = await readSkillRecords();
  const rendered = await renderIcons(skills);
  const manifest = await writeOutputs(skills, rendered);
  if (process.argv.includes("--contact-sheet")) await writeContactSheet(rendered);
  console.log(`SKILL_ICON_GENERATION_PASS count=${manifest.icons.length} output=${path.relative(ROOT, OUTPUT_DIR)}`);
  console.log(`generation_policy=${GENERATION_POLICY} native_canvas=${NATIVE_CANVAS}x${NATIVE_CANVAS}`);
}

main().catch((error) => {
  console.error(error?.stack || error);
  process.exitCode = 1;
});
