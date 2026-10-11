/**
 * 第三人称士兵：刚性蒙皮 + 程序动画 + 骨骼命中盒（移植自原版 character.js）。
 * 骨骼矩阵每帧在世界空间计算，送渲染层蒙皮绘制；命中测试在 ArkTS 侧完成。
 */
import { Mat4, Vec3, clamp } from './math3d';
import { Geom, VertexData, boxGeom, cylinderGeom, sphereGeom, capsuleGeom } from './geometry';

// 骨骼表：name, parent, x, y, z
export const BONES: string[][] = [
  ['hips', '-1', '0', '0.98', '0'], ['spine', '0', '0', '0.12', '0'], ['chest', '1', '0', '0.2', '0'],
  ['neck', '2', '0', '0.2', '0'], ['head', '3', '0', '0.08', '0'],
  ['shoulderR', '2', '0.17', '0.13', '0'], ['upperArmR', '5', '0.04', '0', '0'], ['forearmR', '6', '0', '-0.29', '0'],
  ['handR', '7', '0', '-0.26', '0'],
  ['shoulderL', '2', '-0.17', '0.13', '0'], ['upperArmL', '9', '-0.04', '0', '0'], ['forearmL', '10', '0', '-0.29', '0'],
  ['handL', '11', '0', '-0.26', '0'],
  ['thighR', '0', '0.1', '-0.05', '0'], ['shinR', '13', '0', '-0.44', '0'], ['footR', '14', '0', '-0.44', '0'],
  ['thighL', '0', '-0.1', '-0.05', '0'], ['shinL', '16', '0', '-0.44', '0'], ['footL', '17', '0', '-0.44', '0']
];

export const BI: Map<string, number> = new Map<string, number>();
for (let i = 0; i < BONES.length; i++) {
  BI.set(BONES[i][0], i);
}

function boneName(i: number): string {
  return BONES[i][0];
}

function boneParent(i: number): number {
  return parseInt(BONES[i][1]);
}

function boneBind(i: number): Vec3 {
  return new Vec3(parseFloat(BONES[i][2]), parseFloat(BONES[i][3]), parseFloat(BONES[i][4]));
}

// 绑定姿态的全局位置
const BIND_POS: Vec3[] = [];
for (let i = 0; i < BONES.length; i++) {
  const v = boneBind(i);
  const p = boneParent(i);
  if (p >= 0) {
    v.add(BIND_POS[p]);
  }
  BIND_POS.push(v);
}

function hexRGB(hex: number): number[] {
  return [((hex >> 16) & 0xff) / 255, ((hex >> 8) & 0xff) / 255, (hex & 0xff) / 255];
}

const OUTFIT: Map<string, Map<string, number[]>> = new Map<string, Map<string, number[]>>();
{
  const bl = new Map<string, number[]>();
  bl.set('pants', hexRGB(0x2c2d31));
  bl.set('jacket', hexRGB(0x1f2124));
  bl.set('vest', hexRGB(0x2e3128));
  bl.set('pouch', hexRGB(0x3a3d30));
  bl.set('boots', hexRGB(0x141414));
  bl.set('gloves', hexRGB(0x18181a));
  bl.set('skin', hexRGB(0xb88c6c));
  bl.set('mask', hexRGB(0x151618));
  bl.set('head', hexRGB(0x151618));
  bl.set('band', hexRGB(0xa3161a));
  bl.set('armband', hexRGB(0xb01c1c));
  bl.set('goggles', hexRGB(0x1a1a1a));
  bl.set('lens', hexRGB(0xd66a1a));
  bl.set('pads', hexRGB(0x222326));
  OUTFIT.set('BL', bl);
  const gr = new Map<string, number[]>();
  gr.set('pants', hexRGB(0x5e6b7c));
  gr.set('jacket', hexRGB(0x566478));
  gr.set('vest', hexRGB(0x27344a));
  gr.set('pouch', hexRGB(0x2e3c52));
  gr.set('boots', hexRGB(0x16161a));
  gr.set('gloves', hexRGB(0x1c1d20));
  gr.set('skin', hexRGB(0xc49a7a));
  gr.set('mask', hexRGB(0x202328));
  gr.set('head', hexRGB(0x33404f));
  gr.set('band', hexRGB(0x1a1a1a));
  gr.set('armband', hexRGB(0x1f62c8));
  gr.set('goggles', hexRGB(0x151515));
  gr.set('lens', hexRGB(0xe0c040));
  gr.set('pads', hexRGB(0x2a3340));
  OUTFIT.set('GR', gr);
}

