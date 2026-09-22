#!/usr/bin/env node

/**
 * Deterministically import the five user-approved skill-icon sheets.
 *
 * The source sheets are treated as fixed raster input.  This tool never calls
 * an image-generation/editing model and never writes Godot .import files: it
 * only writes the 33 generated_v2 PNGs and their manifest after every output
 * has passed the final 128x128 RGBA contract.
 */

import crypto from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
let sharp;
try {
  sharp = require("sharp");
} catch (error) {
  throw new Error(
    "sharp is required. Install it in the active Node environment or provide NODE_PATH to a sharp installation. " +
      `Original error: ${error.message}`,
  );
}

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
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
const SKILLS_PATH = path.join(ROOT, "assets", "data", "vanilla_176", "skills.json");

const NATIVE_CANVAS = 128;
const MAX_CONTENT_SIZE = 118;
const ALPHA_THRESHOLD = 8;
const OUTPUT_ROOT = "res://assets/ui/gothic_hud/v2/runtime/skill_icons/generated_v2";
const SOURCE_ROOT = process.env.SKILL_ICON_SOURCE_ROOT || path.join(os.homedir(), "Downloads");

const SHEETS = [
  {
    id: "A",
    file: "ChatGPT Image 2026年9月4日 00_08_15 (4).png",
    columns: 3,
    rows: 3,
    expectedWidth: 1254,
    expectedHeight: 1254,
    skills: [
      "taoist.healing",
      "taoist.spiritual_warfare",
      "taoist.poison",
      "taoist.soul_fire_talisman",
      "taoist.summon_skeleton",
      "taoist.invisibility",
      "taoist.mass_invisibility",
      "taoist.magic_defense",
      "taoist.defense",
    ],
  },
  {
    id: "B",
    file: "ChatGPT Image 2026年9月4日 00_08_13 (1).png",
    columns: 3,
    rows: 2,
    expectedWidth: 1536,
    expectedHeight: 1024,
    skills: [
      "warrior.basic_swordsmanship",
      "warrior.slaying_swordsmanship",
      "warrior.thrusting",
      "warrior.half_moon",
      "warrior.wild_rush",
      "warrior.fire_sword",
    ],
  },
  {
    id: "C",
    file: "ChatGPT Image 2026年9月4日 00_08_13 (2).png",
    columns: 3,
    rows: 3,
    expectedWidth: 1254,
    expectedHeight: 1254,
    skills: [
      "wizard.fireball",
      "wizard.repulsion_ring",
      "wizard.temptation_light",
      "wizard.hellfire",
      "wizard.lightning",
      "wizard.teleport",
      "wizard.great_fireball",
      "wizard.exploding_flame",
      "wizard.fire_wall",
    ],
  },
  {
    id: "D",
    file: "ChatGPT Image 2026年9月4日 00_08_15 (5).png",
    columns: 2,
    rows: 2,
    expectedWidth: 1254,
    expectedHeight: 1254,
    skills: [
      "taoist.revelation",
      "taoist.entrapment",
      "taoist.mass_healing",
      "taoist.summon_divine_beast",
    ],
  },
  {
    id: "E",
    file: "ChatGPT Image 2026年9月4日 00_08_14 (3).png",
    columns: 3,
    rows: 2,
    expectedWidth: 1536,
    expectedHeight: 1024,
    skills: [
      "wizard.laser",
      "wizard.hell_lightning",
      "wizard.magic_shield",
      "wizard.holy_word",
      "wizard.ice_storm",
      null,
    ],
  },
];

const EXPECTED_SKILL_IDS = SHEETS.flatMap((sheet) => sheet.skills).filter(Boolean);

