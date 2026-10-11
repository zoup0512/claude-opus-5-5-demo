/**
 * 枪械模型：程序化构建（移植自原版 guns.js）。
 * 局部坐标：枪口朝 -Z，上 +Y，右 +X，原点在握把上方。
 * 材质以顶点色烘焙（metal/black/steel/wood/bakelite/olive/tan/rubber/brass/blade）。
 */
import { Mat4, Vec3 } from './math3d';
import { Geom, VertexData, boxGeom, cylinderGeom, sphereGeom, capsuleGeom } from './geometry';

export class GunModel {
  vd: VertexData;
  muzzle: Vec3;
  grip: Vec3;
  fore: Vec3;

  constructor(vd: VertexData, muzzle: Vec3, grip: Vec3, fore: Vec3) {
    this.vd = vd;
    this.muzzle = muzzle;
    this.grip = grip;
    this.fore = fore;
  }
}

// 材质颜色（0..1 线性近似）
const C_METAL: number[] = [0.12, 0.12, 0.13];
const C_BLACK: number[] = [0.06, 0.06, 0.07];
const C_STEEL: number[] = [0.42, 0.44, 0.47];
const C_WOOD: number[] = [0.32, 0.17, 0.08];
const C_BAKELITE: number[] = [0.26, 0.11, 0.05];
const C_OLIVE: number[] = [0.18, 0.21, 0.12];
const C_TAN: number[] = [0.38, 0.32, 0.22];
const C_RUBBER: number[] = [0.04, 0.04, 0.04];
const C_BRASS: number[] = [0.55, 0.42, 0.18];
const C_BLADE: number[] = [0.55, 0.57, 0.6];
const C_GLASS: number[] = [0.02, 0.08, 0.12];
const C_RED: number[] = [0.35, 0.06, 0.05];

const _t = new Vec3();
const _m1 = new Mat4();
const _m2 = new Mat4();

class GunBuilder {
  pos: number[] = [];
  nrm: number[] = [];
  uv: number[] = [];
  col: number[] = [];
  idx: number[] = [];
  muzzle: Vec3 = new Vec3(0, 0, -0.5);
  grip: Vec3 = new Vec3(0, -0.035, 0.03);
  fore: Vec3 = new Vec3(0, 0, -0.29);

  addPart(geo: Geom, preRot: Mat4 | null, color: number[], x: number, y: number, z: number,
    rx: number = 0, ry: number = 0, rz: number = 0): void {
    _m1.compose(_t.set(x, y, z), rx, ry, rz);
    if (preRot !== null) {
      _m1.multiply(preRot);
    }
    const m = _m1.m;
    const base = this.pos.length / 3;
    const rotateOnly = _m2.copyFrom(_m1);
    const mm = rotateOnly.m;
    mm[12] = 0;
    mm[13] = 0;
    mm[14] = 0;
    const rm = mm;
    for (let i = 0; i < geo.pos.length; i += 3) {
      const px = geo.pos[i], py = geo.pos[i + 1], pz = geo.pos[i + 2];
      this.pos.push(m[0] * px + m[4] * py + m[8] * pz + m[12],
        m[1] * px + m[5] * py + m[9] * pz + m[13],
        m[2] * px + m[6] * py + m[10] * pz + m[14]);
      const nx = geo.nrm[i], ny = geo.nrm[i + 1], nz = geo.nrm[i + 2];
      let vx = rm[0] * nx + rm[4] * ny + rm[8] * nz;
      let vy = rm[1] * nx + rm[5] * ny + rm[9] * nz;
      let vz = rm[2] * nx + rm[6] * ny + rm[10] * nz;
      const nl = Math.hypot(vx, vy, vz) || 1;
      vx /= nl;
      vy /= nl;
      vz /= nl;
      this.nrm.push(vx, vy, vz);
      this.col.push(color[0], color[1], color[2]);
    }
    for (let i = 0; i < geo.uv.length; i++) {
      this.uv.push(geo.uv[i]);
    }
    for (const i of geo.idx) {
      this.idx.push(base + i);
    }
  }

  build(): VertexData {
    const n = this.pos.length / 3;
    const vdata = new Float32Array(n * 11);
    for (let i = 0; i < n; i++) {
      const o = i * 11;
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
    }
    return new VertexData(vdata, new Uint32Array(this.idx));
  }
}