class SkinBuilder {
  pos: number[] = [];
  nrm: number[] = [];
  uv: number[] = [];
  col: number[] = [];
  skin: number[] = [];
  idx: number[] = [];

  add(geo: Geom, bone: string, colorKey: string, team: string, x: number, y: number, z: number,
    rx: number = 0, ry: number = 0, rz: number = 0): void {
    const O = OUTFIT.get(team) as Map<string, number[]>;
    const color = O.get(colorKey) as number[];
    const bi = BI.get(bone) as number;
    const m = new Mat4().compose(new Vec3(x, y, z), rx, ry, rz);
    const mm = m.m;
    const base = this.pos.length / 3;
    for (let i = 0; i < geo.pos.length; i += 3) {
      const px = geo.pos[i], py = geo.pos[i + 1], pz = geo.pos[i + 2];
      this.pos.push(mm[0] * px + mm[4] * py + mm[8] * pz + mm[12],
        mm[1] * px + mm[5] * py + mm[9] * pz + mm[13],
        mm[2] * px + mm[6] * py + mm[10] * pz + mm[14]);
      const nx = geo.nrm[i], ny = geo.nrm[i + 1], nz = geo.nrm[i + 2];
      let vx = mm[0] * nx + mm[4] * ny + mm[8] * nz;
      let vy = mm[1] * nx + mm[5] * ny + mm[9] * nz;
      let vz = mm[2] * nx + mm[6] * ny + mm[10] * nz;
      const nl = Math.hypot(vx, vy, vz) || 1;
      this.nrm.push(vx / nl, vy / nl, vz / nl);
      this.uv.push(0.5, 0.5);
      this.col.push(color[0], color[1], color[2]);
      this.skin.push(bi);
    }
    for (const i of geo.idx) {
      this.idx.push(base + i);
    }
  }

  build(): VertexDataWithSkin {
    const n = this.pos.length / 3;
    const vdata = new Float32Array(n * 12);
    const skinIdx = new Uint16Array(n);
    for (let i = 0; i < n; i++) {
      const o = i * 12;
      vdata[o] = this.pos[i * 3];
      vdata[o + 1] = this.pos[i * 3 + 1];
      vdata[o + 2] = this.pos[i * 3 + 2];
      vdata[o + 3] = this.nrm[i * 3];
      vdata[o + 4] = this.nrm[i * 3 + 1];
      vdata[o + 5] = this.nrm[i * 3 + 2];
      vdata[o + 6] = this.uv[i * 2];
      vdata[o + 7] = this.uv[i * 2 + 1];
      vdata[o + 8] = this.col[i * 3];
      vdata[o + 9] = this.col[i * 3 + 1];
      vdata[o + 10] = this.col[i * 3 + 2];
      vdata[o + 11] = this.skin[i];
      skinIdx[i] = this.skin[i];
    }
    return new VertexDataWithSkin(vdata, new Uint32Array(this.idx), skinIdx);
  }
}

export class VertexDataWithSkin {
  vdata: Float32Array;
  idata: Uint32Array;
  skinIdx: Uint16Array;

  constructor(vdata: Float32Array, idata: Uint32Array, skinIdx: Uint16Array) {
    this.vdata = vdata;
    this.idata = idata;
    this.skinIdx = skinIdx;
  }
}

const GEO_CACHE: Map<string, VertexDataWithSkin> = new Map();