function fail(message) {
  throw new Error(`[approved-skill-icon-import] ${message}`);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function toPosix(value) {
  return value.replaceAll("\\", "/");
}

function sha256(buffer) {
  return crypto.createHash("sha256").update(buffer).digest("hex");
}

function filenameFor(skillId) {
  return `${skillId.replaceAll(".", "_")}.png`;
}

function outputPathFor(skillId) {
  return path.join(OUTPUT_DIR, filenameFor(skillId));
}

function resourcePathFor(skillId) {
  return `${OUTPUT_ROOT}/${filenameFor(skillId)}`;
}

function cleanAlpha(raw) {
  const cleaned = Buffer.from(raw);
  let cleared = 0;
  for (let index = 0; index < cleaned.length; index += 4) {
    if (cleaned[index + 3] <= ALPHA_THRESHOLD) {
      // Clear RGB as well so transparent pixels cannot bleed colour through
      // the Lanczos kernel when the visible bbox is resized.
      cleaned[index] = 0;
      cleaned[index + 1] = 0;
      cleaned[index + 2] = 0;
      cleaned[index + 3] = 0;
      cleared += 1;
    }
  }
  return { buffer: cleaned, cleared };
}

function sideNames(touches) {
  const names = [];
  if (touches.top) names.push("top");
  if (touches.right) names.push("right");
  if (touches.bottom) names.push("bottom");
  if (touches.left) names.push("left");
  return names;
}

function connectedComponents(raw, width, height) {
  const visited = new Uint8Array(width * height);
  const queue = new Int32Array(width * height);
  const components = [];

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const start = y * width + x;
      if (visited[start] || raw[start * 4 + 3] <= ALPHA_THRESHOLD) continue;

      let head = 0;
      let tail = 0;
      queue[tail] = start;
      tail += 1;
      visited[start] = 1;
      let pixels = 0;
      let partialPixels = 0;
      let opaquePixels = 0;
      let minX = width;
      let minY = height;
      let maxX = -1;
      let maxY = -1;
      const touches = { top: false, right: false, bottom: false, left: false };

      while (head < tail) {
        const index = queue[head];
        head += 1;
        const currentX = index % width;
        const currentY = Math.floor(index / width);
        const alpha = raw[index * 4 + 3];
        pixels += 1;
        if (alpha < 255) partialPixels += 1;
        if (alpha === 255) opaquePixels += 1;
        minX = Math.min(minX, currentX);
        minY = Math.min(minY, currentY);
        maxX = Math.max(maxX, currentX);
        maxY = Math.max(maxY, currentY);
        if (currentY === 0) touches.top = true;
        if (currentX === width - 1) touches.right = true;
        if (currentY === height - 1) touches.bottom = true;
        if (currentX === 0) touches.left = true;

        for (let deltaY = -1; deltaY <= 1; deltaY += 1) {
          for (let deltaX = -1; deltaX <= 1; deltaX += 1) {
            if (deltaX === 0 && deltaY === 0) continue;
            const nextX = currentX + deltaX;
            const nextY = currentY + deltaY;
            if (nextX < 0 || nextY < 0 || nextX >= width || nextY >= height) continue;
            const next = nextY * width + nextX;
            if (visited[next] || raw[next * 4 + 3] <= ALPHA_THRESHOLD) continue;
            visited[next] = 1;
            queue[tail] = next;
            tail += 1;
          }
        }
      }

      components.push({
        pixels,
        partialPixels,
        opaquePixels,
        bbox: [minX, minY, maxX, maxY],
        bboxSize: [maxX - minX + 1, maxY - minY + 1],
        touches: sideNames(touches),
      });
    }
  }

  components.sort((left, right) => right.pixels - left.pixels);
  return components;
}

