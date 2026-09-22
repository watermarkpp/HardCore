import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

// Resolve exclusively from the bundled runtime junction, never repository deps.
const outDir = path.resolve(process.argv[2] || 'outputs/repair_v92/excel');
const outputFilename = process.argv[3] || 'HardCore_当前地图怪物真实掉率_20260922.xlsx';
if (path.basename(outputFilename) !== outputFilename || !outputFilename.endsWith('.xlsx')) throw new Error('Expected an .xlsx filename without a directory');
const armorRevision = process.argv.includes('--armor-single-slot');
const bundledRequire = createRequire(path.join(outDir, 'runtime-loader.cjs'));
const { Workbook, SpreadsheetFile } = await import(pathToFileURL(bundledRequire.resolve('@oai/artifact-tool')).href);
const data = JSON.parse(await fs.readFile(path.join(outDir, 'exact_ground_probabilities.json'), 'utf8'));
const previewDir = path.join(outDir, 'previews');
await fs.mkdir(previewDir, { recursive: true });
const workbook = Workbook.create();
const manifest = { sourceSha256: data.source_sha256, outputFilename, armorRevision, sheets: [], probabilityCells: [], renders: [] };
const font = 'Microsoft YaHei';
const colors = { navy: '#243746', text: '#23313B', muted: '#596773', pale: '#F0F4F7', gold: '#886024', teal: '#397668' };

function put(sheet, cell, value) { sheet.getRange(cell).values = [[value]]; }
function standard(sheet, end, widths) {
  sheet.showGridLines = false;
  const all = sheet.getRange(`A1:F${end}`);
  all.format.font = { name: font, size: 10, color: colors.text };
  all.format.verticalAlignment = 'center';
  all.format.rowHeight = 20;
  all.setNumberFormat('General');
  for (const [col, width] of Object.entries(widths)) sheet.getRange(`${col}1:${col}${end}`).format.columnWidth = width;
  sheet.getRange('A1:F1').format.rowHeight = 9;
  sheet.getRange('A2:F2').format.rowHeight = 29;
  sheet.getRange('A2:F2').format.font = { name: font, size: 15, bold: true, color: colors.navy };
  sheet.getRange('A2:F2').format.borders = { bottom: { style: 'thin', color: '#AEBCC7' } };
}
function header(sheet, row, labels) {
  const range = sheet.getRange(`A${row}:F${row}`);
  range.values = [labels];
  range.format.fill = colors.navy;
  range.format.font = { name: font, size: 10, bold: true, color: '#FFFFFF' };
  range.format.rowHeight = 30;
  range.format.horizontalAlignment = 'center';
  range.format.borders = { insideVertical: { style: 'thin', color: '#FFFFFF' } };
}
function probabilityCell(sheet, row, value, kind, monsterId) {
  const address = `C${row}`;
  sheet.getRange(address).setNumberFormat('@');
  sheet.getRange(address).format.horizontalAlignment = 'left';
  sheet.getRange(address).format.wrapText = true;
  manifest.probabilityCells.push({ sheet: sheet.name, address, value, kind, monsterId });
}
function sheetName(m) { return `${m.monster_id}_${m.name}`.replace(/[\\/?*\[\]:]/g, '_').slice(0, 31); }

const overview = workbook.worksheets.add('总览');
standard(overview, 138, { A: 14, B: 29, C: 17, D: 15, E: 15, F: 57 });
overview.tabColor = colors.navy;
put(overview, 'A2', 'HardCore 当前地图怪物真实掉率' + (armorRevision ? ' · 衣服单槽修正版' : ''));
put(overview, 'A3', '统计日期'); put(overview, 'B3', '2026-09-22'); overview.getRange('B3').setNumberFormat('@');
put(overview, 'C3', '当前正式地图'); put(overview, 'D3', data.map_count);
put(overview, 'E3', '刷新点'); put(overview, 'F3', data.spawn_points);
put(overview, 'A4', '怪物种类'); put(overview, 'B4', data.summary.monster_count);
put(overview, 'C4', '正式掉落槽'); put(overview, 'D4', data.slot_count);
put(overview, 'E4', '实际输出种类'); put(overview, 'F4', data.summary.output_rows);
put(overview, 'A6', '主表概率：每次击杀后，指定物品或指定金额金币至少实际落地一份的精确概率。');
put(overview, 'A7', '已计入每次最多15件、保护组优先、组内优先级及同级超限随机选择。同物品的多个槽合并计算。');
put(overview, 'A8', '所有概率均保存为分数字符串及Excel文本格式。下方槽明细仅供核对，单槽判定概率并不等于实际落地概率。');
put(overview, 'A9', '分类：普通61种、精英27种、Boss17种、特殊普通7种、特殊8种。特殊分类保留当前正式定义。');
put(overview, 'A10', '空掉落表5种仍各有一张表。触龙神124已包含：死亡棺材913207，金币70000实际概率为0/1。');
put(overview, 'A11', armorRevision
  ? '衣服修正：除六个暗之Boss最高级衣服外，每怪同一实际衣服仅判定一槽，保留单槽原概率；15件上限及优先级不变。'
  : '每个怪物表包含实际输出概率、原始独立槽明细、当前地图ID及名称。静态快照中的分数使用任意精度有理数计算。');