export function buildSoldierGeometry(team: string): VertexDataWithSkin {
  let cached = GEO_CACHE.get(team);
  if (cached) {
    return cached;
  }
  const g = new SkinBuilder();
  const P = (name: string): Vec3 => BIND_POS[BI.get(name) as number];
  // 腿
  for (const s of ['R', 'L']) {
    const sx = s === 'R' ? 1 : -1;
    const th = P('thigh' + s), sh = P('shin' + s), ft = P('foot' + s);
    g.add(capsuleGeom(0.085, 0.3, 2, 8), 'thigh' + s, 'pants', team, th.x, th.y - 0.2, th.z);
    g.add(capsuleGeom(0.068, 0.32, 2, 8), 'shin' + s, 'pants', team, sh.x, sh.y - 0.2, sh.z);
    g.add(boxGeom(0.12, 0.14, 0.1), 'shin' + s, 'pads', team, sh.x, sh.y - 0.02, sh.z - 0.06);
    g.add(boxGeom(0.12, 0.13, 0.27), 'foot' + s, 'boots', team, ft.x, ft.y + 0.03, ft.z - 0.05);
    g.add(boxGeom(0.11, 0.1, 0.14), 'shin' + s, 'boots', team, sh.x, sh.y - 0.38, sh.z);
    g.add(boxGeom(0.07, 0.1, 0.1), 'thigh' + s, 'pouch', team, th.x + sx * 0.08, th.y - 0.18, th.z);
  }
  // 躯干
  const hp = P('hips'), sp = P('spine'), ch = P('chest');
  g.add(boxGeom(0.36, 0.22, 0.24), 'hips', 'pants', team, hp.x, hp.y - 0.02, hp.z);
  g.add(boxGeom(0.38, 0.06, 0.26), 'hips', 'band', team, hp.x, hp.y + 0.08, hp.z);
  g.add(boxGeom(0.33, 0.22, 0.22), 'spine', 'jacket', team, sp.x, sp.y + 0.1, sp.z);
  g.add(boxGeom(0.4, 0.3, 0.25), 'chest', 'jacket', team, ch.x, ch.y + 0.1, ch.z);
  g.add(boxGeom(0.42, 0.34, 0.29), 'chest', 'vest', team, ch.x, ch.y + 0.06, ch.z);
  for (let i = 0; i < 3; i++) {
    g.add(boxGeom(0.085, 0.11, 0.05), 'chest', 'pouch', team, ch.x - 0.1 + i * 0.1, ch.y - 0.02, ch.z - 0.16);
  }
  g.add(boxGeom(0.3, 0.34, 0.12), 'chest', 'pouch', team, ch.x, ch.y + 0.05, ch.z + 0.19);
  g.add(boxGeom(0.03, 0.25, 0.03), 'chest', 'goggles', team, ch.x + 0.1, ch.y + 0.32, ch.z + 0.2);
  // 头
  const nk = P('neck'), hd = P('head');
  g.add(capsuleGeom(0.055, 0.06, 2, 8), 'neck', 'skin', team, nk.x, nk.y + 0.04, nk.z);
  const headG = sphereGeom(0.108, 10, 8);
  for (let i = 0; i < headG.pos.length; i += 3) {
    headG.pos[i] *= 0.95;
    headG.pos[i + 1] *= 1.12;
    headG.pos[i + 2] *= 1.02;
  }
  g.add(headG, 'head', 'skin', team, hd.x, hd.y + 0.09, hd.z);
  if (team === 'GR') {
    const helm = sphereGeom(0.128, 12, 6, 0, Math.PI * 0.55);
    for (let i = 0; i < helm.pos.length; i += 3) {
      helm.pos[i] *= 1;
      helm.pos[i + 1] *= 0.95;
      helm.pos[i + 2] *= 1.08;
    }
    g.add(helm, 'head', 'head', team, hd.x, hd.y + 0.12, hd.z + 0.005);
    g.add(boxGeom(0.23, 0.05, 0.05), 'head', 'goggles', team, hd.x, hd.y + 0.155, hd.z - 0.1);
    g.add(boxGeom(0.18, 0.035, 0.02), 'head', 'lens', team, hd.x, hd.y + 0.155, hd.z - 0.125);
    const mask = sphereGeom(0.1, 10, 6);
    for (let i = 0; i < mask.pos.length; i += 3) {
      mask.pos[i] *= 1;
      mask.pos[i + 1] *= 0.62;
      mask.pos[i + 2] *= 1.05;
    }
    g.add(mask, 'head', 'mask', team, hd.x, hd.y + 0.035, hd.z - 0.02);
  } else {
    const hood = sphereGeom(0.114, 10, 8);
    for (let i = 0; i < hood.pos.length; i += 3) {
      hood.pos[i] *= 0.98;
      hood.pos[i + 1] *= 1.1;
      hood.pos[i + 2] *= 1.05;
    }
    g.add(hood, 'head', 'mask', team, hd.x, hd.y + 0.1, hd.z + 0.008);
    g.add(boxGeom(0.16, 0.035, 0.03), 'head', 'skin', team, hd.x, hd.y + 0.12, hd.z - 0.105);
    g.add(boxGeom(0.24, 0.035, 0.235), 'head', 'band', team, hd.x, hd.y + 0.185, hd.z);
    g.add(boxGeom(0.07, 0.022, 0.02), 'head', 'goggles', team, hd.x - 0.04, hd.y + 0.12, hd.z - 0.118);
    g.add(boxGeom(0.07, 0.022, 0.02), 'head', 'goggles', team, hd.x + 0.04, hd.y + 0.12, hd.z - 0.118);
  }
  // 手臂
  for (const s of ['R', 'L']) {
    const ua = P('upperArm' + s), fa = P('forearm' + s), hn = P('hand' + s);
    g.add(sphereGeom(0.085, 8, 6), 'upperArm' + s, 'jacket', team, ua.x, ua.y - 0.02, ua.z);
    g.add(capsuleGeom(0.062, 0.2, 2, 8), 'upperArm' + s, 'jacket', team, ua.x, ua.y - 0.15, ua.z);
    g.add(capsuleGeom(0.066, 0.05, 2, 8), 'upperArm' + s, 'armband', team, ua.x, ua.y - 0.12, ua.z);
    g.add(capsuleGeom(0.052, 0.19, 2, 8), 'forearm' + s, 'jacket', team, fa.x, fa.y - 0.13, fa.z);
    g.add(boxGeom(0.075, 0.1, 0.05), 'hand' + s, 'gloves', team, hn.x, hn.y - 0.04, hn.z);
  }
  cached = g.build();
  GEO_CACHE.set(team, cached);
  return cached;
}