// 预旋转：圆柱轴向
function rotX90(): Mat4 {
  const m = new Mat4();
  m.compose(new Vec3(0, 0, 0), Math.PI / 2, 0, 0);
  return m;
}

function rotZ90(): Mat4 {
  const m = new Mat4();
  m.compose(new Vec3(0, 0, 0), 0, 0, Math.PI / 2);
  return m;
}

const PRE_X90 = rotX90();
const PRE_Z90 = rotZ90();

// 几何快捷方式
function RB(w: number, h: number, d: number): Geom {
  return boxGeom(w, h, d);
}

function CZ(r: number, len: number, seg: number = 12, r2: number = -1): Geom {
  return cylinderGeom(r2 >= 0 ? r2 : r, r, len, seg, true);
}

function CX(r: number, len: number, seg: number = 10): Geom {
  return cylinderGeom(r, r, len, seg, true);
}

function curvedMag(g: GunBuilder, segs: number, x0: number, y0: number, z0: number, w: number, segH: number,
  segD: number, curve: number): void {
  let y = 0, z = 0, a = 0;
  for (let i = 0; i < segs; i++) {
    g.addPart(RB(w, segH + 0.004, segD), null, C_BAKELITE, x0, y0 + y - segH / 2, z0 + z, -a, 0, 0);
    y -= Math.cos(a) * segH;
    z -= Math.sin(a) * segH;
    a += curve;
  }
  g.addPart(RB(w + 0.004, 0.012, segD + 0.006), null, C_BAKELITE, x0, y0 + y - 0.004, z0 + z, -a + curve, 0, 0);
}

function buildAK47(): GunBuilder {
  const g = new GunBuilder();
  g.addPart(RB(0.046, 0.058, 0.25), null, C_METAL, 0, 0.035, -0.05);
  g.addPart(RB(0.043, 0.022, 0.21), null, C_METAL, 0, 0.07, -0.03);
  g.addPart(RB(0.03, 0.02, 0.05), null, C_METAL, 0, 0.08, -0.175);
  g.addPart(RB(0.052, 0.046, 0.2), null, C_WOOD, 0, 0.022, -0.275);
  g.addPart(CZ(0.019, 0.17, 12), PRE_X90, C_WOOD, 0, 0.066, -0.26);
  g.addPart(CZ(0.0085, 0.3, 8), PRE_X90, C_METAL, 0, 0.042, -0.47);
  g.addPart(CZ(0.006, 0.26, 8), PRE_X90, C_METAL, 0, 0.066, -0.43);
  g.addPart(RB(0.02, 0.038, 0.022), null, C_METAL, 0, 0.066, -0.55);
  g.addPart(RB(0.004, 0.02, 0.004), null, C_METAL, 0, 0.093, -0.55);
  g.addPart(CZ(0.013, 0.05, 8), PRE_X90, C_METAL, 0, 0.042, -0.63);
  g.addPart(RB(0.03, 0.012, 0.03), null, C_METAL, 0, 0.018, -0.39);
  curvedMag(g, 5, 0, 0.005, -0.1, 0.03, 0.045, 0.07, 0.11);
  g.addPart(RB(0.03, 0.1, 0.042), null, C_BAKELITE, 0, -0.045, 0.035, 0.32);
  g.addPart(RB(0.006, 0.006, 0.06), null, C_METAL, 0, -0.012, -0.015);
  g.addPart(RB(0.004, 0.03, 0.004), null, C_METAL, 0, -0.018, -0.03);
  g.addPart(RB(0.042, 0.068, 0.27), null, C_WOOD, 0, 0.004, 0.2, -0.1);
  g.addPart(RB(0.044, 0.1, 0.012), null, C_METAL, 0, -0.012, 0.335);
  g.addPart(CX(0.006, 0.03), PRE_Z90, C_STEEL, 0.034, 0.06, -0.08);
  g.muzzle = new Vec3(0, 0.042, -0.66);
  g.grip = new Vec3(0, -0.035, 0.03);
  g.fore = new Vec3(0, 0, -0.29);
  return g;
}

