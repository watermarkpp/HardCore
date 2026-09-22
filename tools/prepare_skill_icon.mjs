#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const sharp = require("sharp");

const [inputPath, outputPath] = process.argv.slice(2);
if (!inputPath || !outputPath) {
  throw new Error("usage: node tools/prepare_skill_icon.mjs <source.png> <output.png>");
}

const metadata = await sharp(inputPath).metadata();
if (!metadata.width || !metadata.height || !metadata.hasAlpha) {
  throw new Error(`source is not a true RGBA image: ${inputPath}`);
}

const { data, info } = await sharp(inputPath)
  .ensureAlpha()
  .raw()
  .toBuffer({ resolveWithObject: true });
let visiblePixels = 0;
let partialAlphaPixels = 0;
let edgePixels = 0;
let transparentEdgePixels = 0;
for (let y = 0; y < info.height; y += 1) {
  for (let x = 0; x < info.width; x += 1) {
    const alpha = data[(y * info.width + x) * info.channels + 3];
    if (alpha > 0) visiblePixels += 1;
    if (alpha > 0 && alpha < 255) partialAlphaPixels += 1;
    if (x === 0 || y === 0 || x === info.width - 1 || y === info.height - 1) {
      edgePixels += 1;
      if (alpha <= 8) transparentEdgePixels += 1;
    }
  }
}
if (visiblePixels === 0 || partialAlphaPixels === 0) {
  throw new Error(`source has no usable antialiased cutout: ${inputPath}`);
}
if (transparentEdgePixels / edgePixels < 0.9) {
  throw new Error(`source subject/background touches too much of the outer edge: ${inputPath}`);
}

const { data: resized, info: resizedInfo } = await sharp(inputPath)
  .trim({ background: { r: 0, g: 0, b: 0, alpha: 0 }, threshold: 1 })
  .resize(112, 112, { fit: "inside", kernel: sharp.kernel.lanczos3 })
  .png()
  .toBuffer({ resolveWithObject: true });
const left = Math.floor((128 - resizedInfo.width) / 2);
const right = 128 - resizedInfo.width - left;
const top = Math.floor((128 - resizedInfo.height) / 2);
const bottom = 128 - resizedInfo.height - top;

await fs.mkdir(path.dirname(outputPath), { recursive: true });
await sharp(resized)
  .extend({
    top,
    bottom,
    left,
    right,
    background: { r: 0, g: 0, b: 0, alpha: 0 },
  })
  .png({ compressionLevel: 9, adaptiveFiltering: true })
  .toFile(outputPath);

