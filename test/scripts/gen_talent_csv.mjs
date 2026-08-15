// Node 脚本：按确认后的设计重写 defs/talents 两份 CSV。
// 改完跑 node test/scripts/gen_talent_csv.mjs 重新生成，再跑 validate_talent_csv.mjs 校验。
// 设计决策（2026-08-16 与用户确认）：
//  - 无自动建筑；矿石是点击掉落物。购买目标是"地块"（放置时计价）+ 地块行为升级 + 矿物价值升级 + 升华。
//  - 矿物价值升级 10 级/矿（原 15 级）；条件用累计开采数 ore_mined。
//  - 地块：天赋树里只做"解锁"，放置/卖出在游戏里计价（base×1.15^已放置，卖=25%）。
//  - 地块行为升级 5 级/块（新增）。
//  - 开局只有 dirt；grass 也需要购买。
//  - 删：Gold Link、协同 I/II、离线收益、bulk/buy_max、meta_gold_research。
//  - 升华点公式（Cookie Clicker 式）：总点=floor(cbrt(累计金币/1e6))，升华时获得差值，每点 +1% 金币获取。
import { writeFileSync } from 'node:fs';

const INT64_MAX = 9223372036854775807n;

// ---------- 工具 ----------
function fmtMantissa(costBig) {
  // 用整数字符串精确推导：cost / 10^exp 的小数形式，保证 mantissa×10^exp == cost 恒成立
  const s = costBig.toString();
  if (s === '0') return '0';
  const mant = s.length > 1 ? `${s[0]}.${s.slice(1)}` : s;
  return mant.replace(/\.?0+$/, '');
}
function fmtDisplay(costBig) {
  const cost = Number(costBig);
  if (cost === 0) return '0';
  if (cost < 1000) return String(cost);
  const exp = Math.floor(Math.log10(cost));
  const m = fmtMantissa(costBig);
  const SUF = [['e+', 21], ['Qi', 18], ['Qa', 15], ['T', 12], ['B', 9], ['M', 6], ['K', 3]];
  for (const [s, e] of SUF) if (exp >= e) return e === 21 ? `${m}e+${exp}` : `${m}${s}`;
  return String(cost);
}
function costRow(costBig) {
  const cost = costBig.toString();
  const display = fmtDisplay(costBig);
  const mantissa = fmtMantissa(costBig);
  const exp = costBig === 0n ? '0' : String(Math.floor(Math.log10(Number(costBig))));
  const big = costBig > INT64_MAX ? 'true' : 'false';
  return { cost, display, mantissa, exp, big };
}

// ---------- 常量数据 ----------
const ORES = ['coal', 'iron', 'zinc', 'gold', 'crystal', 'obsidian', 'diamond', 'cat'];
const ORE_NAME = { coal: '煤矿', iron: '铁矿', zinc: '锌矿', gold: '金矿', crystal: '水晶矿', obsidian: '黑曜石', diamond: '钻石矿', cat: '猫矿' };
const ORE_COLOR = { gold: 'gold' }; // 金矿名称用黄色
const ORE_UNLOCK = [
  { id: 'coal', cost: 0n, prereq: '', cond: '开局已购买' },
  { id: 'iron', cost: 250n, prereq: 'unlock_coal', cond: 'coal_mined ≥ 50' },
  { id: 'zinc', cost: 2750n, prereq: 'unlock_iron', cond: 'iron_mined ≥ 50' },
  { id: 'gold', cost: 30000n, prereq: 'unlock_zinc', cond: 'zinc_mined ≥ 50' },
  { id: 'crystal', cost: 325000n, prereq: 'unlock_gold', cond: 'gold_mined ≥ 50' },
  { id: 'obsidian', cost: 3500000n, prereq: 'unlock_crystal', cond: 'crystal_mined ≥ 50' },
  { id: 'diamond', cost: 50000000n, prereq: 'unlock_obsidian', cond: 'obsidian_mined ≥ 50' },
  { id: 'cat', cost: 825000000n, prereq: 'unlock_diamond', cond: 'diamond_mined ≥ 50' },
];
// 矿物价值升级：tier1 成本 = 20×解锁价（coal 例外固定 750），倍率见下
const PROD_MULT = [1n, 5n, 50n, 5000n, 500000n, 50000000n, 50000000000n, 50000000000000n, 50000000000000000n, 50000000000000000000n];
const PROD_MINED = [1, 5, 25, 50, 100, 200, 400, 800, 1600, 3200]; // ore_mined 门槛
const PROD_STAGE = ['本轮核心', '本轮核心', '本轮核心', '本轮核心', '升华扩展 I', '升华扩展 I', '大数阶段', '大数阶段', '终局阶段', '终局阶段'];
const PROD_ASC = ['', '', '', '', 'meta_deep_mining', 'meta_deep_mining', 'meta_abyssal_mining', 'meta_abyssal_mining', 'meta_endless_mining', 'meta_endless_mining'];
const PROD_FLAVOR = ['基础工具', '标准流程', '机械化', '精密钻探', '工业扩建', '自动调度', '深层网络', '量子提炼', '星核工艺', '维度开采'];