function buildM4A1(): GunBuilder {
  const g = new GunBuilder();
  g.addPart(RB(0.042, 0.05, 0.23), null, C_BLACK, 0, 0.05, -0.04);
  g.addPart(RB(0.022, 0.01, 0.22), null, C_METAL, 0, 0.08, -0.05);
  for (let i = 0; i < 11; i++) {
    g.addPart(RB(0.026, 0.004, 0.008), null, C_METAL, 0, 0.087, -0.15 + i * 0.02);
  }
  g.addPart(RB(0.03, 0.03, 0.045), null, C_BLACK, 0, 0.1, 0.03);
  g.addPart(RB(0.004, 0.012, 0.004), null, C_METAL, 0, 0.12, 0.035);
  g.addPart(RB(0.036, 0.05, 0.17), null, C_BLACK, 0, 0.005, -0.02);
  g.addPart(RB(0.036, 0.05, 0.06), null, C_BLACK, 0, -0.03, -0.085);
  g.addPart(CZ(0.026, 0.21, 12), PRE_X90, C_BLACK, 0, 0.046, -0.28);
  for (let i = 0; i < 6; i++) {
    g.addPart(CZ(0.0265, 0.006, 12), PRE_X90, C_METAL, 0, 0.046, -0.2 - i * 0.032);
  }
  g.addPart(CZ(0.008, 0.22, 8), PRE_X90, C_METAL, 0, 0.046, -0.48);
  g.addPart(RB(0.018, 0.055, 0.018), null, C_BLACK, 0, 0.068, -0.41);
  g.addPart(RB(0.004, 0.02, 0.004), null, C_METAL, 0, 0.105, -0.41);
  g.addPart(CZ(0.011, 0.05, 8), PRE_X90, C_METAL, 0, 0.046, -0.6);
  curvedMagM(g, 4, 0, -0.04, -0.085, 0.028, 0.045, 0.062, 0.06);
  g.addPart(RB(0.028, 0.09, 0.036), null, C_BLACK, 0, -0.04, 0.035, 0.38);
  g.addPart(CZ(0.016, 0.17, 10), PRE_X90, C_BLACK, 0, 0.046, 0.145);
  g.addPart(RB(0.042, 0.075, 0.1), null, C_BLACK, 0, 0.03, 0.235);
  g.addPart(RB(0.03, 0.01, 0.02), null, C_BLACK, 0, 0.078, 0.07);
  g.addPart(RB(0.002, 0.03, 0.05), null, C_BLACK, 0.022, 0.05, -0.04);
  g.muzzle = new Vec3(0, 0.046, -0.63);
  g.grip = new Vec3(0, -0.035, 0.035);
  g.fore = new Vec3(0, 0.02, -0.28);
  return g;
}

function curvedMagM(g: GunBuilder, segs: number, x0: number, y0: number, z0: number, w: number, segH: number,
  segD: number, curve: number): void {
  let y = 0, z = 0, a = 0;
  for (let i = 0; i < segs; i++) {
    g.addPart(RB(w, segH + 0.004, segD), null, C_METAL, x0, y0 + y - segH / 2, z0 + z, -a, 0, 0);
    y -= Math.cos(a) * segH;
    z -= Math.sin(a) * segH;
    a += curve;
  }
  g.addPart(RB(w + 0.004, 0.012, segD + 0.006), null, C_METAL, x0, y0 + y - 0.004, z0 + z, -a + curve, 0, 0);
}

