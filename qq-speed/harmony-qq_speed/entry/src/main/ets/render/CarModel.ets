// 赛车模型：低多边形积木式（车身/座舱/尾翼/车灯/霓虹/车轮），部件带层级矩阵
// 自 H5 版 carModel.js 的挤出轮廓简化为盒体组合，保留各车漆配色
import { Skin } from '../common/Config';
import { Palette } from './Palette';
import { Mesh, MeshBuilder, Mat34, matMul, addBox } from './Mesh';

export const WHEEL_POS: number[][] = [[-0.93, 1.38], [0.93, 1.38], [-0.93, -1.38], [0.93, -1.38]];

export class CarPart {
  mesh: Mesh;
  mode: number; // 0 = 车身根, 1 = 带侧倾的车身, 2..5 = 车轮(前两轮带转向)
  offX: number = 0;
  offY: number = 0;
  offZ: number = 0;

  constructor(mesh: Mesh, mode: number) {
    this.mesh = mesh;
    this.mode = mode;
  }
}

export class CarVisual {
  parts: CarPart[] = [];
  skin: Skin = new Skin();
  // 远距离简化车身（仅底盘+座舱+尾翼，~18 面）
  simpleBody: Mesh | null = null;
  // 排气口（尾焰粒子锚点，本地坐标）
  exhausts: number[][] = [[-0.42, 0.42, -2.56], [0.42, 0.42, -2.56]];
}

function buildWheel(pal: Palette, rimCol: number): Mesh {
  const b = new MeshBuilder(pal, true);
  const n = 8;
  const r = 0.47;
  const w = 0.4;
  const tireC = pal.add(0x1a1a1a);
  const rimC = pal.add(rimCol);
  const hubC = pal.add(0x9aa0aa);
  for (let k = 0; k < n; k++) {
    const a0 = (k / n) * Math.PI * 2;
    const a1 = ((k + 1) / n) * Math.PI * 2;
    const y0 = Math.cos(a0) * r;
    const z0 = Math.sin(a0) * r;
    const y1 = Math.cos(a1) * r;
    const z1 = Math.sin(a1) * r;
    // 胎侧（轴沿 X）
    b.quad(-w / 2, y0, z0, -w / 2, y1, z1, w / 2, y1, z1, w / 2, y0, z0, tireC, -1);
    // 胎面（亮一点的深灰）
    const treadC = k % 2 === 0 ? tireC : pal.add(0x282828);
    b.quad(-w / 2, y0, z0, w / 2, y0, z0, w / 2, y1, z1, -w / 2, y1, z1, treadC, -1);
  }
  // 轮毂盖（两侧）
  for (const sx of [-1, 1]) {
    for (let k = 0; k < 4; k++) {
      const a0 = (k / 4) * Math.PI * 2;
      const a1 = ((k + 1) / 4) * Math.PI * 2;
      const x = sx * (w / 2 + 0.01);
      b.quad(x, 0, 0, x, Math.cos(a0) * 0.31, Math.sin(a0) * 0.31,
        x, Math.cos(a1) * 0.31, Math.sin(a1) * 0.31, x, Math.cos(a1) * 0.31, Math.sin(a1) * 0.31,
        k % 2 === 0 ? rimC : hubC, -1);
    }
  }
  return b.build(400);
}