// 地块：id / 显示名 / 解锁费 / 放置基准价 / 行为升级(L1..L5 的数值+描述)
const TILES = [
  { id: 'dirt', name: '泥土', unlock: 0n,     place: 10n,      up: [['1.1', '手挖伤害 ×1.1'], ['1.2', '手挖伤害 ×1.2'], ['1.3', '手挖伤害 ×1.3'], ['1.4', '手挖伤害 ×1.4'], ['1.5', '手挖伤害 ×1.5']], upBase: 100n },
  { id: 'grass', name: '草地', unlock: 500n,  place: 50n,      up: [['2.0', '手挖伤害 ×2'], ['2.5', '手挖伤害 ×2.5'], ['3.0', '手挖伤害 ×3'], ['3.5', '手挖伤害 ×3.5'], ['4.0', '手挖伤害 ×4']], upBase: 500n },
  { id: 'stone', name: '石头', unlock: 2500n, place: 250n,     up: [['2.0', '结算价值 ×2'], ['2.5', '结算价值 ×2.5'], ['3.0', '结算价值 ×3'], ['3.5', '结算价值 ×3.5'], ['4.0', '结算价值 ×4']], upBase: 2500n },
  { id: 'water', name: '水域', unlock: 12500n, place: 1250n,   up: [['0.15', '沉没返还 15%'], ['0.20', '沉没返还 20%'], ['0.25', '沉没返还 25%'], ['0.30', '沉没返还 30%'], ['0.35', '沉没返还 35%']], upBase: 12500n },
  { id: 'fire', name: '熔岩', unlock: 50000n, place: 5000n,    up: [['15', '每秒伤害 15'], ['20', '每秒伤害 20'], ['25', '每秒伤害 25'], ['30', '每秒伤害 30'], ['35', '每秒伤害 35']], upBase: 50000n },
  { id: 'push', name: '传送带', unlock: 125000n, place: 12500n, up: [['1.8', '推动周期 1.8s'], ['1.6', '推动周期 1.6s'], ['1.4', '推动周期 1.4s'], ['1.2', '推动周期 1.2s'], ['1.0', '推动周期 1.0s']], upBase: 125000n },
  { id: 'pull', name: '磁吸', unlock: 250000n, place: 25000n,  up: [['1.8', '拉动周期 1.8s'], ['1.6', '拉动周期 1.6s'], ['1.4', '拉动周期 1.4s'], ['1.2', '拉动周期 1.2s'], ['1.0', '拉动周期 1.0s']], upBase: 250000n },
  { id: 'volcano_stable', name: '稳定火山', unlock: 1250000n, place: 125000n, up: [['45', '四邻伤害 45'], ['60', '四邻伤害 60'], ['75', '四邻伤害 75'], ['90', '四邻伤害 90'], ['105', '四邻伤害 105']], upBase: 1250000n },
  { id: 'upgrade', name: '升级台', unlock: 5000000n, place: 500000n, up: [['2.5', '升级周期 2.5s'], ['2.0', '升级周期 2.0s'], ['1.5', '升级周期 1.5s'], ['1.2', '升级周期 1.2s'], ['1.0', '升级周期 1.0s']], upBase: 5000000n },
  { id: 'rarity', name: '稀有矿脉', unlock: 10000000n, place: 1000000n, up: [['3', '稀有度过滤 ≥3'], ['4', '稀有度过滤 ≥4'], ['4', '过滤 ≥4 且结算 ×1.1'], ['4', '过滤 ≥4 且结算 ×1.2'], ['4', '过滤 ≥4 且结算 ×1.3']], upBase: 10000000n },
  { id: 'spawn', name: '水晶矿脉', unlock: 25000000n, place: 2500000n, up: [['4.0', '生成周期 4.0s'], ['3.0', '生成周期 3.0s'], ['2.5', '生成周期 2.5s'], ['2.0', '生成周期 2.0s'], ['1.5', '生成周期 1.5s']], upBase: 25000000n },
];
const TILE_COLOR = { grass: 'green', fire: 'red', water: 'blue', gold: 'gold', stone: 'gray' };