// 命中盒：bone, cx, cy, cz, hx, hy, hz, part
export interface HitBox {
  bone: number;
  cx: number;
  cy: number;
  cz: number;
  hx: number;
  hy: number;
  hz: number;
  part: string;
}

export const HITBOXES: HitBox[] = [
  { bone: BI.get('head') as number, cx: 0, cy: 0.1, cz: 0, hx: 0.1, hy: 0.12, hz: 0.11, part: 'head' },
  { bone: BI.get('chest') as number, cx: 0, cy: 0.1, cz: 0, hx: 0.21, hy: 0.18, hz: 0.145, part: 'chest' },
  { bone: BI.get('spine') as number, cx: 0, cy: 0.09, cz: 0, hx: 0.17, hy: 0.12, hz: 0.12, part: 'stomach' },
  { bone: BI.get('hips') as number, cx: 0, cy: -0.02, cz: 0, hx: 0.18, hy: 0.11, hz: 0.13, part: 'stomach' },
  { bone: BI.get('upperArmR') as number, cx: 0, cy: -0.14, cz: 0, hx: 0.065, hy: 0.16, hz: 0.065, part: 'arm' },
  { bone: BI.get('upperArmL') as number, cx: 0, cy: -0.14, cz: 0, hx: 0.065, hy: 0.16, hz: 0.065, part: 'arm' },
  { bone: BI.get('forearmR') as number, cx: 0, cy: -0.13, cz: 0, hx: 0.055, hy: 0.15, hz: 0.055, part: 'arm' },
  { bone: BI.get('forearmL') as number, cx: 0, cy: -0.13, cz: 0, hx: 0.055, hy: 0.15, hz: 0.055, part: 'arm' },
  { bone: BI.get('thighR') as number, cx: 0, cy: -0.21, cz: 0, hx: 0.09, hy: 0.24, hz: 0.09, part: 'leg' },
  { bone: BI.get('thighL') as number, cx: 0, cy: -0.21, cz: 0, hx: 0.09, hy: 0.24, hz: 0.09, part: 'leg' },
  { bone: BI.get('shinR') as number, cx: 0, cy: -0.22, cz: 0, hx: 0.07, hy: 0.24, hz: 0.075, part: 'leg' },
  { bone: BI.get('shinL') as number, cx: 0, cy: -0.22, cz: 0, hx: 0.07, hy: 0.24, hz: 0.075, part: 'leg' }
];