function alphaStats(raw, width, height, includeComponents = true) {
  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;
  let visiblePixels = 0;
  let partialPixels = 0;
  let opaquePixels = 0;
  let minAlpha = 255;
  let maxAlpha = 0;
  const touches = { top: false, right: false, bottom: false, left: false };

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const alpha = raw[(y * width + x) * 4 + 3];
      if (alpha <= ALPHA_THRESHOLD) continue;
      visiblePixels += 1;
      minX = Math.min(minX, x);
      minY = Math.min(minY, y);
      maxX = Math.max(maxX, x);
      maxY = Math.max(maxY, y);
      minAlpha = Math.min(minAlpha, alpha);
      maxAlpha = Math.max(maxAlpha, alpha);
      if (alpha < 255) partialPixels += 1;
      if (alpha === 255) opaquePixels += 1;
      if (y === 0) touches.top = true;
      if (x === width - 1) touches.right = true;
      if (y === height - 1) touches.bottom = true;
      if (x === 0) touches.left = true;
    }
  }

  const bbox = visiblePixels === 0 ? null : [minX, minY, maxX, maxY];
  const bboxSize = visiblePixels === 0 ? [0, 0] : [maxX - minX + 1, maxY - minY + 1];
  const components = includeComponents ? connectedComponents(raw, width, height) : [];
  const edgeComponents = components.filter((component) => component.touches.length > 0);

  return {
    visiblePixels,
    partialPixels,
    opaquePixels,
    minAlpha: visiblePixels === 0 ? null : minAlpha,
    maxAlpha: visiblePixels === 0 ? null : maxAlpha,
    bbox,
    bboxSize,
    touches: sideNames(touches),
    componentCount: components.length,
    edgeComponentCount: edgeComponents.length,
    largestComponentPixels: components[0]?.pixels ?? 0,
    components,
  };
}

function compactComponent(component) {
  return {
    pixels: component.pixels,
    partialPixels: component.partialPixels,
    opaquePixels: component.opaquePixels,
    bbox: component.bbox,
    bboxSize: component.bboxSize,
    touches: component.touches,
  };
}

function sourcePathFor(sheet) {
  return path.join(SOURCE_ROOT, sheet.file);
}

async function readAndValidateSheet(sheet) {
  const sourcePath = sourcePathFor(sheet);
  let fileBytes;
  try {
    fileBytes = await fs.readFile(sourcePath);
  } catch (error) {
    fail(`source sheet ${sheet.id} is unreadable at ${sourcePath}: ${error.message}`);
  }

  const metadata = await sharp(fileBytes).metadata();
  assert(metadata.format === "png", `source sheet ${sheet.id} is not PNG: ${metadata.format}`);
  assert(metadata.hasAlpha && metadata.channels === 4, `source sheet ${sheet.id} must be true RGBA`);
  assert(
    metadata.width === sheet.expectedWidth && metadata.height === sheet.expectedHeight,
    `source sheet ${sheet.id} dimensions ${metadata.width}x${metadata.height} do not match expected ${sheet.expectedWidth}x${sheet.expectedHeight}`,
  );
  assert(metadata.width % sheet.columns === 0, `source sheet ${sheet.id} width is not divisible by ${sheet.columns}`);
  assert(metadata.height % sheet.rows === 0, `source sheet ${sheet.id} height is not divisible by ${sheet.rows}`);

  const rawResult = await sharp(fileBytes).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  assert(rawResult.info.channels === 4, `source sheet ${sheet.id} raw channel count is ${rawResult.info.channels}`);
  return {
    id: sheet.id,
    file: sheet.file,
    path: sourcePath,
    bytes: fileBytes,
    sha256: sha256(fileBytes),
    width: rawResult.info.width,
    height: rawResult.info.height,
    channels: rawResult.info.channels,
    cellWidth: rawResult.info.width / sheet.columns,
    cellHeight: rawResult.info.height / sheet.rows,
    raw: rawResult.data,
  };
}

function cellRaw(sheet, source, column, row) {
  const raw = Buffer.alloc(sheet.cellWidth * sheet.cellHeight * 4);
  for (let y = 0; y < sheet.cellHeight; y += 1) {
    const sourceStart = ((row * sheet.cellHeight + y) * source.width + column * sheet.cellWidth) * 4;
    const targetStart = y * sheet.cellWidth * 4;
    source.raw.copy(raw, targetStart, sourceStart, sourceStart + sheet.cellWidth * 4);
  }
  return raw;
}