export function buildCarVisual(skin: Skin, pal: Palette): CarVisual {
  const cv = new CarVisual();
  cv.skin = skin;
  const paint = pal.add(skin.body);
  const paintDark = pal.add(mixHex(skin.body, 0x000000, 0.25));
  const accent = pal.add(skin.accent);
  const glass = pal.add(0x18202e);
  const dark = pal.add(0x15171c);
  const head = pal.add(0xf4faff);
  const tail = pal.add(0xff2030);
  const neon = pal.add(skin.glow);

  // —— 车身主体（挂在带侧倾的根上，mode 1）——
  const bb = new MeshBuilder(pal, true);
  // 下部车体（长 4.5、宽 2.0）
  addBox(bb, 0, 0.55, 0, 2.0, 0.5, 4.5, 0, paint, paint, paintDark);
  // 前引擎盖下探
  addBox(bb, 0, 0.5, 2.05, 1.86, 0.32, 0.85, 0, paint, paint, paintDark);
  // 座舱（玻璃色）
  addBox(bb, 0, 1.02, -0.35, 1.46, 0.5, 1.9, 0, glass, glass, glass);
  // 车顶
  addBox(bb, 0, 1.3, -0.6, 1.3, 0.08, 1.2, 0, paint, paint, paint);
  // 侧裙（accent）
  addBox(bb, 0, 0.36, 0, 2.08, 0.16, 3.9, 0, accent, accent, accent);
  // 车顶赛车条纹
  addBox(bb, 0, 1.35, -0.5, 0.34, 0.03, 1.5, 0, accent, accent, accent);
  // 尾翼
  addBox(bb, 0, 1.36, -1.95, 2.1, 0.07, 0.46, 0, accent, accent, accent);
  for (const sx of [-0.62, 0.62]) {
    addBox(bb, sx, 1.12, -1.95, 0.08, 0.42, 0.18, 0, dark, dark, dark);
  }
  for (const sx of [-1.06, 1.06]) {
    addBox(bb, sx, 1.32, -1.97, 0.06, 0.28, 0.6, 0, paint, paint, paint);
  }
  // 头灯（高亮）
  for (const sx of [-0.62, 0.62]) {
    addBox(bb, sx, 0.66, 2.32, 0.5, 0.12, 0.14, 0, head, head, head);
  }
  // 贯穿尾灯 + 两侧灯组（高亮红）
  addBox(bb, 0, 0.8, -2.28, 1.5, 0.08, 0.1, 0, tail, tail, tail);
  for (const sx of [-0.72, 0.72]) {
    addBox(bb, sx, 0.76, -2.28, 0.34, 0.16, 0.1, 0, tail, tail, tail);
  }
  // 后扩散器 / 前格栅
  addBox(bb, 0, 0.38, -2.2, 1.6, 0.16, 0.3, 0, dark, dark, dark);
  addBox(bb, 0, 0.44, 2.3, 1.1, 0.12, 0.12, 0, dark, dark, dark);
  // 侧面霓虹灯条
  for (const sx of [-1.05, 1.05]) {
    addBox(bb, sx, 0.48, -0.5, 0.04, 0.06, 2.2, 0, neon, neon, neon);
  }
  // 排气管
  const exhaustC = pal.add(skin.rim);
  for (const sx of [-0.42, 0.42]) {
    addBox(bb, sx, 0.42, -2.42, 0.18, 0.18, 0.3, 0, exhaustC, exhaustC, exhaustC);
  }
  const bodyMesh = bb.build(400);
  // 头灯/尾灯/霓虹面改为高亮 shade（最后若干面）
  const nFaces = bodyMesh.faceCount;
  for (let i = 0; i < nFaces; i++) {
    bodyMesh.shade[i] = Math.max(bodyMesh.shade[i], 0.9);
  }
  cv.parts.push(new CarPart(bodyMesh, 1));

  // —— 远距离简化车身 ——
  const sb = new MeshBuilder(pal, true);
  addBox(sb, 0, 0.58, 0, 2.0, 0.62, 4.5, 0, paint, paint, paintDark);
  addBox(sb, 0, 1.05, -0.35, 1.46, 0.55, 1.9, 0, glass, glass, glass);
  addBox(sb, 0, 1.36, -1.95, 2.1, 0.1, 0.46, 0, accent, accent, accent);
  cv.simpleBody = sb.build(400);

  // —— 车轮（mode 2..5）——
  const wheel = buildWheel(pal, skin.rim);
  for (let k = 0; k < 4; k++) {
    const p = new CarPart(wheel, 2 + k);
    p.offX = WHEEL_POS[k][0];
    p.offZ = WHEEL_POS[k][1];
    p.offY = 0.47;
    cv.parts.push(p);
  }
  return cv;
}