export interface SoldierAnimState {
  speed: number;
  fwd: number;
  crouch: boolean;
  pitch: number;
  onGround: boolean;
  reloading: boolean;
}

const NB = BONES.length; // 19

export class Soldier {
  team: string;
  // 动画状态（骨骼局部旋转/偏移）
  rot: Float32Array;    // 19*3 欧拉
  posOff: Float32Array; // 19*3 位置偏移（hips 用）
  world: Mat4[] = [];
  skin: Mat4[] = [];
  phase: number;
  crouchK: number = 0;
  amp: number = 0;
  deadT: number = -1;
  fallDir: number = 1;
  fallSide: number = 0;
  fallSpeed: number = 1;
  limbR: number[] = [0, 0, 0, 0];
  recoilK: number = 0;
  gunId: string = '';
  gunLocal: Mat4 = new Mat4();
  invFrame: number = -1;
  hitInv: Mat4[] = [];

  constructor(team: string) {
    this.team = team;
    this.rot = new Float32Array(NB * 3);
    this.posOff = new Float32Array(NB * 3);
    this.phase = Math.random() * 10;
    for (let i = 0; i < NB; i++) {
      this.world.push(new Mat4());
      this.skin.push(new Mat4());
      this.hitInv.push(new Mat4());
    }
  }

  setWeapon(id: string): void {
    this.gunId = id;
  }

  /** 计算所有骨骼的皮肤矩阵（世界空间）。pos/yaw 为角色位置朝向 */
  computeBones(pos: Vec3, yaw: number): void {
    this.lastYaw = yaw;
    const root = this.rootM.identity().compose(pos, 0, yaw, 0);
    if (this.deadT >= 0) {
      // 倒地：整体绕根旋转
      const t = Math.min(1, this.deadT * 1.6 * this.fallSpeed);
      const e = t * t;
      const ang = e * Math.PI * 0.5 * 0.96;
      const fall = this.fallM.identity().compose(new Vec3(0, 0, 0), -this.fallDir * ang, 0, this.fallSide * e);
      root.multiply(fall);
    }
    const bindT = this.bindT;
    const local = this.localM;
    for (let i = 0; i < NB; i++) {
      const bp = BIND_POS[i];
      bindT.compose(new Vec3(bp.x + this.posOff[i * 3], bp.y + this.posOff[i * 3 + 1], bp.z + this.posOff[i * 3 + 2]),
        this.rot[i * 3], this.rot[i * 3 + 1], this.rot[i * 3 + 2]);
      const p = boneParent(i);
      if (p >= 0) {
        local.copyFrom(this.world[p]);
        local.multiply(bindT);
        this.world[i].copyFrom(local);
      } else {
        this.world[i].copyFrom(root);
        this.world[i].multiply(bindT);
      }
      // skin = world × bindInv，bindInv = T(-bindPos)（先平移后旋转到世界）
      const w = this.world[i].m;
      const sm = this.skin[i].m;
      sm.set(w);
      // 平移分量 = w_trans - R·bp
      sm[12] = w[12] - (w[0] * bp.x + w[4] * bp.y + w[8] * bp.z);
      sm[13] = w[13] - (w[1] * bp.x + w[5] * bp.y + w[9] * bp.z);
      sm[14] = w[14] - (w[2] * bp.x + w[6] * bp.y + w[10] * bp.z);
    }
  }

  private rootM: Mat4 = new Mat4();
  private fallM: Mat4 = new Mat4();
  private bindT: Mat4 = new Mat4();
  private localM: Mat4 = new Mat4();
  private tmpM: Mat4 = new Mat4();