function regionFor(sheet, column, row) {
  return [column * sheet.cellWidth, row * sheet.cellHeight, sheet.cellWidth, sheet.cellHeight];
}

function adjacentSharedEdges(sheet, cellStats) {
  const byGrid = new Map(cellStats.map((cell) => [`${cell.column},${cell.row}`, cell]));
  const pairs = [];
  for (const cell of cellStats) {
    const right = byGrid.get(`${cell.column + 1},${cell.row}`);
    if (right && cell.stats.touches.includes("right") && right.stats.touches.includes("left")) {
      pairs.push({ axis: "vertical", first: [cell.column, cell.row], second: [right.column, right.row] });
    }
    const bottom = byGrid.get(`${cell.column},${cell.row + 1}`);
    if (bottom && cell.stats.touches.includes("bottom") && bottom.stats.touches.includes("top")) {
      pairs.push({ axis: "horizontal", first: [cell.column, cell.row], second: [bottom.column, bottom.row] });
    }
  }
  return pairs;
}

function sharedEdgesForCell(cell, sharedEdges) {
  return sharedEdges
    .filter(
      (pair) =>
        (pair.first[0] === cell.column && pair.first[1] === cell.row) ||
        (pair.second[0] === cell.column && pair.second[1] === cell.row),
    )
    .map((pair) => ({ axis: pair.axis, first: pair.first, second: pair.second }));
}