function buildAWM(): GunBuilder {
  const g = new GunBuilder();
  g.addPart(RB(0.055, 0.075, 0.46), null, C_OLIVE, 0, 0.004, -0.02);
  g.addPart(RB(0.05, 0.05, 0.22), null, C_OLIVE, 0, -0.005, -0.33);
  g.addPart(CZ(0.022, 0.24, 12), PRE_X90, C_METAL, 0, 0.05, -0.08);
  g.addPart(CZ(0.013, 0.56, 10), PRE_X90, C_METAL, 0, 0.05, -0.5);
  g.addPart(RB(0.036, 0.032, 0.07), null, C_METAL, 0, 0.05, -0.8);
  // 瞄准镜
  g.addPart(CZ(0.018, 0.3, 12), PRE_X90, C_BLACK, 0, 0.118, -0.07);
  g.addPart(CZ(0.03, 0.09, 14, 0.019), PRE_X90, C_BLACK, 0, 0.118, -0.25);
  g.addPart(CZ(0.025, 0.06, 14), PRE_X90, C_BLACK, 0, 0.118, 0.1);
  g.addPart(CZ(0.027, 0.002, 14), PRE_X90, C_GLASS, 0, 0.118, -0.296);
  g.addPart(CZ(0.011, 0.035, 8), PRE_X90, C_BLACK, 0, 0.145, -0.07);
  g.addPart(CX(0.011, 0.035, 8), PRE_Z90, C_BLACK, 0.028, 0.118, -0.07);
  g.addPart(RB(0.03, 0.04, 0.022), null, C_METAL, 0, 0.088, -0.14);
  g.addPart(RB(0.03, 0.04, 0.022), null, C_METAL, 0, 0.088, 0);
  g.addPart(RB(0.034, 0.06, 0.085), null, C_METAL, 0, -0.065, -0.07);
  g.addPart(RB(0.035, 0.1, 0.045), null, C_OLIVE, 0, -0.07, 0.08, 0.3);
  g.addPart(RB(0.05, 0.16, 0.045), null, C_OLIVE, 0, -0.02, 0.3);
  g.addPart(RB(0.04, 0.04, 0.18), null, C_OLIVE, 0, 0.05, 0.22);
  g.addPart(RB(0.052, 0.17, 0.014), null, C_RUBBER, 0, -0.02, 0.33);
  g.addPart(CZ(0.004, 0.2, 6), PRE_X90, C_BLACK, -0.012, -0.035, -0.4);
  g.addPart(CZ(0.004, 0.2, 6), PRE_X90, C_BLACK, 0.012, -0.035, -0.4);
  g.muzzle = new Vec3(0, 0.05, -0.84);
  g.grip = new Vec3(0, -0.05, 0.075);
  g.fore = new Vec3(0, -0.02, -0.3);
  return g;
}

function buildMP5(): GunBuilder {
  const g = new GunBuilder();
  g.addPart(RB(0.042, 0.06, 0.32), null, C_BLACK, 0, 0.042, -0.09);
  g.addPart(RB(0.046, 0.05, 0.15), null, C_BLACK, 0, 0.02, -0.31);
  g.addPart(CZ(0.009, 0.08, 8), PRE_X90, C_METAL, 0, 0.046, -0.41);
  g.addPart(CZ(0.012, 0.02, 8), PRE_X90, C_METAL, 0, 0.046, -0.45);
  g.addPart(CZ(0.014, 0.024, 8), PRE_X90, C_BLACK, 0, 0.085, 0.02);
  g.addPart(RB(0.024, 0.03, 0.02), null, C_BLACK, 0, 0.083, -0.38);
  g.addPart(CZ(0.009, 0.14, 8), PRE_X90, C_BLACK, -0.024, 0.066, -0.3);
  curvedMagM(g, 4, 0, 0.0, -0.13, 0.026, 0.042, 0.052, 0.14);
  g.addPart(RB(0.03, 0.095, 0.04), null, C_BLACK, 0, -0.04, 0.03, 0.3);
  g.addPart(CZ(0.005, 0.2, 6), PRE_X90, C_METAL, -0.016, 0.035, 0.15);
  g.addPart(CZ(0.005, 0.2, 6), PRE_X90, C_METAL, 0.016, 0.035, 0.15);
  g.addPart(RB(0.045, 0.07, 0.018), null, C_BLACK, 0, 0.03, 0.25);
  g.muzzle = new Vec3(0, 0.046, -0.46);
  g.grip = new Vec3(0, -0.035, 0.03);
  g.fore = new Vec3(0, 0, -0.3);
  return g;
}

