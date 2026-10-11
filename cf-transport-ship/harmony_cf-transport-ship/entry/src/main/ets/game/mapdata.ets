/**
 * 运输船地图构建（移植自原版 map.js）。
 * 坐标：X 沿船长（-X 船尾/潜伏者出生，+X 船头/保卫者出生），Z 船宽，Y 向上，甲板 Y=0。
 */
import { World } from './physics';
import { Batch, Geom, cylinderGeom, sphereGeom, capsuleGeom, triangulatePolygon } from './geometry';
import { Mat4, Vec3 } from './math3d';
import { mulberry32 } from './textures';

export const CH = 2.59;
export const CW = 2.44;
export const L20 = 6.06;
export const L40 = 12.19;
export const SEA_Y = -7.5;
export const H2 = 2.6;

// 纹理 id 常量（与 Game 层上传一致）
export const TEX_WHITE = 1;
export const TEX_DECK = 2;
export const TEX_CONTAINER_BASE = 10; // +0..7
export const TEX_CRATE_BASE = 20;     // +0..4
export const TEX_HULL = 30;
export const TEX_BULKHEAD = 31;
export const TEX_SUPERWALL = 32;
export const TEX_FENCE = 40;
export const TEX_GRATING = 41;
export const TEX_SOLDIER = 60;
export const TEX_GUNWEAR = 61;

// 网格 id 常量
export const MESH_SOLDIER_BL = 9000;
export const MESH_SOLDIER_GR = 9001;
export const MESH_GUN_BASE = 9100;
export const MESH_GRENADE = 9290;
export const MESH_DECK = 100;      // 装饰网格无动态
export const MESH_HANG = 9280;     // 吊着的集装箱（动态摆动）

export interface MatDef {
  tex: number;
  color: number[];
  rough: number;
  metal: number;
  emis: number;
  flags: number; // 1 alphaTest 2 doubleSide 4 unlit
  uvS: number;   // 每米平铺数；0 = 整面 0..1
  uvT: number;
}

function mat(tex: number, color: number[], rough: number, metal: number, uvS: number, uvT: number,
  flags: number = 0, emis: number = 0): MatDef {
  return { tex, color, rough, metal, emis, flags, uvS, uvT };
}

function hex(h: number): number[] {
  return [((h >> 16) & 0xff) / 255, ((h >> 8) & 0xff) / 255, (h & 0xff) / 255];
}

export interface SpawnPoint {
  x: number;
  z: number;
  yaw: number;
}

export interface MapBuild {
  world: World;
  batches: Map<string, Batch>;
  matDefs: Map<string, MatDef>;
  spawns: Map<string, SpawnPoint[]>;
  funnelTop: Vec3;
  hangBase: Mat4;
  craneTip: Vec3;
  lampSpots: Vec3[];
}

const FACE_N: number[][] = [
  [1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]
];
const FACE_U: number[][] = [
  [0, 0, -1], [0, 0, 1], [1, 0, 0], [1, 0, 0], [1, 0, 0], [-1, 0, 0]
];
const FACE_V: number[][] = [
  [0, 1, 0], [0, 1, 0], [0, 0, -1], [0, 0, 1], [0, 1, 0], [0, 1, 0]
];
const FACE_KEYS: string[] = ['px', 'nx', 'py', 'ny', 'pz', 'nz'];