async function makeFinalIcon(cleanedCellRaw, cellWidth, cellHeight, bbox) {
  const [minX, minY, maxX, maxY] = bbox;
  const croppedWidth = maxX - minX + 1;
  const croppedHeight = maxY - minY + 1;
  const cropped = await sharp(cleanedCellRaw, {
    raw: { width: cellWidth, height: cellHeight, channels: 4 },
  })
    .extract({ left: minX, top: minY, width: croppedWidth, height: croppedHeight })
    .resize({
      width: MAX_CONTENT_SIZE,
      height: MAX_CONTENT_SIZE,
      fit: "inside",
      withoutEnlargement: true,
      kernel: sharp.kernel.lanczos3,
    })
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toBuffer();

  const resizedMetadata = await sharp(cropped).metadata();
  assert(resizedMetadata.width && resizedMetadata.height, "resized subject has no dimensions");
  assert(
    resizedMetadata.width <= MAX_CONTENT_SIZE && resizedMetadata.height <= MAX_CONTENT_SIZE,
    `resized subject is ${resizedMetadata.width}x${resizedMetadata.height}, over ${MAX_CONTENT_SIZE}x${MAX_CONTENT_SIZE}`,
  );

  const left = Math.floor((NATIVE_CANVAS - resizedMetadata.width) / 2);
  const top = Math.floor((NATIVE_CANVAS - resizedMetadata.height) / 2);
  const right = NATIVE_CANVAS - resizedMetadata.width - left;
  const bottom = NATIVE_CANVAS - resizedMetadata.height - top;
  const composed = await sharp(cropped)
    .extend({
      top,
      bottom,
      left,
      right,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toBuffer();

  const finalRawResult = await sharp(composed).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  assert(finalRawResult.info.channels === 4, "composed icon is not RGBA before final cleanup");
  const finalCleaned = cleanAlpha(finalRawResult.data);
  const finalPng = await sharp(finalCleaned.buffer, {
    raw: {
      width: finalRawResult.info.width,
      height: finalRawResult.info.height,
      channels: finalRawResult.info.channels,
    },
  })
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toBuffer();

  return {
    buffer: finalPng,
    resizedSize: [resizedMetadata.width, resizedMetadata.height],
    finalClearedNearTransparentPixels: finalCleaned.cleared,
  };
}

async function validateFinalIcon(buffer, skillId) {
  const metadata = await sharp(buffer).metadata();
  assert(metadata.format === "png", `${skillId} final format is ${metadata.format}`);
  assert(
    metadata.width === NATIVE_CANVAS && metadata.height === NATIVE_CANVAS,
    `${skillId} final dimensions are ${metadata.width}x${metadata.height}, expected 128x128`,
  );
  assert(metadata.hasAlpha && metadata.channels === 4, `${skillId} final PNG is not RGBA`);

  const rawResult = await sharp(buffer).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  assert(
    rawResult.info.width === NATIVE_CANVAS && rawResult.info.height === NATIVE_CANVAS && rawResult.info.channels === 4,
    `${skillId} final raw contract failed: ${rawResult.info.width}x${rawResult.info.height}x${rawResult.info.channels}`,
  );
  const raw = rawResult.data;
  const corners = [
    raw[3],
    raw[(NATIVE_CANVAS - 1) * 4 + 3],
    raw[((NATIVE_CANVAS - 1) * NATIVE_CANVAS) * 4 + 3],
    raw[(NATIVE_CANVAS * NATIVE_CANVAS - 1) * 4 + 3],
  ];
  assert(corners.every((alpha) => alpha === 0), `${skillId} corner alpha values are ${corners.join(",")}`);

  let residualNearTransparent = 0;
  for (let index = 3; index < raw.length; index += 4) {
    if (raw[index] > 0 && raw[index] <= ALPHA_THRESHOLD) residualNearTransparent += 1;
  }
  assert(residualNearTransparent === 0, `${skillId} retains ${residualNearTransparent} alpha<=${ALPHA_THRESHOLD} pixels`);

  const stats = alphaStats(raw, NATIVE_CANVAS, NATIVE_CANVAS, false);
  assert(stats.visiblePixels > 0, `${skillId} final icon is empty`);
  assert(stats.partialPixels > 0, `${skillId} final icon has no partial alpha edge pixels`);
  assert(stats.bbox, `${skillId} final icon has no visible bbox`);
  assert(stats.bboxSize[0] <= MAX_CONTENT_SIZE && stats.bboxSize[1] <= MAX_CONTENT_SIZE, `${skillId} final visible bbox exceeds ${MAX_CONTENT_SIZE}`);
  assert(stats.bbox[0] > 0 && stats.bbox[1] > 0 && stats.bbox[2] < NATIVE_CANVAS - 1 && stats.bbox[3] < NATIVE_CANVAS - 1, `${skillId} final visible bbox touches canvas edge`);
  return {
    width: metadata.width,
    height: metadata.height,
    channels: metadata.channels,
    hasAlpha: metadata.hasAlpha,
    sha256: sha256(buffer),
    alpha: stats,
  };
}

async function readSkillRecords() {
  let document;
  try {
    document = JSON.parse(await fs.readFile(SKILLS_PATH, "utf8"));
  } catch (error) {
    fail(`cannot parse ${toPosix(path.relative(ROOT, SKILLS_PATH))}: ${error.message}`);
  }
  assert(document && Array.isArray(document.records), "skills.json.records must be an array");
  const records = new Map();
  for (const record of document.records) {
    const skillId = typeof record?.skill_id === "string" ? record.skill_id : "";
    if (!skillId || records.has(skillId)) continue;
    const displayName = typeof record.display_name === "string" ? record.display_name.trim() : "";
    const description = typeof record.description === "string" ? record.description.trim() : "";
    assert(displayName && description, `${skillId} is missing display_name or description`);
    records.set(skillId, { skill_id: skillId, display_name: displayName, description });
  }
  const actualIds = [...records.keys()].sort();
  const expectedIds = [...EXPECTED_SKILL_IDS].sort();
  assert(actualIds.length === expectedIds.length && actualIds.every((id, index) => id === expectedIds[index]), `skills.json catalog mismatch; actual=${actualIds.join(",")}; expected=${expectedIds.join(",")}`);
  return records;
}

async function existingOutputPngNames() {
  let entries = [];
  try {
    entries = await fs.readdir(OUTPUT_DIR, { withFileTypes: true });
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
  return entries.filter((entry) => entry.isFile() && entry.name.toLowerCase().endsWith(".png")).map((entry) => entry.name).sort();
}

async function main() {
  assert(EXPECTED_SKILL_IDS.length === 33, `embedded mapping has ${EXPECTED_SKILL_IDS.length} skill IDs, expected 33`);
  assert(new Set(EXPECTED_SKILL_IDS).size === EXPECTED_SKILL_IDS.length, "embedded mapping contains duplicate skill IDs");

  const skills = await readSkillRecords();
  const sources = [];
  for (const sheet of SHEETS) sources.push(await readAndValidateSheet(sheet));

  const existingPngNames = await existingOutputPngNames();
  const expectedPngNames = EXPECTED_SKILL_IDS.map(filenameFor).sort();
  const unexpectedExisting = existingPngNames.filter((name) => !expectedPngNames.includes(name));
  if (unexpectedExisting.length > 0) {
    fail(`generated_v2 contains unexpected PNG files; refusing to delete or overwrite them: ${unexpectedExisting.join(",")}`);
  }

  const allIcons = [];
  const sheetReports = [];
  for (let sourceIndex = 0; sourceIndex < SHEETS.length; sourceIndex += 1) {
    const sheet = SHEETS[sourceIndex];
    const source = sources[sourceIndex];
    const cellReports = [];

    for (let row = 0; row < sheet.rows; row += 1) {
      for (let column = 0; column < sheet.columns; column += 1) {
        const index = row * sheet.columns + column;
        const skillId = sheet.skills[index];
        const region = regionFor(source, column, row);
        const originalCellRaw = cellRaw(source, source, column, row);
        const cleanedCell = cleanAlpha(originalCellRaw);
        const stats = alphaStats(cleanedCell.buffer, source.cellWidth, source.cellHeight, true);
        const cell = { column, row, index, skillId, region, stats, cleanedCell };
        cellReports.push(cell);

        if (!skillId) {
          assert(stats.visiblePixels === 0, `unused ${sheet.id}[${column},${row}] contains ${stats.visiblePixels} visible pixels`);
          continue;
        }
        assert(stats.visiblePixels > 0, `${skillId} at ${sheet.id}[${column},${row}] is empty`);
        assert(stats.bbox, `${skillId} at ${sheet.id}[${column},${row}] has no bbox`);
      }
    }

    const sharedEdges = adjacentSharedEdges(sheet, cellReports);
    for (const cell of cellReports) {
      if (!cell.skillId) continue;
      const sourceStats = cell.stats;
      const edgeComponents = sourceStats.components.filter((component) => component.touches.length > 0);
      const sharedGridEdges = sharedEdgesForCell(cell, sharedEdges);
      const finalIcon = await makeFinalIcon(
        cell.cleanedCell.buffer,
        source.cellWidth,
        source.cellHeight,
        sourceStats.bbox,
      );
      const finalValidation = await validateFinalIcon(finalIcon.buffer, cell.skillId);
      const edgeRisk = edgeComponents.length > 0 || sharedGridEdges.length > 0;
      const entry = {
        skill_id: cell.skillId,
        display_name: skills.get(cell.skillId).display_name,
        output: resourcePathFor(cell.skillId),
        sha256: finalValidation.sha256,
        width: finalValidation.width,
        height: finalValidation.height,
        has_alpha: finalValidation.hasAlpha,
        source_sheet: sheet.id,
        source_file: sheet.file,
        source_sha256: source.sha256,
        source_grid: { column: cell.column, row: cell.row, index: cell.index },
        source_region: cell.region,
        source_cell_size: [source.cellWidth, source.cellHeight],
        source_visible_bbox: [
          sourceStats.bbox[0],
          sourceStats.bbox[1],
          sourceStats.bboxSize[0],
          sourceStats.bboxSize[1],
        ],
        resized_content_size: finalIcon.resizedSize,
        final_visible_bbox: [
          finalValidation.alpha.bbox[0],
          finalValidation.alpha.bbox[1],
          finalValidation.alpha.bboxSize[0],
          finalValidation.alpha.bboxSize[1],
        ],
        edge_risk: {
          source_touches: sourceStats.touches,
          flagged: edgeRisk,
        },
      };
      allIcons.push({ entry, buffer: finalIcon.buffer });

      if (edgeRisk) {
        console.log(
          `EDGE_RISK skill=${cell.skillId} sheet=${sheet.id} grid=${cell.column},${cell.row} ` +
            `touches=${sourceStats.touches.join("+") || "none"} ` +
            `edge_components=${sourceStats.edgeComponentCount} shared=${sharedGridEdges.length}`,
        );
      }
    }

    sheetReports.push({
      id: sheet.id,
      file: sheet.file,
      sha256: source.sha256,
      width: source.width,
      height: source.height,
      channels: source.channels,
      grid: { columns: sheet.columns, rows: sheet.rows },
      cell_size: [source.cellWidth, source.cellHeight],
      shared_grid_edge_touch_pairs: sharedEdges,
      unused_cells: cellReports.filter((cell) => !cell.skillId).map((cell) => ({ column: cell.column, row: cell.row, index: cell.index })),
    });
  }

  assert(allIcons.length === EXPECTED_SKILL_IDS.length, `prepared ${allIcons.length} icons, expected ${EXPECTED_SKILL_IDS.length}`);
  const preparedNames = allIcons.map(({ entry }) => path.basename(entry.output)).sort();
  assert(preparedNames.every((name, index) => name === expectedPngNames[index]), "prepared output names do not match the embedded catalog");

  await fs.mkdir(OUTPUT_DIR, { recursive: true });
  for (const { entry, buffer } of allIcons) await fs.writeFile(outputPathFor(entry.skill_id), buffer);

  const edgeRiskEntries = allIcons.filter(({ entry }) => entry.edge_risk.flagged).length;
  const manifest = {
    schema_version: 4,
    contract_id: "ui.skill_icons.gothic_physical.approved_grid_import.v1",
    generation_mode: "deterministic_approved_grid_sheet_import",
    generation_policy: "exact_grid_crop_alpha_threshold_8_bbox_fit_118_centered_lanczos3",
    script: "tools/import_approved_skill_icon_sheets.mjs",
    source_sheets: sheetReports,
    final_asset_contract: {
      width: NATIVE_CANVAS,
      height: NATIVE_CANVAS,
      channels: 4,
      format: "PNG",
      background: "true RGBA transparency",
      alpha_threshold: ALPHA_THRESHOLD,
      max_visible_content: [MAX_CONTENT_SIZE, MAX_CONTENT_SIZE],
      resize_kernel: "lanczos3",
      placement: "centered",
      interpolation: "preserve_aspect_ratio_no_stretch",
    },
    output_root: OUTPUT_ROOT,
    skill_count: allIcons.length,
    edge_risk_count: edgeRiskEntries,
    icons: allIcons.map(({ entry }) => entry),
  };
  await fs.writeFile(MANIFEST_PATH, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");

  console.log(`SKILL_ICON_IMPORT_PASS count=${allIcons.length} output=${toPosix(path.relative(ROOT, OUTPUT_DIR))}`);
  console.log(`manifest=${toPosix(path.relative(ROOT, MANIFEST_PATH))}`);
  console.log(`contract=128x128 RGBA corners-alpha-0 partial-alpha max-content=${MAX_CONTENT_SIZE} edge_risk=${edgeRiskEntries}`);
}

main().catch((error) => {
  console.error(error?.stack || error);
  process.exitCode = 1;
});
