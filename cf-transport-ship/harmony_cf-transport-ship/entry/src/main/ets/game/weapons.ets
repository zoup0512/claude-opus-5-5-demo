/**
 * 武器数据与状态机（手感参考穿越火线：首发精准、连射上跳后左右摆、狙击开镜才准）
 * 与原版 weapons.js 数值一致。
 */
import { Vec3 } from './math3d';

export class SpreadDef {
  base: number;
  scoped: number;
  move: number;
  air: number;
  crouch: number;
  perShot: number;
  max: number;
  recover: number;

  constructor(base: number, scoped: number, move: number, air: number, crouch: number, perShot: number,
    max: number, recover: number) {
    this.base = base;
    this.scoped = scoped;
    this.move = move;
    this.air = air;
    this.crouch = crouch;
    this.perShot = perShot;
    this.max = max;
    this.recover = recover;
  }
}

export class RecoilDef {
  up: number;
  upMax: number;
  side: number;
  sideStart: number;
  recover: number;

  constructor(up: number, upMax: number, side: number, sideStart: number, recover: number) {
    this.up = up;
    this.upMax = upMax;
    this.side = side;
    this.sideStart = sideStart;
    this.recover = recover;
  }
}

export class WeaponDef {
  id: string;
  name: string;
  slot: number;
  type: string; // rifle | sniper | smg | pistol | melee | grenade
  auto: boolean;
  dmg: number;
  headMul: number;
  limbMul: number;
  rpm: number;
  mag: number;
  reserve: number;
  reload: number;
  draw: number;
  speed: number;
  range: number;
  falloff: number;
  pen: number;
  armorPen: number;
  spread: SpreadDef | null;
  recoil: RecoilDef | null;
  bolt: number;
  zoom: number[];
  dmgLight: number; // 近战
  dmgHeavy: number;
  rangeLight: number;
  rangeHeavy: number;
  rateLight: number;
  rateHeavy: number;
  radius: number; // 手雷
  fuse: number;

  constructor(id: string, name: string, slot: number, type: string, auto: boolean, dmg: number, headMul: number,
    limbMul: number, rpm: number, mag: number, reserve: number, reload: number, draw: number, speed: number,
    range: number, falloff: number, pen: number, armorPen: number, spread: SpreadDef | null, recoil: RecoilDef | null,
    bolt: number, zoom: number[], dmgLight: number, dmgHeavy: number, rangeLight: number, rangeHeavy: number,
    rateLight: number, rateHeavy: number, radius: number, fuse: number) {
    this.id = id;
    this.name = name;
    this.slot = slot;
    this.type = type;
    this.auto = auto;
    this.dmg = dmg;
    this.headMul = headMul;
    this.limbMul = limbMul;
    this.rpm = rpm;
    this.mag = mag;
    this.reserve = reserve;
    this.reload = reload;
    this.draw = draw;
    this.speed = speed;
    this.range = range;
    this.falloff = falloff;
    this.pen = pen;
    this.armorPen = armorPen;
    this.spread = spread;
    this.recoil = recoil;
    this.bolt = bolt;
    this.zoom = zoom;
    this.dmgLight = dmgLight;
    this.dmgHeavy = dmgHeavy;
    this.rangeLight = rangeLight;
    this.rangeHeavy = rangeHeavy;
    this.rateLight = rateLight;
    this.rateHeavy = rateHeavy;
    this.radius = radius;
    this.fuse = fuse;
  }
}

export const WEAPONS: Map<string, WeaponDef> = new Map<string, WeaponDef>([
  ['ak47', new WeaponDef('ak47', 'AK-47', 0, 'rifle', true, 36, 4.0, 0.78, 600, 30, 90, 2.45, 0.85, 0.93, 220, 0.985,
    1.2, 0.78, new SpreadDef(0.0028, 0, 0.045, 0.16, 0.6, 0.0055, 0.05, 7),
    new RecoilDef(0.0105, 0.11, 0.0062, 5, 6.5), 0, [], 0, 0, 0, 0, 0, 0, 0, 0)],
  ['m4a1', new WeaponDef('m4a1', 'M4A1', 0, 'rifle', true, 32, 4.0, 0.8, 700, 30, 90, 2.3, 0.8, 0.95, 220, 0.985,
    1.0, 0.72, new SpreadDef(0.0024, 0, 0.04, 0.15, 0.6, 0.0044, 0.042, 8),
    new RecoilDef(0.0082, 0.085, 0.0048, 6, 7), 0, [], 0, 0, 0, 0, 0, 0, 0, 0)],
  ['awm', new WeaponDef('awm', 'AWM', 0, 'sniper', false, 118, 2.2, 0.82, 41, 5, 20, 3.5, 1.1, 0.82, 400, 0.998,
    2.6, 0.95, new SpreadDef(0.06, 0.0004, 0.09, 0.22, 0.85, 0, 0.2, 3),
    new RecoilDef(0.035, 0.035, 0.004, 0, 4), 1.35, [30, 11], 0, 0, 0, 0, 0, 0, 0, 0)],
  ['mp5', new WeaponDef('mp5', 'MP5', 0, 'smg', true, 25, 3.6, 0.85, 800, 30, 120, 2.1, 0.6, 1.0, 120, 0.97,
    0.6, 0.6, new SpreadDef(0.004, 0, 0.022, 0.12, 0.7, 0.0035, 0.04, 9),
    new RecoilDef(0.0058, 0.06, 0.004, 5, 8), 0, [], 0, 0, 0, 0, 0, 0, 0, 0)],
  ['deagle', new WeaponDef('deagle', '沙漠之鹰', 1, 'pistol', false, 54, 3.8, 0.75, 260, 7, 35, 2.0, 0.55, 1.0, 150,
    0.98, 1.0, 0.8, new SpreadDef(0.004, 0, 0.05, 0.18, 0.7, 0.028, 0.07, 5),
    new RecoilDef(0.03, 0.09, 0.008, 1, 5), 0, [], 0, 0, 0, 0, 0, 0, 0, 0)],
  ['knife', new WeaponDef('knife', '军刀', 2, 'melee', true, 0, 0, 0, 0, 0, 0, 0, 0.4, 1.08, 0, 0, 0, 0,
    null, null, 0, [], 52, 100, 1.9, 1.6, 0.42, 1.05, 0, 0)],
  ['he', new WeaponDef('he', '手雷', 3, 'grenade', false, 115, 0, 0, 0, 1, 0, 0, 0.5, 1.0, 0, 0, 0, 0,
    null, null, 0, [], 0, 0, 0, 0, 0, 0, 7.5, 2.6)]
]);