// 地块协同：每 10 块已放置 → 目标矿价值 +10/15/20%
const TERRAIN_TARGET = {
  dirt: ['coal'], grass: ['gold'], stone: ['iron'], water: ['zinc'],
  fire: ORES, push: ['coal', 'iron', 'zinc', 'gold'],
  pull: ['crystal', 'obsidian', 'diamond', 'cat'],
  volcano_stable: ['obsidian'], upgrade: ['cat'], rarity: ['diamond'], spawn: ['crystal'],
};
const TERRAIN_COST = {
  dirt: [1800n, 130000n, 2900000n], grass: [850000n, 63000000n, 1400000000n],
  stone: [18000n, 1300000n, 29000000n], water: [140000n, 11000000n, 230000000n],
  fire: [190000000n, 14000000000n, 310000000000n], push: [300000n, 30000000n, 650000000n],
  pull: [290000000n, 29000000000n, 620000000000n], volcano_stable: [25000000n, 1900000000n, 40000000000n],
  upgrade: [790000000n, 59000000000n, 1300000000000n], rarity: [140000000n, 11000000000n, 220000000000n],
  spawn: [4700000n, 350000000n, 7500000000n],
};
const TERRAIN_RATE = [0.10, 0.15, 0.20];
const TERRAIN_NEED = [10, 50, 100];

// ---------- 行构造 ----------
const NORMAL = [];
function pushNormal(o) {
  NORMAL.push([
    o.id, o.name, o.desc, o.currency ?? '金币',
    ...(o.cost0 !== undefined ? ['0', '0', '0', '0'] : [o.cost, o.display, o.mantissa, o.exp]),
    String(o.col), String(o.row), o.prereq, o.asc ?? '', o.cond,
    o.effect, o.targets, o.op, String(o.value), '1', o.secondary ?? '',
    o.group, o.branch, o.level, o.stage, o.big ?? 'false',
  ]);
}
const C = (s) => `[color=#67E9F8][b]${s}[/b][/color]`;
const B = (s) => `[color=#86EFAC][b]${s}[/b][/color]`;
const G = (s) => `[color=#FACC15][b]${s}[/b][/color]`;

// 1) 升华根
pushNormal({
  id: 'talent_reset', name: '重置·升华',
  desc: `重置本轮${C('普通天赋')}并进行${C('升华')}，结算本次可获得的${C('升华点')}。`,
  cost0: true, col: 0, row: 0, prereq: '', cond: '始终可见',
  effect: 'PRESTIGE_RESET', targets: 'normal_run', op: 'RESET', value: 1,
  secondary: '升华点 = floor(cbrt(累计金币 / 1e6))，升华时领取差值；每点 +1% 金币获取（永久）',
  group: '核心', branch: 'prestige', level: 'Root', stage: '核心',
});