function mixHex(a: number, b: number, t: number): number {
  const ar = (a >> 16) & 255;
  const ag = (a >> 8) & 255;
  const ab = a & 255;
  const br = (b >> 16) & 255;
  const bg = (b >> 8) & 255;
  const bbb = b & 255;
  return (Math.round(ar + (br - ar) * t) << 16) | (Math.round(ag + (bg - ag) * t) << 8) | Math.round(ab + (bbb - ab) * t);
}

// 每帧组装矩阵（就地复用，避免每帧分配）
export class CarPose {
  root: Mat34 = Mat34.identity();
  lean: Mat34 = Mat34.identity();
  wheels: Mat34[] = [Mat34.identity(), Mat34.identity(), Mat34.identity(), Mat34.identity()];
  scratch: Mat34 = Mat34.identity(); // 部件矩阵暂存（drawMesh 即用即弃）
  wheelSpin: number = 0;

  set(x: number, y: number, z: number, yaw: number, pitch: number, roll: number,
    leanRoll: number, leanPitch: number, steer: number, wheelSpin: number): void {
    composeInto(this.root, x, y, z, yaw, pitch, roll);
    composeInto(this.lean, 0, 0, 0, 0, leanPitch, leanRoll);
    this.wheelSpin = wheelSpin;
    for (let k = 0; k < 4; k++) {
      const front = k < 2;
      composeInto(this.wheels[k], WHEEL_POS[k][0], 0.47, WHEEL_POS[k][1], front ? steer : 0, wheelSpin, 0);
    }
  }
}

// 与 Mat34.compose 相同的 YXZ 欧拉，但写入已存在的矩阵（零分配）
function composeInto(t: Mat34, x: number, y: number, z: number, yaw: number, pitch: number, roll: number): void {
  const cy = Math.cos(yaw);
  const sy = Math.sin(yaw);
  const cp = Math.cos(pitch);
  const sp = Math.sin(pitch);
  const cr = Math.cos(roll);
  const sr = Math.sin(roll);
  const m = t.m;
  m[0] = cy * cr + sy * sp * sr;
  m[1] = -cy * sr + sy * sp * cr;
  m[2] = sy * cp;
  m[3] = x;
  m[4] = cp * sr;
  m[5] = cp * cr;
  m[6] = -sp;
  m[7] = y;
  m[8] = -sy * cr + cy * sp * sr;
  m[9] = sy * sr + cy * sp * cr;
  m[10] = cy * cp;
  m[11] = z;
}

export function carPartMatrix(cv: CarVisual, pose: CarPose, part: CarPart): Mat34 {
  if (part.mode === 0) return pose.root;
  if (part.mode === 1) {
    matMulInto(pose.scratch, pose.root, pose.lean);
    return pose.scratch;
  }
  matMulInto(pose.scratch, pose.root, pose.wheels[part.mode - 2]);
  return pose.scratch;
}

// a·b 写入 out（零分配）
export function matMulInto(out: Mat34, a: Mat34, b: Mat34): void {
  const A = a.m;
  const B = b.m;
  const O = out.m;
  for (let r = 0; r < 3; r++) {
    const a0 = A[r * 4];
    const a1 = A[r * 4 + 1];
    const a2 = A[r * 4 + 2];
    const a3 = A[r * 4 + 3];
    O[r * 4] = a0 * B[0] + a1 * B[4] + a2 * B[8];
    O[r * 4 + 1] = a0 * B[1] + a1 * B[5] + a2 * B[9];
    O[r * 4 + 2] = a0 * B[2] + a1 * B[6] + a2 * B[10];
    O[r * 4 + 3] = a0 * B[3] + a1 * B[7] + a2 * B[11] + a3;
  }
}