  /** st: 动画输入（与原版 update 一致） */
  update(dt: number, st: SoldierAnimState | null, pos: Vec3, yaw: number): void {
    if (this.deadT >= 0) {
      this.updateDeath(dt);
      this.computeBones(pos, yaw);
      this.updateGunLocal();
      return;
    }
    const cr = st !== null ? (st.crouch ? 1 : 0) : 0;
    this.crouchK += (cr - this.crouchK) * Math.min(1, dt * 10);
    const ck = this.crouchK;
    const sp = st !== null ? st.speed : 0;
    const moving = sp > 0.3 && st !== null && st.onGround;
    this.phase += dt * (moving ? 2.2 + sp * 1.15 : 0) * (ck > 0.5 ? 0.7 : 1);
    const amp = moving ? Math.min(1, sp / 5) : 0;
    this.amp += (amp - this.amp) * Math.min(1, dt * 8);
    const A = this.amp;
    const ph = this.phase;
    const fwd = st !== null ? (st.fwd < -0.3 ? -1 : 1) : 1;
    // 腿
    const swing = Math.sin(ph) * 0.62 * A * fwd;
    const bendR = Math.max(0, Math.sin(ph + Math.PI * 0.5 * fwd)) * 1.0 * A;
    const bendL = Math.max(0, Math.sin(ph + Math.PI + Math.PI * 0.5 * fwd)) * 1.0 * A;
    let thR = swing, thL = -swing, shR = -bendR, shL = -bendL;
    thR = thR * (1 - ck) + (1.25 + swing * 0.3) * ck;
    thL = thL * (1 - ck) + (0.55 - swing * 0.3) * ck;
    shR = shR * (1 - ck) + -1.9 * ck;
    shL = shL * (1 - ck) + (-1.2 + Math.min(0, -swing)) * ck;
    const onG = st !== null ? st.onGround : true;
    if (!onG) {
      thR = 0.7;
      thL = 0.25;
      shR = -1.1;
      shL = -0.6;
    }
    this.setRot('thighR', thR, 0, 0.02);
    this.setRot('thighL', thL, 0, -0.02);
    this.setRot('shinR', shR, 0, 0);
    this.setRot('shinL', shL, 0, 0);
    let ftR = -thR - shR;
    let ftL = -thL - shL;
    if (ck > 0.01) {
      ftL = 0.5 * ck + ftL * (1 - ck);
    }
    this.setRot('footR', ftR, 0, 0);
    this.setRot('footL', ftL, 0, 0);
    // 髋部
    const bob = moving ? Math.abs(Math.cos(ph)) * 0.035 * A : 0;
    const hipsY = 0.98 - ck * 0.38 - bob + (onG ? 0 : 0.02);
    const hipsZ = ck * 0.08;
    const hipsIdx = (BI.get('hips') as number) * 3;
    this.posOff[hipsIdx] = 0;
    this.posOff[hipsIdx + 1] = hipsY - 0.98;
    this.posOff[hipsIdx + 2] = hipsZ;
    this.setRot('hips', 0, Math.sin(ph) * 0.08 * A, 0);
    // 上身
    const pitch = clamp(st !== null ? st.pitch : 0, -1.2, 1.2);
    this.setRot('spine', pitch * 0.3 + ck * 0.15, -Math.sin(ph) * 0.08 * A - 0.25, 0);
    this.setRot('chest', pitch * 0.45 - this.recoilK * 0.08, -0.12, 0);
    this.setRot('neck', pitch * 0.2, 0.3, 0);
    this.setRot('head', 0, 0.05, 0);
    this.recoilK *= Math.exp(-dt * 12);
    // 手臂：持枪姿势（右手前伸握把、左手托护木）
    this.poseArms();
    this.computeBones(pos, yaw);
    this.updateGunLocal();
  }

  private poseArms(): void {
    // 上臂朝前下方，前臂上抬（持枪姿态近似）
    this.setRot('upperArmR', 0.55, 0, -0.5);
    this.setRot('forearmR', -1.15, 0.25, 0);
    this.setRot('upperArmL', 0.35, -0.55, 0.75);
    this.setRot('forearmL', -1.35, -0.5, 0);
    this.setRot('handR', 0, 0, 0);
    this.setRot('handL', 0, 0, 0);
    this.setRot('shoulderR', 0, 0, 0);
    this.setRot('shoulderL', 0, 0, 0);
  }

  private setRot(name: string, x: number, y: number, z: number): void {
    const i = (BI.get(name) as number) * 3;
    this.rot[i] = x;
    this.rot[i + 1] = y;
    this.rot[i + 2] = z;
  }

  /** 第三人称枪相对胸骨的局部变换（原版 gun.position/rotation） */
  private updateGunLocal(): void {
    const pistol = this.gunId === 'deagle';
    const knife = this.gunId === 'knife' || this.gunId === 'he';
    if (knife) {
      this.gunLocal.compose(new Vec3(0.18, 0.02, -0.28), -0.3, 0.37, 0);
    } else {
      const gx = pistol ? 0.03 : 0.1;
      const gy = pistol ? 0.14 : 0.1;
      const gz = pistol ? -0.42 : -0.3;
      this.gunLocal.compose(new Vec3(gx, gy, gz), 0, 0.37, 0);
    }
  }