// 1.5) 稿子升级（上方：col 0 向上链，跨升四级后可强化暴击/范围）
{
  const PICKAXE = [
    ['pickaxe_root', '稿子精通', `解锁${C('稿子升级')}链。`, 1000, -1, 'PICKAXE_UPGRADE', 'UNLOCK', '1', ''],
    ['pickaxe_dmg_1', '稿子·锋利 I', `${C('稿子基础伤害')} ${B('+5')}。`, 5000, -2, 'PICKAXE_DAMAGE_FLAT', 'ADD', '5', 'pickaxe_root'],
    ['pickaxe_dmg_2', '稿子·锋利 II', `${C('稿子基础伤害')} ${B('+5')}。`, 50000, -3, 'PICKAXE_DAMAGE_FLAT', 'ADD', '5', 'pickaxe_dmg_1'],
    ['pickaxe_dmg_3', '稿子·锋利 III', `${C('稿子基础伤害')} ${B('+10')}。`, 500000, -4, 'PICKAXE_DAMAGE_FLAT', 'ADD', '10', 'pickaxe_dmg_2'],
    ['pickaxe_crit_1', '稿子·精准 I', `${C('暴击几率')} ${B('+2%')}。`, 5000000, -5, 'PICKAXE_CRIT_CHANCE', 'ADD', '0.02', 'pickaxe_dmg_3'],
    ['pickaxe_crit_2', '稿子·精准 II', `${C('暴击几率')} ${B('+3%')}。`, 50000000, -6, 'PICKAXE_CRIT_CHANCE', 'ADD', '0.03', 'pickaxe_crit_1'],
    ['pickaxe_critdmg', '稿子·重击', `${C('暴击伤害')} ${B('+50%')}。`, 500000000, -7, 'PICKAXE_CRIT_DAMAGE', 'ADD', '0.5', 'pickaxe_crit_2'],
    ['pickaxe_aoe', '稿子·横扫', `${C('稿子作用范围')} ${B('+1 格')}。`, 5000000000, -8, 'PICKAXE_AOE', 'SET', '1', 'pickaxe_critdmg'],
  ];
  for (let i = 0; i < PICKAXE.length; i++) {
    const [id, name, desc, cost, row, effect, op, value, prereq] = PICKAXE[i];
    const c = costRow(BigInt(cost));
    pushNormal({
      id, name, desc,
      cost: c.cost, display: c.display, mantissa: c.mantissa, exp: c.exp,
      col: 0, row, prereq,
      cond: prereq === '' ? '开局可见' : `已购买 ${PICKAXE[i - 1][1]}`,
      effect, targets: 'pickaxe', op, value,
      group: '稿子', branch: 'pickaxe', level: String(i + 1), stage: '本轮核心', big: c.big,
    });
  }
}

// 1.6) 全局金币收益（左侧：row 0 向左链 + 末端分支）
{
  const COIN = [
    ['coin_bonus', '金币收益', `${C('全局金币获取')} ${B('+10%')}。`, 500, -1, 'GLOBAL_COIN_MULT', 'ADD', '0.1'],
    ['coin_bonus_2', '金币收益 II', `${C('全局金币获取')} ${B('+10%')}。`, 5000, -2, 'GLOBAL_COIN_MULT', 'ADD', '0.1'],
    ['coin_bonus_3', '金币收益 III', `${C('全局金币获取')} ${B('+10%')}。`, 50000, -3, 'GLOBAL_COIN_MULT', 'ADD', '0.1'],
    ['coin_bonus_4', '金币收益 IV', `${C('全局金币获取')} ${B('+10%')}。`, 500000, -4, 'GLOBAL_COIN_MULT', 'ADD', '0.1'],
    ['coin_bonus_5', '金币收益 V', `${C('全局金币获取')} ${B('+10%')}。`, 5000000, -5, 'GLOBAL_COIN_MULT', 'ADD', '0.1'],
    ['coin_bonus_6', '金币收益 VI', `${C('全局金币获取')} ${B('+10%')}。`, 50000000, -6, 'GLOBAL_COIN_MULT', 'ADD', '0.1'],
  ];
  for (let i = 0; i < COIN.length; i++) {
    const [id, name, desc, cost, col, effect, op, value] = COIN[i];
    const c = costRow(BigInt(cost));
    pushNormal({
      id, name, desc,
      cost: c.cost, display: c.display, mantissa: c.mantissa, exp: c.exp,
      col, row: 0, prereq: i === 0 ? '' : COIN[i - 1][0],
      cond: i === 0 ? '开局可见' : `已购买 ${COIN[i - 1][1]}`,
      effect, targets: 'all', op, value,
      group: '金币收益', branch: 'coin', level: String(i + 1), stage: '本轮核心', big: c.big,
    });
  }
  // 末端上方分支：矿石结算价值（全局层）
  {
    const c = costRow(500000000n);
    pushNormal({
      id: 'coin_ore_value', name: '落矿收益', desc: `${C('矿石结算价值')} ${B('+10%')}。`,
      cost: c.cost, display: c.display, mantissa: c.mantissa, exp: c.exp,
      col: -6, row: -1, prereq: 'coin_bonus_6', cond: '已购买 金币收益 VI',
      effect: 'GLOBAL_ORE_VALUE_MULT', targets: 'all', op: 'ADD', value: '0.1',
      group: '金币收益', branch: 'coin', level: 'Cap', stage: '升华扩展 I', big: c.big,
    });
  }
}