put(overview, 'A12', '口径：死亡掉落流程生成的地面奖励；不包含个人显示过滤、拾取结果或事件额外奖励。');
overview.getRange('A6:F12').format.rowHeight = 23;
overview.getRange('A6:F12').format.font = { name: font, size: 10, color: colors.muted };
header(overview, 14, ['怪物ID', '怪物名称', '正式分类', '刷新点数', '独立槽数', '对应工作表']);
overview.getRange(`A15:F${14 + data.monsters.length}`).values = data.monsters.map(m => [m.monster_id, m.name, m.classification_label, m.spawn_points, m.slots.length, sheetName(m)]);
overview.freezePanes.freezeRows(14);
manifest.sheets.push({ name: '总览', monsterId: null });

for (const m of data.monsters) {
  const name = sheetName(m);
  const sheet = workbook.worksheets.add(name);
  const mainStart = 9;
  const mainCount = Math.max(1, m.outputs.length);
  const detailHeader = mainStart + mainCount + 2;
  const detailStart = detailHeader + 1;
  const detailCount = Math.max(1, m.slots.length);
  const mapsHeader = detailStart + detailCount + 2;
  const mapsStart = mapsHeader + 1;
  const end = mapsStart + m.maps.length + 4;
  standard(sheet, end, { A: 37, B: 16, C: 82, D: 12, E: 32, F: 39 });
  sheet.tabColor = m.classification === 'boss' ? colors.gold : m.classification === 'elite' ? colors.teal : '#708596';
  put(sheet, 'A2', `${m.name}（${m.monster_id}）`);
  put(sheet, 'A3', `正式分类：${m.classification_label}`);
  put(sheet, 'B3', `刷新点：${m.spawn_points}`);
  put(sheet, 'C3', `刷新地图：${m.maps.length}张；落地上限：${data.ground_limit}件`);
  put(sheet, 'A4', `正式分类键：${m.classification}`);
  put(sheet, 'C4', `刷新分类：${m.spawn_classification || '未另行指定'}`);
  put(sheet, 'A5', '实际概率：每次击杀后，该物品或指定金币金额至少落地一份。已计入15件上限及选择顺序。');
  put(sheet, 'A6', '分数均为精确文本。独立槽先判定，再按保护组、优先级和同级随机选择。');
  sheet.getRange('A5:F6').format.font = { name: font, size: 10, color: colors.muted };
  header(sheet, 8, ['实际掉落物品', '实际物品ID', '实际落地概率（精确分数）', '独立槽数', '各槽判定概率（核对）', '保护组 / 优先级（核对）']);
  if (m.outputs.length) {
    sheet.getRange(`A${mainStart}:F${mainStart + m.outputs.length - 1}`).values = m.outputs.map(r => [r.name, r.item_id, r.actual_probability, r.slot_count, r.slot_probabilities, r.groups]);
    for (let i = 0; i < m.outputs.length; i++) {
      const row = mainStart + i;
      const r = m.outputs[i];
      probabilityCell(sheet, row, r.actual_probability, 'actual', m.monster_id);
      sheet.getRange(`E${row}:F${row}`).setNumberFormat('@');
      sheet.getRange(`E${row}:F${row}`).format.wrapText = true;
      const lines = Math.max(Math.ceil(r.actual_probability.length / 76), r.slot_probabilities.split('\n').length, r.groups.split('\n').length);
      sheet.getRange(`A${row}:F${row}`).format.rowHeight = Math.max(23, lines * 15 + 8);
      if (i % 2 === 1) sheet.getRange(`A${row}:F${row}`).format.fill = '#F5F7F9';
      if (r.actual_probability === '0/1') sheet.getRange(`C${row}`).format.font = { name: font, size: 10, color: '#A04332', bold: true };
    }
  } else {
    put(sheet, `A${mainStart}`, '正式空掉落表');
    put(sheet, `C${mainStart}`, '无掉落物品；当前正式表无独立掉落槽。');
    sheet.getRange(`A${mainStart}:F${mainStart}`).format.rowHeight = 28;
  }
  header(sheet, detailHeader, ['原始槽UID', '实际物品ID', '单槽判定概率（不是实际落地概率）', '保护组', '优先级', '实际输出']);
  if (m.slots.length) {
    sheet.getRange(`A${detailStart}:F${detailStart + m.slots.length - 1}`).values = m.slots.map(r => [r.slot_uid, r.item_id, r.probability, r.protected ? '保护' : '常规', r.priority, r.name]);
    for (let i = 0; i < m.slots.length; i++) probabilityCell(sheet, detailStart + i, m.slots[i].probability, 'slot', m.monster_id);
  } else put(sheet, `A${detailStart}`, '无独立掉落槽');
  header(sheet, mapsHeader, ['当前正式地图ID', '地图名称', '', '', '', '']);
  // Map names may be long, so the name occupies the wide probability column.
  put(sheet, `B${mapsHeader}`, ''); put(sheet, `C${mapsHeader}`, '当前正式地图名称');
  for (let i = 0; i < m.maps.length; i++) {
    put(sheet, `A${mapsStart + i}`, m.maps[i].map_id);
    put(sheet, `C${mapsStart + i}`, m.maps[i].name);
  }
  put(sheet, `A${mapsStart + m.maps.length + 1}`, '来源：当前正式地图刷新数据、正式怪物分类及生产掉落查询快照（2026-09-22）。');
  put(sheet, `A${mapsStart + m.maps.length + 2}`, `概率权威：dpv2.user_loot_sheet.v1；输入快照SHA-256：${data.source_sha256}`);
  sheet.freezePanes.freezeRows(8);
  manifest.sheets.push({ name, monsterId: m.monster_id, classification: m.classification_label,
    outputs: m.outputs.length, slots: m.slots.length, mainStart, detailStart, mapsStart,
    mapCount: m.maps.length, empty: m.outputs.length === 0 });
}

