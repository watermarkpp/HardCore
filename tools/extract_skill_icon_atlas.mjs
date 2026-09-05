#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const sharp = require("sharp");

const [inputPath, ...outputPaths] = process.argv.slice(2);
if (!inputPath || outputPaths.length !== 4) {
  throw new Error(
    "usage: node tools/extract_skill_icon_atlas.mjs <atlas.png> <top-left.png> <top-right.png> <bottom-left.png> <bottom-right.png>",
  );
}

const source = sharp(inputPath, { failOn: "error" });
const metadata = await source.metadata();
if (!metadata.width || !metadata.height) {
  throw new Error(`cannot read atlas dimensions: ${inputPath}`);
}
if (!metadata.hasAlpha) {
  throw new Error(`atlas is not true RGBA and will not be extracted: ${inputPath}`);
}

const splitX = Math.floor(metadata.width / 2);
const splitY = Math.floor(metadata.height / 2);
const regions = [
  { left: 0, top: 0, width: splitX, height: splitY },
  { left: splitX, top: 0, width: metadata.width - splitX, height: splitY },
  { left: 0, top: splitY, width: splitX, height: metadata.height - splitY },
  {
    left: splitX,
    top: splitY,
    width: metadata.width - splitX,
    height: metadata.height - splitY,
  },
];

const { data: atlasPixels, info: atlasInfo } = await sharp(inputPath)
  .ensureAlpha()
  .raw()
  .toBuffer({ resolveWithObject: true });
let transparentEdgePixels = 0;
let edgePixels = 0;
for (let y = 0; y < atlasInfo.height; y += 1) {
  for (let x = 0; x < atlasInfo.width; x += 1) {
    if (x !== 0 && y !== 0 && x !== atlasInfo.width - 1 && y !== atlasInfo.height - 1) {
      continue;
    }
    edgePixels += 1;
    const alpha = atlasPixels[(y * atlasInfo.width + x) * atlasInfo.channels + 3];
    if (alpha <= 8) transparentEdgePixels += 1;
  }
}
if (transparentEdgePixels / edgePixels < 0.9) {
  throw new Error(`atlas does not have a transparent outer edge: ${inputPath}`);
}

for (let index = 0; index < regions.length; index += 1) {
  const region = regions[index];
  const outputPath = outputPaths[index];
  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  await sharp(inputPath)
    .extract(region)
    .resize(128, 128, { fit: "fill", kernel: sharp.kernel.lanczos3 })
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toFile(outputPath);
}