// 2) 矿物解锁 + 价值升级（8 矿 × (1 + 10)）
ORES.forEach((ore, i) => {
  const u = ORE_UNLOCK[i];
  const oname = ORE_COLOR[ore] ? G(ORE_NAME[ore]) : C(ORE_NAME[ore]);
  pushNormal({
    id: `unlock_${ore}`, name: `解锁·${ORE_NAME[ore]}`,
    desc: `${oname}${C('解锁')}：允许实体 ${ore} 进入${C('自然落矿池')}（${B('Lv1~3')}同时允许）。`,
    cost: u.cost.toString(), display: fmtDisplay(u.cost), mantissa: fmtMantissa(u.cost), exp: u.cost === 0n ? '0' : String(Math.floor(Math.log10(Number(u.cost)))),
    col: i + 1, row: 0, prereq: u.prereq, cond: u.cond,
    effect: 'UNLOCK_ORE', targets: ore, op: 'UNLOCK', value: 1,
    group: '矿物解锁', branch: ore, level: 'Unlock', stage: '本轮核心',
    big: u.cost > INT64_MAX ? 'true' : 'false',
  });
  const prod01 = ore === 'coal' ? 750n : u.cost * 20n;
  for (let t = 1; t <= 10; t++) {
    const costBig = prod01 * PROD_MULT[t - 1];
    const c = costRow(costBig);
    const multStr = (2 ** t).toLocaleString('en-US'); // 32 / 1,024
    pushNormal({
      id: `prod_${ore}_${String(t).padStart(2, '0')}`, name: `${ORE_NAME[ore]}·${PROD_FLAVOR[t - 1]}`,
      desc: `${oname}${C('结算价值')} ${B('×2')}；购买后该矿价值累计倍率为 ${B(`×${multStr}`)}。`,
      cost: c.cost, display: c.display, mantissa: c.mantissa, exp: c.exp,
      col: i + 1, row: -t, prereq: t === 1 ? `unlock_${ore}` : `prod_${ore}_${String(t - 1).padStart(2, '0')}`,
      asc: PROD_ASC[t - 1], cond: `${ore}_mined ≥ ${PROD_MINED[t - 1]}`,
      effect: 'ORE_VALUE_MULT', targets: ore, op: 'MULTIPLY', value: 2,
      group: '矿物价值升级', branch: ore, level: String(t), stage: PROD_STAGE[t - 1], big: c.big,
    });
  }
});

// 3) 地块解锁（只解锁，放置计价在游戏内）
TILES.forEach((tile, i) => {
  const tname = tile.name === '草地' ? B('草地') : C(tile.name);
  pushNormal({
    id: `unlock_tile_${tile.id}`, name: `解锁地块·${tile.name}`,
    desc: `${C('解锁')} ${tile.name} 的购买与放置（放置时按 ${B('基准价 × 1.15^已放置')} 计费，卖出返还 ${B('25%')}）。`,
    cost: tile.unlock.toString(), display: fmtDisplay(tile.unlock), mantissa: fmtMantissa(tile.unlock), exp: tile.unlock === 0n ? '0' : String(Math.floor(Math.log10(Number(tile.unlock)))),
    col: 0, row: i + 1,
    prereq: i === 0 ? '' : `unlock_tile_${TILES[i - 1].id}`,
    cond: tile.unlock === 0n ? '开局已购买' : `已解锁前置地块 ${TILES[i - 1].name}`,
    effect: 'UNLOCK_TILE', targets: tile.id, op: 'UNLOCK', value: 1,
    group: '地块解锁', branch: tile.id, level: 'Unlock', stage: '本轮核心',
  });
});