  /** 第三人称枪的世界矩阵 */
  gunWorld(out: Mat4): Mat4 {
    out.copyFrom(this.world[BI.get('chest') as number]);
    out.multiply(this.gunLocal);
    return out;
  }

  kick(): void {
    this.recoilK = 1;
  }

  die(dirX: number, dirZ: number, headshot: boolean): void {
    this.deadT = 0;
    const yaw = 0; // fallDir 由子弹方向决定
    void yaw;
    // 朝向：fwd = (-sin(rootYaw), 0, -cos(rootYaw))；这里近似用世界 -Z
    const fwdX = -Math.sin(this.lastYaw), fwdZ = -Math.cos(this.lastYaw);
    const dot = fwdX * dirX + fwdZ * dirZ;
    this.fallDir = dot > 0 ? 1 : -1;
    this.fallSide = (Math.random() - 0.5) * 0.8;
    this.fallSpeed = headshot ? 1.4 : 1;
    this.limbR = [Math.random(), Math.random(), Math.random(), Math.random()];
  }

  lastYaw: number = 0;

  private updateDeath(dt: number): void {
    this.deadT += dt;
    const t = Math.min(1, this.deadT * 1.6 * this.fallSpeed);
    // 肢体松弛
    const r = this.limbR;
    const k = Math.min(1, this.deadT * 3);
    const uAR = (BI.get('upperArmR') as number) * 3;
    const uAL = (BI.get('upperArmL') as number) * 3;
    this.rot[uAR] += ((r[0] * 2 - 1) * 1.5 - this.rot[uAR]) * k * 0.2;
    this.rot[uAL] += ((r[1] * 2 - 1) * 1.5 - this.rot[uAL]) * k * 0.2;
    const fR = (BI.get('forearmR') as number) * 3;
    const fL = (BI.get('forearmL') as number) * 3;
    this.rot[fR] = 0.3 * r[2];
    this.rot[fL] = 0.4 * r[3];
    const thR = (BI.get('thighR') as number) * 3;
    const thL = (BI.get('thighL') as number) * 3;
    this.rot[thR] *= 0.9;
    this.rot[thL] += (0.4 * r[2] - this.rot[thL]) * 0.1;
    const sR = (BI.get('shinR') as number) * 3;
    const sL = (BI.get('shinL') as number) * 3;
    this.rot[sR] *= 0.9;
    this.rot[sL] *= 0.9;
    const sp = (BI.get('spine') as number) * 3;
    const ch = (BI.get('chest') as number) * 3;
    const nk = (BI.get('neck') as number) * 3;
    this.rot[sp] *= 0.9;
    this.rot[ch] *= 0.9;
    this.rot[nk] += (0.3 * this.fallDir - this.rot[nk]) * 0.1;
    // 髋部下沉
    const hp = (BI.get('hips') as number) * 3 + 1;
    const sink = -Math.sin(t * Math.PI) * 0.25 - t * 0.3;
    this.posOff[hp] = sink;
    void t;
  }

  reset(): void {
    this.deadT = -1;
    this.rot.fill(0);
    this.posOff.fill(0);
    this.crouchK = 0;
    this.amp = 0;
    this.recoilK = 0;
  }

  private hitWorld: Mat4 = new Mat4();
  private hitLocalT: Mat4 = new Mat4();

  private ensureHitInv(frame: number): void {
    if (this.invFrame === frame) {
      return;
    }
    for (let i = 0; i < HITBOXES.length; i++) {
      const h = HITBOXES[i];
      this.hitLocalT.compose(new Vec3(h.cx, h.cy, h.cz), 0, 0, 0);
      this.hitWorld.copyFrom(this.world[h.bone]);
      this.hitWorld.multiply(this.hitLocalT);
      this.hitInv[i].copyFrom(this.hitWorld);
      this.hitInv[i].invert();
    }
    this.invFrame = frame;
  }

