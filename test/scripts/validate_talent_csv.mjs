// Node 脚本：校验 defs/talents 下的天赋 CSV（列数 / 引用完整性 / 坐标冲突 / 成本公式 / target_ids 对照 defs）
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

function parseCsv(text) {
  const rows = [];
  let cur = '', row = [], inQ = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQ) {
      if (c === '"') {
        if (text[i + 1] === '"') { cur += '"'; i++; } else inQ = false;
      } else cur += c;
    } else if (c === '"') inQ = true;
    else if (c === ',') { row.push(cur); cur = ''; }
    else if (c === '\n') { row.push(cur); rows.push(row); row = []; cur = ''; }
    else if (c !== '\r') cur += c;
  }
  if (cur !== '' || row.length) { row.push(cur); rows.push(row); }
  return rows.filter(r => r.some(x => x.trim() !== ''));
}

const dir = join(process.cwd(), 'defs/talents');
const files = ['normal_talents.csv', 'ascension_talents.csv'].filter(f => readdirSync(dir).includes(f));

// 真实存在的 ore / tile id（来自 defs/ 目录）
const ores = readdirSync(join(process.cwd(), 'defs/ores')).map(f => f.replace('.tres', ''));
const tiles = readdirSync(join(process.cwd(), 'defs/tiles')).map(f => f.replace('.tres', ''));
const validTargets = new Set([...ores, ...tiles, 'gold_links', 'gold_links_group', 'normal_run', 'pickaxe', 'all']);

const tables = {};
const allIds = new Set();
for (const f of files) {
  const rows = parseCsv(readFileSync(join(dir, f), 'utf8'));
  const header = rows[0];
  tables[f] = { header, rows: rows.slice(1) };
  for (const r of tables[f].rows) allIds.add(r[0]);
}

let errors = 0;
function err(f, line, msg) { console.log(`  [${f}:${line}] ${msg}`); errors++; }

for (const f of files) {
  const { header, rows } = tables[f];
  const H = header.length;
  const colIdx = header.indexOf('col');
  const rowIdx = header.indexOf('row');
  const costIdx = header.indexOf('cost');
  const manIdx = header.indexOf('cost_mantissa');
  const expIdx = header.indexOf('cost_exponent');
  const curIdx = header.indexOf('currency');
  const preIdx = header.indexOf('prerequisite_ids');
  const ascIdx = header.indexOf('ascension_prerequisite_id');
  const tgtIdx = header.indexOf('target_ids');

  console.log(`\n== ${f} == 列数=${H} 行数=${rows.length}`);
  const seen = new Set();
  const pos = new Set();
  for (let li = 0; li < rows.length; li++) {
    const r = rows[li];
    const line = li + 2;
    if (r.length !== H) { err(f, line, `列数 ${r.length} ≠ ${H}`); continue; }
    const id = r[0];

    if (seen.has(id)) err(f, line, `重复 id: ${id}`); seen.add(id);

    // 成本公式 cost == mantissa × 10^expo（仅 normal 表有这两列）
    if (manIdx >= 0 && costIdx >= 0 && r[costIdx] !== '0') {
      const want = parseFloat(r[manIdx]) * Math.pow(10, parseFloat(r[expIdx]));
      const got = parseInt(r[costIdx], 10);
      if (Math.abs(want - got) > Math.max(1, got * 1e-9))
        err(f, line, `${id}: cost=${r[costIdx]} 但 mantissa×10^expo=${r[manIdx]}e${r[expIdx]}=${want}`);
    }

    // 坐标唯一
    const key = `${r[colIdx]},${r[rowIdx]}`;
    if (pos.has(key)) err(f, line, `${id}: 坐标 (${r[colIdx]},${r[rowIdx]}) 与另一节点冲突`);
    pos.add(key);

    // 货币
    if (f === 'ascension_talents.csv' && r[curIdx] !== '升华点')
      err(f, line, `${id}: 货币应为升华点，实际 ${r[curIdx]}`);

    // target_ids 是否指向真实存在的 ore/tile（逗号分隔的合法集合）
    if (tgtIdx >= 0 && r[tgtIdx]) {
      for (const t of r[tgtIdx].split(',').map(s => s.trim()).filter(Boolean)) {
        if (!validTargets.has(t)) err(f, line, `${id}: target_ids 引用未知实体 ${t}`);
      }
    }

    // 引用完整性
    for (const p of (r[preIdx] || '').split(',').map(s => s.trim()).filter(Boolean))
      if (!allIds.has(p)) err(f, line, `${id}: 前置 ${p} 不存在`);
    if (f === 'normal_talents.csv' && ascIdx >= 0 && r[ascIdx]) {
      for (const p of r[ascIdx].split(',').map(s => s.trim()).filter(Boolean))
        if (!allIds.has(p)) err(f, line, `${id}: 升华前置 ${p} 不存在`);
    }
  }
}

console.log(`\n总问题数: ${errors}`);
process.exit(errors ? 1 : 0);