// 4) 地块行为升级（11 块 × 5 级）
TILES.forEach((tile, i) => {
  for (let L = 1; L <= 5; L++) {
    const costBig = tile.upBase * (5n ** BigInt(L - 1));
    const c = costRow(costBig);
    const [val, text] = tile.up[L - 1];
    pushNormal({
      id: `tile_up_${tile.id}_${L}`, name: `${tile.name}强化 ${L}`,
      desc: `${C(tile.name)}${C('行为强化')}：${B(text)}。`,
      cost: c.cost, display: c.display, mantissa: c.mantissa, exp: c.exp,
      col: L, row: i + 1, prereq: L === 1 ? `unlock_tile_${tile.id}` : `tile_up_${tile.id}_${L - 1}`,
      cond: `已解锁地块 ${tile.name}`,
      effect: 'TILE_BEHAVIOR_UP', targets: tile.id, op: 'SET', value: val,
      secondary: text, group: '地块行为', branch: tile.id, level: String(L),
      stage: ['本轮核心', '本轮核心', '升华扩展 I', '升华扩展 I', '大数阶段'][L - 1], big: c.big,
    });
  }
});

// 5) 地块协同（11 块 × 3 级）
TILES.forEach((tile, i) => {
  for (let t = 1; t <= 3; t++) {
    const costBig = TERRAIN_COST[tile.id][t - 1];
    const c = costRow(costBig);
    const targets = TERRAIN_TARGET[tile.id];
    const targetStr = targets.length === ORES.length ? '全部矿物' : targets.map((t) => ORE_NAME[t] ?? t).join('、');
    pushNormal({
      id: `terrain_${tile.id}_${t}`, name: `${tile.name}协同 ${'ⅠⅡⅢ'[t - 1]}`,
      desc: `${targetStr}每${B('10块')}已放置的${C(tile.name)}，结算价值 ${B(`+${Math.round(TERRAIN_RATE[t - 1] * 100)}%`)}（最多 ${B('10组')}）。`,
      cost: c.cost, display: c.display, mantissa: c.mantissa, exp: c.exp,
      col: -t, row: i + 1,
      prereq: t === 1 ? `unlock_tile_${tile.id},unlock_${targets[0]}` : `terrain_${tile.id}_${t - 1}`,
      cond: `placed_${tile.id} ≥ ${TERRAIN_NEED[t - 1]}`,
      effect: 'TERRAIN_ORE_SYNERGY', targets: targets.join(','), op: 'SET_RATE_PER_10', value: TERRAIN_RATE[t - 1],
      secondary: `${targetStr}每10块${tile.name} +${Math.round(TERRAIN_RATE[t - 1] * 100)}%，最多计算10组。`,
      group: '地块协同', branch: tile.id, level: String(t), stage: ['本轮核心', '升华扩展 I', '大数阶段'][t - 1], big: c.big,
    });
  }
});

// 6) 金矿议会（精简为单节点价值天赋）
{
  const c = costRow(1000000000n);
  pushNormal({
    id: 'gold_council', name: '黄金矿业议会',
    desc: `${G('金矿')}${C('结算价值')} ${B('×4')}。`,
    cost: c.cost, display: c.display, mantissa: c.mantissa, exp: c.exp,
    col: 6, row: 1, prereq: 'unlock_gold', cond: 'gold_mined ≥ 50',
    effect: 'ORE_VALUE_MULT', targets: 'gold', op: 'MULTIPLY', value: 4,
    group: '矿物价值升级', branch: 'gold', level: 'Research', stage: '升华扩展 I',
  });
}