  /** 射线命中测试：返回 [t, part] 或 null */
  hitTest(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number, maxT: number,
    frame: number): HitResult | null {
    // 粗检：到髋部
    const hip = this.world[BI.get('hips') as number].m;
    const hx = hip[12], hy = hip[13] + 0.3, hz = hip[14];
    const wx = hx - ox, wy = hy - oy, wz = hz - oz;
    const tc = wx * dx + wy * dy + wz * dz;
    if (tc < -1.5 || tc > maxT + 1.5) {
      return null;
    }
    const px = wx - dx * tc, py = wy - dy * tc, pz = wz - dz * tc;
    if (px * px + py * py + pz * pz > 1.6) {
      return null;
    }
    this.ensureHitInv(frame);
    let best = maxT;
    let part: string | null = null;
    for (let i = 0; i < HITBOXES.length; i++) {
      const h = HITBOXES[i];
      const inv = this.hitInv[i].m;
      // 射线变换到命中盒局部
      const lox = inv[0] * ox + inv[4] * oy + inv[8] * oz + inv[12] - h.cx;
      const loy = inv[1] * ox + inv[5] * oy + inv[9] * oz + inv[13] - h.cy;
      const loz = inv[2] * ox + inv[6] * oy + inv[10] * oz + inv[14] - h.cz;
      const ldx = inv[0] * dx + inv[4] * dy + inv[8] * dz;
      const ldy = inv[1] * dx + inv[5] * dy + inv[9] * dz;
      const ldz = inv[2] * dx + inv[6] * dy + inv[10] * dz;
      let tmin = 0, tmax = best;
      let ok = true;
      // 三轴 slab
      if (Math.abs(ldx) < 1e-9) {
        if (lox < -h.hx || lox > h.hx) {
          ok = false;
        }
      } else {
        let t1 = (-h.hx - lox) / ldx, t2 = (h.hx - lox) / ldx;
        if (t1 > t2) {
          const t = t1;
          t1 = t2;
          t2 = t;
        }
        if (t1 > tmin) {
          tmin = t1;
        }
        if (t2 < tmax) {
          tmax = t2;
        }
        if (tmin > tmax) {
          ok = false;
        }
      }
      if (ok && Math.abs(ldy) < 1e-9) {
        if (loy < -h.hy || loy > h.hy) {
          ok = false;
        }
      } else if (ok) {
        let t1 = (-h.hy - loy) / ldy, t2 = (h.hy - loy) / ldy;
        if (t1 > t2) {
          const t = t1;
          t1 = t2;
          t2 = t;
        }
        if (t1 > tmin) {
          tmin = t1;
        }
        if (t2 < tmax) {
          tmax = t2;
        }
        if (tmin > tmax) {
          ok = false;
        }
      }
      if (ok && Math.abs(ldz) < 1e-9) {
        if (loz < -h.hz || loz > h.hz) {
          ok = false;
        }
      } else if (ok) {
        let t1 = (-h.hz - loz) / ldz, t2 = (h.hz - loz) / ldz;
        if (t1 > t2) {
          const t = t1;
          t1 = t2;
          t2 = t;
        }
        if (t1 > tmin) {
          tmin = t1;
        }
        if (t2 < tmax) {
          tmax = t2;
        }
        if (tmin > tmax) {
          ok = false;
        }
      }
      if (ok && tmin < best) {
        best = tmin;
        part = h.part;
      }
    }
    return part !== null ? new HitResult(best, part) : null;
  }

  headWorld(out: Vec3): Vec3 {
    return bonePoint(this.world[BI.get('head') as number], 0, 0.1, 0, out);
  }

  chestWorld(out: Vec3): Vec3 {
    return bonePoint(this.world[BI.get('chest') as number], 0, 0.1, 0, out);
  }
}

export class HitResult {
  t: number;
  part: string;

  constructor(t: number, part: string) {
    this.t = t;
    this.part = part;
  }
}

function bonePoint(m: Mat4, x: number, y: number, z: number, out: Vec3): Vec3 {
  const mm = m.m;
  out.x = mm[0] * x + mm[4] * y + mm[8] * z + mm[12];
  out.y = mm[1] * x + mm[5] * y + mm[9] * z + mm[13];
  out.z = mm[2] * x + mm[6] * y + mm[10] * z + mm[14];
  return out;
}

void cylinderGeom;
void boneName;