export function weaponDef(id: string): WeaponDef {
  return WEAPONS.get(id) as WeaponDef;
}

export const PRIMARIES: string[] = ['ak47', 'm4a1', 'awm', 'mp5'];

export class WeaponState {
  def: WeaponDef;
  id: string;
  mag: number;
  reserve: number;
  nextFire: number = 0;
  reloadUntil: number = 0;
  shotsFired: number = 0;
  spreadAcc: number = 0;
  lastShot: number = -10;
  boltUntil: number = 0;
  patternSeed: number = 0;

  constructor(id: string) {
    this.id = id;
    this.def = weaponDef(id);
    this.mag = this.def.mag;
    this.reserve = this.def.reserve;
  }

  isReloading(): boolean {
    return this.reloadUntil > 0;
  }

  canReload(): boolean {
    const d = this.def;
    return d.type !== 'melee' && d.type !== 'grenade' && this.mag < d.mag && this.reserve > 0 && !this.isReloading();
  }

  finishReload(): void {
    const need = this.def.mag - this.mag;
    const take = Math.min(need, this.reserve);
    this.mag += take;
    this.reserve -= take;
    this.reloadUntil = 0;
  }

  refill(): void {
    this.mag = this.def.mag;
    this.reserve = this.def.reserve;
    this.reloadUntil = 0;
    this.boltUntil = 0;
  }
}

export interface SpreadState {
  speed: number;
  onGround: boolean;
  crouch: boolean;
  scoped: boolean;
  scopeReady: boolean;
}

/** 当前散布（弧度，锥半角） */
export function currentSpread(ws: WeaponState, st: SpreadState): number {
  const s = ws.def.spread;
  if (!s) {
    return 0;
  }
  let v = s.base;
  if (ws.def.type === 'sniper') {
    v = st.scoped && st.scopeReady ? s.scoped : s.base;
  }
  const sp = st.speed;
  v += s.move * Math.min(1, Math.max(0, (sp - 0.6) / 5.5));
  if (!st.onGround) {
    v += s.air;
  }
  v += ws.spreadAcc;
  if (st.crouch && st.onGround) {
    v *= s.crouch;
  }
  return Math.min(v, s.max + s.base + (st.onGround ? 0 : s.air));
}

/** 后坐力：返回本发的 [pitch, yaw] 增量（弧度） */
export function recoilKick(ws: WeaponState, rnd: () => number): number[] {
  const r = ws.def.recoil;
  if (!r) {
    return [0, 0];
  }
  const n = ws.shotsFired;
  const up = r.up * (n < 3 ? 1.25 : 1) * (0.85 + rnd() * 0.3);
  let side = 0;
  if (n >= r.sideStart) {
    const phase = Math.sin(n * 0.55 + (ws.patternSeed || 0));
    side = r.side * (phase * 1.3 + (rnd() - 0.5) * 0.9);
  } else {
    side = (rnd() - 0.5) * r.side * 0.4;
  }
  return [up, side];
}

/** 在锥内随机扰动方向（dir 已归一化，就地修改） */
export function jitterDir(dir: Vec3, spread: number, rnd: () => number): Vec3 {
  if (spread <= 0) {
    return dir;
  }
  // 构造与 dir 正交的基：u = dir × axis
  let ux: number, uy: number, uz: number;
  if (Math.abs(dir.x) < 0.9) {
    ux = 0; uy = dir.z; uz = -dir.y; // dir × (1,0,0)
  } else {
    ux = -dir.z; uy = 0; uz = dir.x; // dir × (0,1,0)
  }
  const ul = Math.hypot(ux, uy, uz);
  ux /= ul;
  uy /= ul;
  uz /= ul;
  const vx = dir.y * uz - dir.z * uy;
  const vy = dir.z * ux - dir.x * uz;
  const vz = dir.x * uy - dir.y * ux;
  const a = rnd() * Math.PI * 2;
  const r = Math.sqrt(rnd()) * spread;
  const ca = Math.cos(a) * r, sa = Math.sin(a) * r;
  dir.x += ux * ca + vx * sa;
  dir.y += uy * ca + vy * sa;
  dir.z += uz * ca + vz * sa;
  return dir.normalize();
}