workbook.recalculate();
const inspected = await workbook.inspect({ kind: 'table', range: '124_触龙神!A2:F12', include: 'values,formulas', maxChars: 2500, tableMaxRows: 11, tableMaxCols: 6 });
await fs.writeFile(path.join(outDir, 'artifact_inspection.ndjson'), inspected.ndjson);
const errors = await workbook.inspect({ kind: 'match', searchTerm: '#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!', options: { useRegex: true, maxResults: 20 }, summary: 'Final formula error scan', maxChars: 2000 });
await fs.writeFile(path.join(outDir, 'artifact_formula_errors.ndjson'), errors.ndjson);
const outputPath = path.join(outDir, outputFilename);
const xlsx = await SpreadsheetFile.exportXlsx(workbook);
await xlsx.save(outputPath);
console.log(`EXPORTED ${outputPath}`);

for (let i = 0; i < manifest.sheets.length; i++) {
  const entry = manifest.sheets[i];
  const filename = `${String(i).padStart(3, '0')}_${entry.monsterId ?? 'overview'}.png`;
  const range = entry.monsterId === null ? 'A1:F20' : 'A1:F12';
  const preview = await workbook.render({ sheetName: entry.name, range, scale: 1, format: 'png' });
  await fs.writeFile(path.join(previewDir, filename), new Uint8Array(await preview.arrayBuffer()));
  manifest.renders.push({ sheet: entry.name, file: filename, range });
  if ((i + 1) % 10 === 0) console.log(`RENDERED ${i + 1}/${manifest.sheets.length}`);
}
await fs.writeFile(path.join(outDir, 'workbook_manifest.json'), JSON.stringify(manifest, null, 2));
console.log(JSON.stringify({ sheets: manifest.sheets.length, probabilityCells: manifest.probabilityCells.length, rendered: manifest.renders.length }));