function buildDeagle(): GunBuilder {
  const g = new GunBuilder();
  g.addPart(RB(0.032, 0.042, 0.255), null, C_STEEL, 0, 0.062, -0.075);
  g.addPart(RB(0.012, 0.006, 0.23), null, C_METAL, 0, 0.086, -0.075);
  g.addPart(RB(0.004, 0.01, 0.006), null, C_METAL, 0, 0.094, -0.19);
  for (let i = 0; i < 6; i++) {
    g.addPart(RB(0.034, 0.03, 0.003), null, C_METAL, 0, 0.062, 0.02 + i * 0.008);
  }
  g.addPart(RB(0.03, 0.032, 0.18), null, C_METAL, 0, 0.026, -0.05);
  g.addPart(RB(0.034, 0.115, 0.055), null, C_RUBBER, 0, -0.04, 0.025, 0.24);
  g.addPart(RB(0.006, 0.006, 0.07), null, C_METAL, 0, -0.003, -0.035);
  g.addPart(RB(0.006, 0.03, 0.006), null, C_METAL, 0, -0.018, -0.07);
  g.addPart(RB(0.008, 0.02, 0.012), null, C_METAL, 0, 0.075, 0.06);
  g.addPart(RB(0.022, 0.1, 0.04), null, C_METAL, 0, -0.07, 0.024, 0.24);
  g.muzzle = new Vec3(0, 0.062, -0.21);
  g.grip = new Vec3(0, -0.04, 0.03);
  g.fore = new Vec3(-0.02, -0.05, 0.02);
  return g;
}

function buildKnife(): GunBuilder {
  const g = new GunBuilder();
  // 刀刃：锥形薄盒（两段）
  g.addPart(RB(0.004, 0.03, 0.13), null, C_BLADE, 0, 0.006, -0.1);
  g.addPart(RB(0.003, 0.018, 0.1), null, C_BLADE, 0, 0.012, -0.2);
  g.addPart(RB(0.018, 0.05, 0.012), null, C_METAL, 0, 0, -0.03);
  g.addPart(RB(0.024, 0.03, 0.11), null, C_RUBBER, 0, 0, 0.03);
  for (let i = 0; i < 4; i++) {
    g.addPart(RB(0.026, 0.032, 0.004), null, C_BLACK, 0, 0, -0.005 + i * 0.022);
  }
  g.addPart(RB(0.026, 0.032, 0.018), null, C_METAL, 0, 0, 0.09);
  g.muzzle = new Vec3(0, 0, -0.23);
  g.grip = new Vec3(0, 0, 0.03);
  g.fore = new Vec3(0, 0, 0.03);
  return g;
}

function buildHE(): GunBuilder {
  const g = new GunBuilder();
  const body = sphereGeom(0.034, 12, 10);
  // 椭球：在 addPart 外手动压扁
  for (let i = 0; i < body.pos.length; i += 3) {
    body.pos[i + 1] *= 1.25;
  }
  g.addPart(body, null, C_OLIVE, 0, 0, 0);
  g.addPart(cylinderGeom(0.014, 0.014, 0.03, 8), null, C_METAL, 0, 0.047, 0);
  g.addPart(RB(0.012, 0.07, 0.006), null, C_METAL, 0, 0.03, 0.03, -0.35);
  g.addPart(RB(0.07, 0.012, 0.004), null, C_TAN, 0, -0.005, 0.034);
  g.muzzle = new Vec3(0, 0, -0.04);
  g.grip = new Vec3(0, 0, 0);
  g.fore = new Vec3(0, 0, 0);
  return g;
}

export const GUN_IDS: string[] = ['ak47', 'm4a1', 'awm', 'mp5', 'deagle', 'knife', 'he'];

export function gunMeshId(id: string): number {
  const i = GUN_IDS.indexOf(id);
  return 9100 + (i >= 0 ? i : 0);
}

const CACHE: Map<string, GunModel> = new Map();

export function buildGun(id: string): GunModel {
  let m = CACHE.get(id);
  if (m) {
    return m;
  }
  let b: GunBuilder;
  if (id === 'ak47') {
    b = buildAK47();
  } else if (id === 'm4a1') {
    b = buildM4A1();
  } else if (id === 'awm') {
    b = buildAWM();
  } else if (id === 'mp5') {
    b = buildMP5();
  } else if (id === 'deagle') {
    b = buildDeagle();
  } else if (id === 'knife') {
    b = buildKnife();
  } else {
    b = buildHE();
  }
  m = new GunModel(b.build(), b.muzzle, b.grip, b.fore);
  CACHE.set(id, m);
  return m;
}

void C_BRASS;
void C_RED;
void capsuleGeom;