export function buildMap(world: World): MapBuild {
  const rnd = mulberry32(2024);
  const batches: Map<string, Batch> = new Map<string, Batch>();
  const matDefs: Map<string, MatDef> = new Map<string, MatDef>();
  const lampSpots: Vec3[] = [];

  const defMat = (key: string, m: MatDef): void => {
    matDefs.set(key, m);
  };

  // ---------- 材质 ----------
  defMat('deck', mat(TEX_DECK, [1, 1, 1], 0.95, 0.15, 4, 4));
  const CC = [0, 1, 2, 3, 4, 5, 6, 7];
  for (const i of CC) {
    defMat(`c${i}`, mat(TEX_CONTAINER_BASE + i, [1, 1, 1], 0.65, 0.3, 0, 0));
  }
  defMat('crate0', mat(TEX_CRATE_BASE + 0, [1, 1, 1], 0.85, 0, 0, 0));
  defMat('crate1', mat(TEX_CRATE_BASE + 1, [1, 1, 1], 0.85, 0, 0, 0));
  defMat('crate2', mat(TEX_CRATE_BASE + 2, [1, 1, 1], 0.85, 0, 0, 0));
  defMat('crate3', mat(TEX_CRATE_BASE + 3, [1, 1, 1], 0.55, 0.4, 0, 0));
  defMat('crate4', mat(TEX_CRATE_BASE + 4, [1, 1, 1], 0.55, 0.4, 0, 0));
  defMat('bulkhead', mat(TEX_BULKHEAD, [1, 1, 1], 0.6, 0.25, 3, 3));
  defMat('darkSteel', mat(TEX_BULKHEAD, [0.32, 0.34, 0.37], 0.55, 0.5, 3, 3));
  defMat('interior', mat(TEX_BULKHEAD, [0.55, 0.55, 0.52], 0.7, 0.3, 2.4, 2.4));
  defMat('yellow', mat(TEX_BULKHEAD, [0.85, 0.68, 0.16], 0.5, 0.2, 3, 3));
  defMat('red', mat(TEX_BULKHEAD, [0.78, 0.25, 0.2], 0.5, 0.2, 3, 3));
  defMat('green', mat(TEX_BULKHEAD, [0.25, 0.55, 0.3], 0.6, 0.25, 3, 3));
  defMat('railYellow', mat(TEX_WHITE, hex(0xd4a51c), 0.45, 0.25, 0, 0));
  defMat('railWhite', mat(TEX_WHITE, hex(0xe6e6e0), 0.5, 0.2, 0, 0));
  defMat('black', mat(TEX_WHITE, hex(0x1a1b1c), 0.8, 0.1, 0, 0));
  defMat('steel', mat(TEX_WHITE, hex(0x8a8f94), 0.35, 0.9, 0, 0));
  defMat('orange', mat(TEX_WHITE, hex(0xe0621a), 0.5, 0.1, 0, 0));
  defMat('white', mat(TEX_WHITE, hex(0xdedfda), 0.6, 0.1, 0, 0));
  defMat('lamp', mat(TEX_WHITE, [1, 0.95, 0.82], 0.3, 0, 0, 0, 1));
  defMat('redLamp', mat(TEX_WHITE, [1, 0.19, 0.13], 0.3, 0, 0, 0, 1));
  defMat('greenLamp', mat(TEX_WHITE, [0.19, 1, 0.38], 0.3, 0, 0, 0, 1));
  defMat('superWall', mat(TEX_SUPERWALL, [1, 1, 1], 0.55, 0.15, 0, 0));
  defMat('hull', mat(TEX_HULL, [1, 1, 1], 0.6, 0.3, 0, 0, 2));
  defMat('fence', mat(TEX_FENCE, [0.8, 0.8, 0.82], 0.45, 0.6, 0, 0, 1 | 2));
  defMat('grating', mat(TEX_GRATING, [0.75, 0.77, 0.8], 0.6, 0.6, 0, 0, 1 | 2));
  defMat('paintY', mat(TEX_DECK, hex(0xf0c030), 0.75, 0.1, 4, 4));
  defMat('paintW', mat(TEX_DECK, hex(0xf4f4ee), 0.75, 0.1, 4, 4));
  defMat('wood', mat(TEX_CRATE_BASE + 1, [1, 1, 1], 0.85, 0, 1.2, 1.2));

  const batch = (key: string): Batch => {
    let b = batches.get(key);
    if (!b) {
      b = new Batch();
      batches.set(key, b);
    }
    return b;
  };

  // ---------- 几何工具 ----------
  function box(cx: number, cy: number, cz: number, sx: number, sy: number, sz: number, yaw: number,
    faces: Map<string, string> | string, uvOff?: number[]): void {
    const c = Math.cos(yaw), s = Math.sin(yaw);
    const half = [sx / 2, sy / 2, sz / 2];
    const size = [sx, sy, sz];
    const off = uvOff !== undefined ? uvOff : [rnd(), rnd()];
    for (let f = 0; f < 6; f++) {
      const fk = FACE_KEYS[f];
      const key = typeof faces === 'string' ? faces : (faces as Map<string, string>).get(fk);
      if (!key) {
        continue;
      }
      const def = matDefs.get(key) as MatDef;
      const F = FACE_N[f], U = FACE_U[f], V = FACE_V[f];
      const su = Math.abs(U[0] * size[0] + U[1] * size[1] + U[2] * size[2]);
      const sv = Math.abs(V[0] * size[0] + V[1] * size[1] + V[2] * size[2]);
      const ctr = [F[0] * half[0], F[1] * half[1], F[2] * half[2]];
      const corner = (a: number, b: number): number[] => {
        const lx = ctr[0] + U[0] * su * a + V[0] * sv * b;
        const ly = ctr[1] + U[1] * su * a + V[1] * sv * b;
        const lz = ctr[2] + U[2] * su * a + V[2] * sv * b;
        return [cx + c * lx + s * lz, cy + ly, cz - s * lx + c * lz];
      };
      const n = [c * F[0] + s * F[2], F[1], -s * F[0] + c * F[2]];
      let u0 = 0, v0 = 0, u1 = 1, v1 = 1;
      if (def.uvS > 0) {
        u0 = off[0];
        v0 = off[1];
        u1 = u0 + su / def.uvS;
        v1 = v0 + sv / def.uvT;
      }
      batch(key).quad(corner(-0.5, -0.5), corner(0.5, -0.5), corner(0.5, 0.5), corner(-0.5, 0.5), n,
        [u0, v0, u1, v0, u1, v1, u0, v1]);
    }
  }

  function faceMap(px: string | null, nx: string | null, py: string | null, ny: string | null,
    pz: string | null, nz: string | null): Map<string, string> {
    const m = new Map<string, string>();
    if (px !== null) {
      m.set('px', px);
    }
    if (nx !== null) {
      m.set('nx', nx);
    }
    if (py !== null) {
      m.set('py', py);
    }
    if (ny !== null) {
      m.set('ny', ny);
    }
    if (pz !== null) {
      m.set('pz', pz);
    }
    if (nz !== null) {
      m.set('nz', nz);
    }
    return m;
  }

  const solid = (cx: number, cy: number, cz: number, sx: number, sy: number, sz: number, yaw: number,
    collide: boolean, pen: string, sight: boolean, surface: string): void => {
    if (collide) {
      world.add(cx, cy, cz, sx, sy, sz, yaw, {
        mat: surface === 'wood' ? 'wood' : 'metal', bullet: pen, solid: true, sight, surface, tag: ''
      });
    }
  };

  const m4 = new Mat4();
  const tv = new Vec3();
  function geom(key: string, g: Geom, x: number, y: number, z: number, rx: number = 0, ry: number = 0,
    rz: number = 0, sx: number = 1, sy: number = 1, sz: number = 1): void {
    m4.composeScale(tv.set(x, y, z), rx, ry, rz, sx, sy, sz);
    batch(key).addGeom(g, m4);
  }

  // 两点之间的圆柱（栏杆横杆等）
  const up = new Vec3(0, 1, 0);
  const dirV = new Vec3();
  const rightV = new Vec3(1, 0, 0);
  const fwdV = new Vec3();
  const midV = new Vec3();
  function rod(key: string, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number,
    r: number): void {
    dirV.set(x1 - x0, y1 - y0, z1 - z0);
    const L = dirV.length();
    dirV.normalize();
    // 正交基：up -> dir
    rightV.set(1, 0, 0);
    if (Math.abs(dirV.y) > 0.99) {
      rightV.set(0, 0, 1);
    }
    fwdV.cross(dirV, rightV).normalize();
    rightV.cross(fwdV, dirV).normalize();
    midV.set((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2);
    m4.basis(midV, rightV, dirV, fwdV);
    const g = cylinderGeom(r, r, L, 8, false);
    batch(key).addGeom(g, m4);
    void up;
  }

  const cylG = (): Geom => cylinderGeom(1, 1, 1, 12, true);
  const cylG8 = (): Geom => cylinderGeom(1, 1, 1, 8, true);
  const sphG = (): Geom => sphereGeom(1, 8, 6);

  function container(x: number, z: number, yawDeg: number, len: number, colorIdx: number, level: number = 0,
    collide: boolean = true): void {
    const L = len === 40 ? L40 : L20;
    const yaw = yawDeg * Math.PI / 180;
    const cy = level * CH + CH / 2;
    const ci = colorIdx % 8;
    box(x, cy, z, L, CH, CW, yaw, faceMap(`c${ci}`, `c${ci}`, `c${ci}`, level > 0 ? null : null, `c${ci}`, `c${ci}`));
    solid(x, cy, z, L, CH, CW, yaw, collide, 'block', true, 'container');
  }

  function crate(x: number, z: number, sx: number, sy: number, sz: number, idx: number, y: number = 0,
    yawDeg: number = 0): void {
    const yaw = yawDeg * Math.PI / 180;
    box(x, y + sy / 2, z, sx, sy, sz, yaw, `crate${idx}`);
    const wood = idx < 3;
    solid(x, y + sy / 2, z, sx, sy, sz, yaw, true, wood ? 'pen' : 'block', true, wood ? 'wood' : 'metal');
  }

  function barrel(x: number, z: number, colorKey: string, y: number = 0): void {
    geom(colorKey, cylG(), x, y + 0.45, z, 0, rnd() * 6, 0, 0.3, 0.9, 0.3);
    geom('black', cylG(), x, y + 0.9, z, 0, 0, 0, 0.29, 0.02, 0.29);
    for (const hy of [0.25, 0.65]) {
      geom('darkSteel', cylG(), x, y + hy, z, 0, 0, 0, 0.305, 0.03, 0.305);
    }
    solid(x, y + 0.45, z, 0.56, 0.9, 0.56, 0, true, 'pen', true, 'metal');
  }

  function railing(x0: number, z0: number, x1: number, z1: number, y: number, key: string, h: number,
    collide: boolean): void {
    const dx = x1 - x0, dz = z1 - z0;
    const L = Math.hypot(dx, dz);
    const yaw = Math.atan2(-dz, dx);
    const mx = (x0 + x1) / 2, mz = (z0 + z1) / 2;
    const n = Math.max(1, Math.round(L / 1.5));
    for (let i = 0; i <= n; i++) {
      const t = i / n;
      geom(key, cylG8(), x0 + dx * t, y + h / 2, z0 + dz * t, 0, 0, 0, 0.03, h, 0.03);
    }
    for (const hh of [h, h * 0.5, 0.08]) {
      rod(key, x0, y + hh, z0, x1, y + hh, z1, hh === 0.08 ? 0.02 : 0.028);
    }
    if (collide) {
      solid(mx, y + 0.8, mz, L, 1.6, 0.1, yaw, true, 'pass', false, 'metal');
    }
  }

  function fence(x0: number, z0: number, x1: number, z1: number, y0: number, y1: number,
    frameKey: string): void {
    const dx = x1 - x0, dz = z1 - z0;
    const L = Math.hypot(dx, dz);
    const yaw = Math.atan2(-dz, dx);
    const mx = (x0 + x1) / 2, mz = (z0 + z1) / 2;
    const h = y1 - y0;
    // 网面（pz/nz 面为 L×h）
    const m = faceMap(null, null, null, null, 'fence', 'fence');
    box(mx, (y0 + y1) / 2, mz, L, h, 0.001, yaw, m, [0, 0]);
    // 边框
    geom(frameKey, cylG8(), x0, (y0 + y1) / 2, z0, 0, 0, 0, 0.04, h, 0.04);
    geom(frameKey, cylG8(), x1, (y0 + y1) / 2, z1, 0, 0, 0, 0.04, h, 0.04);
    rod(frameKey, x0, y1, z0, x1, y1, z1, 0.035);
    rod(frameKey, x0, y0 + 0.02, z0, x1, y0 + 0.02, z1, 0.035);
    solid(mx, (y0 + y1) / 2, mz, L, h, 0.08, yaw, true, 'pass', false, 'mesh');
  }

  function lamp(x: number, y: number, z: number): void {
    geom('lamp', sphG(), x, y, z, 0, 0, 0, 0.09, 0.09, 0.09);
    geom('darkSteel', cylG8(), x, y + 0.1, z, 0, 0, 0, 0.12, 0.05, 0.12);
    lampSpots.push(new Vec3(x, y - 0.15, z));
  }

  function lifeRing(x: number, y: number, z: number, yaw: number): void {
    for (let i = 0; i < 10; i++) {
      const a0 = (i / 10) * Math.PI * 2;
      const a1 = ((i + 1) / 10) * Math.PI * 2;
      const cx0 = Math.cos(yaw) * Math.cos((a0 + a1) / 2) * 0.32;
      const cz0 = -Math.sin(yaw) * Math.cos((a0 + a1) / 2) * 0.32;
      const cy0 = Math.sin((a0 + a1) / 2) * 0.32;
      geom('orange', cylG8(), x + cx0, y + cy0, z + cz0, 0, yaw, (a0 + a1) / 2 + Math.PI / 2, 0.075, 0.21, 0.075);
    }
  }

  // ================== 甲板与边界 ==================
  {
    // 甲板（船体轮廓多边形三角化）
    const pts: number[][] = [];
    for (let i = 0; i < 80; i++) {
      const p = hullContour(i / 80, 1, 1);
      pts.push([p[0], p[1]]);
    }
    const tris = triangulatePolygon(pts);
    const deckBatch = batch('deck');
    const b = deckBatch.pos.length / 3;
    for (const p of pts) {
      deckBatch.pos.push(p[0], 0, p[1]);
      deckBatch.nrm.push(0, 1, 0);
      deckBatch.uv.push(p[0] / 4, -p[1] / 4);
    }
    for (const t of tris) {
      deckBatch.idx.push(b + t, b + t + 1, b + t + 2);
    }
  }
  solid(0, -0.5, 0, 90, 1, 30, 0, true, 'block', true, 'metal');
  // 舷侧看不见的墙
  for (const sz of [-1, 1]) {
    solid(0, 3, sz * 12.15, 80, 6, 0.1, 0, true, 'pass', false, 'metal');
  }
  solid(-36.6, 6, 0, 0.4, 12, 26, 0, true, 'block', true, 'metal');
  solid(36.6, 6, 0, 0.4, 12, 26, 0, true, 'block', true, 'metal');

  // 舷边栏杆
  for (const sz of [-1, 1]) {
    for (let x = -64; x < 56; x += 10) {
      railing(x, sz * 12.05, Math.min(x + 10, 56), sz * 12.05, 0, 'railYellow', 1.1, false);
    }
    box(-4, 0.08, sz * 12.12, 120, 0.16, 0.06, 0, 'yellow');
  }

  // ================== 对称结构 ==================
  const sideColors: Map<number, number[]> = new Map<number, number[]>();
  sideColors.set(1, [1, 3, 7, 1, 3]);
  sideColors.set(-1, [0, 5, 4, 0, 5]);
  for (const s of [1, -1]) {
    const X = (x: number): number => x * s;
    const Z = (z: number): number => z * s;
    const YAW = (deg: number): number => deg + (s < 0 ? 180 : 0);
    const R = (deg: number): number => YAW(deg) * Math.PI / 180;
    const col = sideColors.get(s) as number[];

    // ---- 出生点舱壁（带两扇门）----
    const wallX = X(-28.15), wallTh = 0.3, wallH = 4.5, doorH = 2.5;
    const doors: number[][] = [[-4.6, -1.8], [2.8, 5.4]];
    const segs: number[][] = [[-12, doors[0][0]], [doors[0][1], doors[1][0]], [doors[1][1], 6.8]];
    for (const seg of segs) {
      const z0 = seg[0], z1 = seg[1];
      const zc = Z((z0 + z1) / 2);
      const L = z1 - z0;
      box(wallX, wallH / 2, zc, wallTh, wallH, L, 0, 'bulkhead');
      solid(wallX, wallH / 2, zc, wallTh, wallH, L, 0, true, 'block', true, 'metal');
    }
    for (const door of doors) {
      const z0 = door[0], z1 = door[1];
      const zc = Z((z0 + z1) / 2);
      const L = z1 - z0;
      box(wallX, doorH + (wallH - doorH) / 2, zc, wallTh, wallH - doorH, L, 0, 'bulkhead');
      solid(wallX, doorH + (wallH - doorH) / 2, zc, wallTh, wallH - doorH, L, 0, true, 'block', true, 'metal');
      box(wallX, 0.05, zc, wallTh + 0.2, 0.1, L, 0, 'darkSteel');
    }
    lamp(wallX + s * 0.35, 3.0, Z(-3.2));
    lamp(wallX + s * 0.35, 3.0, Z(4.1));
    lamp(wallX - s * 0.35, 3.0, Z(-3.2));
    // 消防箱
    box(wallX - s * 0.3, 1.3, Z(-9.8), 0.25, 0.8, 0.6, 0, 'red');

    // ---- 出生点内：吊机底座、楼梯、平台 ----
    const cx = X(-33), cz = Z(-9.6);
    geom('yellow', cylG(), cx, 3, cz, 0, 0, 0, 1.15, 6, 1.15);
    geom('darkSteel', cylG(), cx, 0.15, cz, 0, 0, 0, 1.45, 0.3, 1.45);
    solid(cx, 3, cz, 2.2, 6, 2.2, R(45), true, 'block', true, 'metal');
    solid(cx, 3, cz, 2.2, 6, 2.2, 0, true, 'block', true, 'metal');
    // 楼梯
    const nSteps = 10, stepH = H2 / nSteps, sx0 = -34, sx1 = -29.5, tread = (sx1 - sx0) / nSteps;
    const stz0 = 6.9, stz1 = 8.5;
    for (let i = 0; i < nSteps; i++) {
      const x0 = sx0 + i * tread;
      const cxs = X((x0 + sx1) / 2);
      const h = (i + 1) * stepH;
      box(cxs, h / 2, Z((stz0 + stz1) / 2), sx1 - x0, h, stz1 - stz0, 0,
        faceMap('darkSteel', 'darkSteel', 'grating', null, 'darkSteel', 'darkSteel'));
      box(X(x0 + 0.03), h - 0.02, Z((stz0 + stz1) / 2), 0.06, 0.04, stz1 - stz0, 0, 'railYellow');
      solid(cxs, h / 2, Z((stz0 + stz1) / 2), sx1 - x0, h, stz1 - stz0, 0, true, 'block', true, 'grate');
    }
    rod('railYellow', X(sx0), 1.0, Z(stz0), X(sx1), H2 + 1.0, Z(stz0), 0.03);
    rod('railYellow', X(sx0), 0.55, Z(stz0), X(sx1), H2 + 0.55, Z(stz0), 0.025);
    for (let i = 0; i <= 4; i++) {
      const t = i / 4;
      const hx = sx0 + (sx1 - sx0) * t, hy = H2 * t;
      rod('railYellow', X(hx), hy, Z(stz0), X(hx), hy + 1.0, Z(stz0), 0.03);
    }
    // 平台支撑块
    box(X(-28.75), H2 / 2, Z(8.1), 1.5, H2, 2.6, 0,
      faceMap('darkSteel', 'darkSteel', 'grating', null, 'darkSteel', 'darkSteel'));
    solid(X(-28.75), H2 / 2, Z(8.1), 1.5, H2, 2.6, 0, true, 'block', true, 'grate');
    railing(X(-29.5), Z(6.8), X(-28.0), Z(6.8), H2, 'railYellow', 1.1, true);

    // 出生点杂物
    crate(X(-29.6), Z(-6.6), 1.3, 1.3, 1.3, 4, 0, 10);
    crate(X(-29.5), Z(-5.3), 1.0, 0.9, 1.0, 5, 0, -5);
    crate(X(-35.6), Z(4.2), 1.4, 1.4, 1.4, 4, 0, 0);
    for (const bz of [-11.3, 11.3]) {
      const bx = X(-35.3), bzz = Z(bz);
      geom('black', cylG(), bx - 0.35, 0.35, bzz, 0, 0, 0, 0.2, 0.7, 0.2);
      geom('black', cylG(), bx + 0.35, 0.35, bzz, 0, 0, 0, 0.2, 0.7, 0.2);
      box(bx, 0.05, bzz, 1.3, 0.1, 0.55, 0, 'black');
      solid(bx, 0.35, bzz, 1.2, 0.7, 0.45, 0, true, 'block', true, 'metal');
    }
    lifeRing(X(-31.5), 0.85, Z(11.98), s > 0 ? 0 : Math.PI);
    lifeRing(X(-34.5), 0.85, Z(-11.98), s > 0 ? Math.PI : 0);
    // 蘑菇通风筒
    for (const vz of [-7.8, 0.3]) {
      const vx = -35.4;
      geom('white', cylG(), X(vx), 0.6, Z(vz), 0, 0, 0, 0.18, 1.2, 0.18);
      geom('white', sphG(), X(vx), 1.25, Z(vz), 0, 0, 0, 0.36, 0.2, 0.36);
      solid(X(vx), 0.7, Z(vz), 0.5, 1.4, 0.5, 0, true, 'block', true, 'metal');
    }

    // ---- 集装箱管道 + 二楼 ----
    const tz0 = 9.4, tz1 = 9.4 + CW, tzc = (tz0 + tz1) / 2;
    const tx0 = -29.5;
    const segCols = [col[0], col[1], col[2]];
    const wT = 0.08;
    for (let k = 0; k < 3; k++) {
      const x0 = tx0 + k * L40, x1 = x0 + L40, xc = (x0 + x1) / 2;
      const ci = segCols[k] % 8;
      // 内墙
      box(X(xc), CH / 2, Z(tz0 + wT / 2), L40, CH, wT, 0,
        faceMap('interior', 'interior', null, null, 'interior', `c${ci}`));
      solid(X(xc), CH / 2, Z(tz0 + wT / 2), L40, CH, wT, 0, true, 'block', true, 'metal');
      // 外墙：实墙 + 铁丝网窗
      const win = [x0 + 3.2, x0 + 8.4];
      let cur = x0;
      for (const wx of win) {
        const a = cur, b2 = wx;
        box(X((a + b2) / 2), CH / 2, Z(tz1 - wT / 2), b2 - a, CH, wT, 0,
          faceMap(`c${ci}`, 'interior', null, null, `c${ci}`, 'interior'));
        solid(X((a + b2) / 2), CH / 2, Z(tz1 - wT / 2), b2 - a, CH, wT, 0, true, 'block', true, 'metal');
        const f0 = wx, f1 = wx + 1.6;
        fence(X(f0), Z(tz1 - wT / 2), X(f1), Z(tz1 - wT / 2), 0.9, 2.2, 'railYellow');
        box(X((f0 + f1) / 2), 0.45, Z(tz1 - wT / 2), 1.6, 0.9, wT, 0,
          faceMap(`c${ci}`, 'interior', null, null, `c${ci}`, 'interior'));
        box(X((f0 + f1) / 2), (2.2 + CH) / 2, Z(tz1 - wT / 2), 1.6, CH - 2.2, wT, 0,
          faceMap(`c${ci}`, 'interior', null, null, `c${ci}`, 'interior'));
        solid(X((f0 + f1) / 2), CH / 2, Z(tz1 - wT / 2), 1.6, CH, wT, 0, true, 'pass', false, 'metal');
        cur = f1;
      }
      box(X((cur + x1) / 2), CH / 2, Z(tz1 - wT / 2), x1 - cur, CH, wT, 0,
        faceMap(`c${ci}`, 'interior', null, null, `c${ci}`, 'interior'));
      solid(X((cur + x1) / 2), CH / 2, Z(tz1 - wT / 2), x1 - cur, CH, wT, 0, true, 'block', true, 'metal');
      // 顶板（二楼地面）
      box(X(xc), CH - 0.07, Z(tzc), L40, 0.14, CW + 0.001, 0,
        faceMap(null, null, `c${ci}`, 'interior', null, null));
      solid(X(xc), CH - 0.07, Z(tzc), L40, 0.14, CW, 0, true, 'block', true, 'container');
      // 角柱
      for (const px of [x0, x1]) {
        for (const pz of [tz0, tz1]) {
          box(X(px), CH / 2, Z(pz), 0.16, CH, 0.16, 0, 'darkSteel');
        }
      }
      // 管道内灯
      lamp(X(xc - 3), CH - 0.25, Z(tzc));
      lamp(X(xc + 3), CH - 0.25, Z(tzc));
      // 外侧管线
      geom('darkSteel', cylG(), X(xc), 0.35, Z(tz1 - 0.3), 0, 0, Math.PI / 2, 0.16, L40, 0.16);
      geom('red', cylG(), X(xc), 0.75, Z(tz1 - 0.28), 0, 0, Math.PI / 2, 0.08, L40, 0.08);
    }
    solid(X(tx0 + 1.5 * L40), 0.4, Z(tz1 - 0.3), 3 * L40, 0.8, 0.36, 0, true, 'pass', true, 'metal');
    const tEnd = tx0 + 3 * L40;
    // 管道尽头：20尺集装箱 + 40尺双层
    container(X(11.83), Z(tzc), YAW(0), 20, col[3]);
    container(X(21.05), Z(tzc), YAW(0), 40, col[4]);
    container(X(21.05), Z(tzc), YAW(0), 40, col[0] + 2, 1);
    // 二楼栏杆
    railing(X(tx0), Z(11.8), X(14.86), Z(11.8), H2, 'railYellow', 1.1, true);
    railing(X(-24), Z(9.45), X(-16), Z(9.45), H2, 'railYellow', 1.1, true);
    railing(X(-8), Z(9.45), X(-2), Z(9.45), H2, 'railYellow', 1.1, true);
    // 管道出口外的箱子
    for (let i = 0; i < 5; i++) {
      crate(X(8.8 + 0.59 + i * 1.18), Z(8.85), 1.16, 0.9, 1.1, i % 2 ? 1 : 3, 0, 0);
    }
    crate(X(11.5), Z(8.85), 1.2, 0.95, 1.2, 0, 0.9, 5);
    crate(X(11.3), Z(7.5), 1.6, 1.6, 1.6, 2, 0, -6);

    // ---- 主甲板障碍（半场）----
    container(X(-21.5), Z(-1.8), YAW(90), 20, col[1]);
    container(X(-12.8), Z(0.9), YAW(90), 20, col[2]);
    container(X(-13.6), Z(5.15), YAW(0), 20, col[0]);
    container(X(-13.6), Z(5.15), YAW(0), 20, col[3] + 1, 1);
    crate(X(-14.65), Z(2.3), 1.2, 1.8, 1.2, 4, 0, 0);
    crate(X(-15.8), Z(2.3), 1.0, 0.9, 1.0, 1, 0, 8);
    crate(X(-26.9), Z(0.4), 1.6, 1.6, 1.6, 4, 0, 0);
    crate(X(-26.6), Z(2.1), 1.2, 1.2, 1.2, 5, 0, 15);
    crate(X(-6.4), Z(8.3), 1.4, 1.4, 1.4, s > 0 ? 0 : 2, 0, 4);
    barrel(X(-19.2), Z(-8.3), 'red');
    barrel(X(-18.5), Z(-8.7), 'red');
    barrel(X(-18.8), Z(-7.7), 'green');
    barrel(X(-9.6), Z(8.7), 'green');
    barrel(X(-9.0), Z(8.95), 'red');
    // 甲板黄线
    for (const lz of [-7.2, 7.4]) {
      box(X(-17), 0.004, Z(lz), 16, 0.001, 0.12, 0, faceMap(null, null, 'paintY', null, null, null), [0, 0]);
    }
  }

  // ---- 中路：V 形斜放集装箱 + 木箱 ----
  container(-1.1, -4.4, -39, 20, 2);
  container(0.9, 4.0, 33, 20, 6);
  crate(-6.9, 1.3, 1.6, 1.6, 1.6, 0, 0, 3);
  crate(-5.2, 1.4, 1.2, 1.2, 1.2, 2, 0, -8);
  crate(-6.9, 1.3, 1.0, 0.8, 1.0, 1, 1.6, 20);

  // ================== 保卫者背后：集装箱墙 ==================
  const stackCols = [0, 5, 4, 1, 2, 6, 3, 7];
  for (let tier = 0; tier < 3; tier++) {
    for (let i = 0; i < 4; i++) {
      container(37.6, -9.09 + i * L20, 90, 20, stackCols[(i + tier * 3) % 8], tier, tier === 0);
    }
  }
  solid(37.6, 6, 0, CW, 12, 24.4, 0, true, 'block', true, 'metal');
  // 更远处的堆场（仅装饰，降低数量保证性能）
  for (let row = 0; row < 2; row++) {
    for (let bay = 0; bay < 5; bay++) {
      const h = 2 + ((row * 7 + bay * 3) % 3);
      for (let tier = 0; tier < h; tier++) {
        container(41 + row * 7, -10.6 + bay * 3.03, 0, 20, (bay + row * 3 + tier * 5) % 8, tier, false);
      }
    }
  }
  // 前桅
  geom('white', cylG(), 64, 8, 0, 0, 0, 0, 0.35, 16, 0.35);
  geom('white', cylG8(), 64, 13, 0, 0, 0, Math.PI / 2, 0.08, 6, 0.08);
  geom('redLamp', sphG(), 64, 16.3, 0, 0, 0, 0, 0.2, 0.2, 0.2);

  // ================== 上层建筑（潜伏者背后） ==================
  const sx0 = -56, sx1 = -36.7, sw = 11.2;
  for (let lvl = 0; lvl < 5; lvl++) {
    const y0 = lvl * 3, inset = lvl * 0.4;
    const x1 = sx1 - (lvl > 3 ? 1.5 : 0);
    const wz = sw + (lvl === 4 ? 3 : 0);
    box((sx0 + x1) / 2, y0 + 1.5, 0, x1 - sx0 - inset, 3, wz * 2, 0,
      faceMap('superWall', 'superWall', 'white', 'white', 'superWall', 'superWall'), [0, 0]);
    box((sx0 + x1) / 2, y0 + 3 - 0.08, 0, x1 - sx0 - inset + 0.6, 0.16, wz * 2 + 0.6, 0, 'white');
    if (lvl < 4) {
      railing(x1 + 0.3, -wz, x1 + 0.3, wz, y0 + 3, 'railWhite', 1.0, false);
    }
  }
  box((sx0 + sx1) / 2, 15.1, 0, sx1 - sx0 - 1, 0.2, 29, 0, 'white');
  // 驾驶台黑玻璃带
  box(sx1 - 1.52, 13.4, 0, 0.05, 1.3, 26, 0, 'black');
  // 烟囱
  const fx = -51;
  box(fx, 20, 0, 5, 10, 4.2, 0, faceMap('white', 'white', 'black', null, 'white', 'white'));
  box(fx, 22.5, 0, 5.05, 1.6, 4.25, 0, faceMap('red', 'red', null, null, 'red', 'red'));
  box(fx, 24.8, 0, 5.1, 0.6, 4.3, 0, 'black');
  const funnelTop = new Vec3(fx, 25.3, 0);
  // 雷达桅
  geom('white', cylG(), -45, 18.5, 0, 0, 0, 0, 0.18, 7, 0.18);
  box(-45, 21.5, 0, 0.3, 0.3, 4, 0, 'white');
  box(-45, 22.4, 0, 0.25, 0.18, 3.2, 0, 'white');
  geom('redLamp', sphG(), -45, 22.1, 1.9, 0, 0, 0, 0.12, 0.12, 0.12);
  geom('greenLamp', sphG(), -45, 22.1, -1.9, 0, 0, 0, 0.12, 0.12, 0.12);
  // 救生艇
  for (const sz of [-1, 1]) {
    geom('orange', capsuleGeom(1.1, 5.2, 3, 10), -46, 7.2, sz * 12.4, 0, 0, Math.PI / 2, 1, 1, 1);
    box(-46, 8.15, sz * 12.4, 6, 0.3, 1.6, 0, 'white');
    for (const dx of [-2.6, 2.6]) {
      geom('white', cylG8(), -46 + dx, 7.8, sz * 11.8, sz * 0.5, 0, 0, 0.08, 3, 0.08);
    }
  }
  // 上层建筑前门
  for (const dz of [-6, 6]) {
    box(sx1 + 0.02, 1.1, dz, 0.06, 2.2, 1.1, 0, 'darkSteel');
  }

  // ================== 吊机 ==================
  function crane(px: number, pz: number, yawDeg: number, luff: number, jibLen: number): Vec3 {
    const yaw = yawDeg * Math.PI / 180;
    const local = (x: number, y: number): number[] => {
      return [px + Math.cos(yaw) * x + Math.sin(yaw) * y, pz - Math.sin(yaw) * x + Math.cos(yaw) * y];
    };
    // 塔身
    const base = local(-0.4, 0);
    geom('yellow', cylG(), base[0], 1.3, base[1], 0, yaw, 0, 1.6, 2.6, 1.6);
    geom('black', cylG(), base[0], 2.6, base[1], 0, yaw, 0, 1.0, 0.1, 1.0);
    // 驾驶室
    const cab = local(0.5, 0);
    box(cab[0], 7.3, cab[1], 2.6, 2.2, 2.4, yaw, 'yellow');
    // 吊臂（绕 Z 俯仰）
    const pivot = local(0.8, 0);
    const tipX = jibLen * Math.cos(luff);
    const tipY = 7.8 + jibLen * Math.sin(luff) * 0 + jibLen * Math.sin(luff);
    // 臂杆两根
    for (const off of [-0.45, 0.45]) {
      const a = local(0, off), b = local(tipX, off);
      rod('yellow', a[0], 7.8 + 0, a[1], b[0], 7.8 + tipX * Math.tan(luff) * 0 + jibLen * Math.sin(luff), b[1], 0.14);
    }
    return new Vec3(pivot[0] + Math.cos(yaw) * tipX, 6 + 1.8 + jibLen * Math.sin(luff),
      pivot[1] - Math.sin(yaw) * tipX);
  }
  const tipA = crane(-33, -9.6, -12, 0.36, 30);
  crane(33, 9.6, 168, 0.95, 22);
  // 吊着的集装箱（随风摆动，动态网格 MESH_HANG，几何在吊点局部空间）
  const hangBase = new Mat4().compose(new Vec3(tipA.x, tipA.y, tipA.z), 0, 0, 0);
  box(0, -2.5, 0, L20, CH, CW, 0, faceMap('c5', 'c5', 'c5', null, 'c5', 'c5'), [0, 0]);
  // 吊索与撑架（同样在吊点局部空间）
  rod('c5', -0.25, -1.1, 0, -0.25, -0.1, 0, 0.03);
  rod('c5', 0.25, -1.1, 0, 0.25, -0.1, 0, 0.03);
  box(0, -1.25, 0, L20 - 0.2, 0.25, CW - 0.2, 0, 'c5', [0, 0]);

  // ================== 船体 ==================
  buildHull(batch('hull'));

  world.build();

  // ================== 出生点 ==================
  const spawns: Map<string, SpawnPoint[]> = new Map<string, SpawnPoint[]>();
  const bl: SpawnPoint[] = [];
  const gr: SpawnPoint[] = [];
  for (let i = 0; i < 10; i++) {
    const zz = -6.6 + (i % 5) * 3.0;
    const xx = -34.0 + Math.floor(i / 5) * 2.8;
    bl.push({ x: xx, z: zz, yaw: -Math.PI / 2 });
    gr.push({ x: -xx, z: -zz, yaw: Math.PI / 2 });
  }
  spawns.set('BL', bl);
  spawns.set('GR', gr);

  return { world, batches, matDefs, spawns, funnelTop, hangBase, craneTip: tipA, lampSpots };
}

/** 船体轮廓：t∈[0,1) 沿边界一周 */
export function hullContour(t: number, sc: number, bowK: number): number[] {
  const halfW = 12.25 * sc;
  const xs = -66, xb0 = 58, xb1 = 58 + 28 * bowK;
  if (t < 0.35) {
    const k = t / 0.35;
    return [xs + (xb0 - xs) * k, halfW];
  }
  if (t < 0.5) {
    const a = ((t - 0.35) / 0.15) * Math.PI;
    const sinA = Math.sin(a);
    return [xb0 + (xb1 - xb0) * Math.pow(sinA, 0.8), halfW * Math.cos(a) * (1 - 0.1 * sinA)];
  }
  if (t < 0.85) {
    const k = (t - 0.5) / 0.35;
    return [xb0 + (xs - xb0) * k, -halfW];
  }
  const a = ((t - 0.85) / 0.15) * Math.PI;
  return [xs - 3 * Math.sin(a) * sc, -halfW * Math.cos(a)];
}

/** 程序生成船体：多层轮廓环 */
function buildHull(batch: Batch): void {
  const rings: number[][] = [
    [0.12, 1.0, 1.0], [-0.4, 1.0, 1.0], [-2.5, 0.995, 0.97], [-5, 0.985, 0.93],
    [-7.5, 0.965, 0.88], [-9.5, 0.93, 0.82], [-12, 0.85, 0.74]
  ];
  const N = 60;
  const base = batch.pos.length / 3;
  const lens: number[] = [];
  for (const R of rings) {
    let acc = 0;
    let prev: number[] | null = null;
    for (let i = 0; i <= N; i++) {
      const p = hullContour((i % N) / N, R[1], R[2]);
      if (prev !== null) {
        acc += Math.hypot(p[0] - prev[0], p[1] - prev[1]);
      }
      prev = p;
      batch.pos.push(p[0], R[0], p[1]);
      batch.nrm.push(0, 1, 0); // 占位，稍后统一重算
      batch.uv.push(acc / 16, (R[0] + 12) / 13.5);
    }
    lens.push(acc);
  }
  const row = N + 1;
  for (let r = 0; r < rings.length - 1; r++) {
    for (let i = 0; i < N; i++) {
      const a = r * row + i, b = a + 1, c = a + row, d = c + 1;
      batch.idx.push(a, c, b, b, c, d);
    }
  }
  // 重算法线（相邻面平均）
  const nrm = batch.nrm;
  const pos = batch.pos;
  const start = base;
  for (let i = start; i < batch.pos.length / 3; i++) {
    nrm[i * 3] = 0;
    nrm[i * 3 + 1] = 0;
    nrm[i * 3 + 2] = 0;
  }
  for (let idxI = 0; idxI < batch.idx.length; idxI += 3) {
    const i0 = batch.idx[idxI], i1 = batch.idx[idxI + 1], i2 = batch.idx[idxI + 2];
    if (i0 < base || i1 < base || i2 < base) {
      continue;
    }
    const ax = pos[i1 * 3] - pos[i0 * 3], ay = pos[i1 * 3 + 1] - pos[i0 * 3 + 1], az = pos[i1 * 3 + 2] - pos[i0 * 3 + 2];
    const bx = pos[i2 * 3] - pos[i0 * 3], by = pos[i2 * 3 + 1] - pos[i0 * 3 + 1], bz = pos[i2 * 3 + 2] - pos[i0 * 3 + 2];
    const nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
    nrm[i0 * 3] += nx;
    nrm[i0 * 3 + 1] += ny;
    nrm[i0 * 3 + 2] += nz;
    nrm[i1 * 3] += nx;
    nrm[i1 * 3 + 1] += ny;
    nrm[i1 * 3 + 2] += nz;
    nrm[i2 * 3] += nx;
    nrm[i2 * 3 + 1] += ny;
    nrm[i2 * 3 + 2] += nz;
  }
  for (let i = start; i < batch.pos.length / 3; i++) {
    const l = Math.hypot(nrm[i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2]) || 1;
    nrm[i * 3] /= l;
    nrm[i * 3 + 1] /= l;
    nrm[i * 3 + 2] /= l;
  }
}