// ---------- 升华表 ----------
const ASC = [];
function pushAsc(o) {
  ASC.push([o.id, o.name, o.desc, '升华点', String(o.cost), String(o.col), String(o.row), o.prereq, o.effect, String(o.value), String(o.maxRank ?? 1), o.stage, o.notes]);
}
pushAsc({ id: 'meta_legacy', name: '矿业传承', desc: `${C('永久')}树根；启用${C('升华点')}与${C('永久升级')}。`, cost: 0, col: 0, row: 0, prereq: '', effect: 'UNLOCK_META', value: 1, stage: '树根', notes: '启用升华点与永久升级。升华点公式（Cookie Clicker 式）：总点 = floor(cbrt(累计金币/1e6))，按全时间累计推导永不减少，升华时领取差值；每点 +1% 金币获取（按已领取点数，全局被动）。购买状态永久保存。' });
pushAsc({ id: 'meta_deep_mining', name: '深层采矿许可', desc: `允许购买全部${C('矿物')}${C('价值升级')}的${B('第 5~6 级')}。`, cost: 10, col: 0, row: 1, prereq: 'meta_legacy', effect: 'UNLOCK_TIER_RANGE', value: '5-6', stage: '扩展 I', notes: '允许购买全部矿物价值升级第 5~6 级。购买状态永久保存。' });
pushAsc({ id: 'meta_abyssal_mining', name: '深渊采矿许可', desc: `允许购买${C('矿物')}${C('价值升级')}的${B('第 7~8 级')}；成本超 int，需${B('BigNumber')}。`, cost: 250, col: 0, row: 2, prereq: 'meta_deep_mining', effect: 'UNLOCK_TIER_RANGE', value: '7-8', stage: '大数', notes: '允许购买第 7~8 级（成本超 int，需 BigNumber）。购买状态永久保存。' });
pushAsc({ id: 'meta_endless_mining', name: '无尽采矿许可', desc: `允许购买${C('矿物')}${C('价值升级')}的${B('第 9~10 级')}；必须启用${B('BigNumber')}。`, cost: 5000, col: 0, row: 3, prereq: 'meta_abyssal_mining', effect: 'UNLOCK_TIER_RANGE', value: '9-10', stage: '终局', notes: '允许购买第 9~10 级；必须启用 BigNumber。购买状态永久保存。' });
pushAsc({ id: 'meta_permaslot_1', name: '永久槽 I', desc: `${C('升华')}时保留一个${C('普通天赋')}按钮。`, cost: 100, col: 1, row: 1, prereq: 'meta_legacy', effect: 'PERMANENT_SLOT', value: 1, stage: '扩展 I', notes: '升华时保留一个普通天赋。购买状态永久保存。' });
pushAsc({ id: 'meta_permaslot_2', name: '永久槽 II', desc: `额外保留一个${C('普通天赋')}按钮。`, cost: 1000, col: 1, row: 2, prereq: 'meta_permaslot_1', effect: 'PERMANENT_SLOT', value: 1, stage: '大数', notes: '额外保留一个普通天赋。购买状态永久保存。' });

// ---------- 写出 ----------
const NORMAL_HEADER = ['id', 'name', 'description', 'currency', 'cost', 'cost_display', 'cost_mantissa', 'cost_exponent', 'col', 'row', 'prerequisite_ids', 'ascension_prerequisite_id', 'unlock_condition', 'effect_type', 'target_ids', 'operation', 'value', 'max_rank', 'secondary_effect', 'group', 'branch', 'level', 'stage', 'requires_big_number'];
const ASC_HEADER = ['id', 'name', 'description', 'currency', 'cost', 'col', 'row', 'prerequisite_ids', 'effect_type', 'value', 'max_rank', 'stage', 'implementation_notes'];
const q = (r) => r.map((f) => `"${String(f)}"`).join(',');
writeFileSync('defs/talents/normal_talents.csv', [q(NORMAL_HEADER), ...NORMAL.map(q)].join('\n') + '\n');
writeFileSync('defs/talents/ascension_talents.csv', [q(ASC_HEADER), ...ASC.map(q)].join('\n') + '\n');
console.log(`normal: ${NORMAL.length} 行, ascension: ${ASC.length} 行`);
