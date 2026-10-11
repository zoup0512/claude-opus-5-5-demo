/**
 * 几何生成库：仿 THREE.js 的 BoxGeometry / CylinderGeometry / SphereGeometry / CapsuleGeometry，
 * 输出 {pos, nrm, uv, idx} 数组，供渲染层上传与模型构建使用。
 */
import { Mat4, Vec3 } from './math3d';

export class Geom {
  pos: number[] = [];
  nrm: number[] = [];
  uv: number[] = [];
  idx: number[] = [];

  vertCount(): number {
    return this.pos.length / 3;
  }
}

const BOX_FACES: number[][] = [
  // [nx,ny,nz, ux,uy,uz, vx,vy,vz]（u/v 为面内二维基）
  [0, 0, 1, 1, 0, 0, 0, 1, 0],    // +Z
  [0, 0, -1, -1, 0, 0, 0, 1, 0],  // -Z
  [1, 0, 0, 0, 0, -1, 0, 1, 0],   // +X
  [-1, 0, 0, 0, 0, 1, 0, 1, 0],   // -X
  [0, 1, 0, 1, 0, 0, 0, 0, -1],   // +Y
  [0, -1, 0, 1, 0, 0, 0, 0, 1]    // -Y
];

export function boxGeom(w: number, h: number, d: number): Geom {
  const g = new Geom();
  const hx = w / 2, hy = h / 2, hz = d / 2;
  const su = [d, d, h, h, w, w]; // 各面 u 方向长度
  const sv = [h, h, d, d, d, d]; // 各面 v 方向长度
  for (let f = 0; f < 6; f++) {
    const F = BOX_FACES[f];
    const base = g.vertCount();
    for (let i = 0; i < 4; i++) {
      const a = (i === 0 || i === 3) ? -0.5 : 0.5;
      const b = (i < 2) ? -0.5 : 0.5;
      g.pos.push(F[0] * hx + F[3] * su[f] * a + F[6] * sv[f] * b,
        F[1] * hy + F[4] * su[f] * a + F[7] * sv[f] * b,
        F[2] * hz + F[5] * su[f] * a + F[8] * sv[f] * b);
      g.nrm.push(F[0], F[1], F[2]);
      g.uv.push(a + 0.5, b + 0.5);
    }
    g.idx.push(base, base + 1, base + 2, base, base + 2, base + 3);
  }
  return g;
}

/** 圆柱：轴 Y，中心在原点。capped 生成顶/底盖 */
export function cylinderGeom(rTop: number, rBot: number, h: number, seg: number, capped: boolean = true): Geom {
  const g = new Geom();
  const half = h / 2;
  const ny = (rBot - rTop) / h;
  // 侧面（顶行到底行，u 环向）
  const rows = 2;
  for (let r = 0; r <= rows; r++) {
    const v = r / rows;
    const y = half - v * h;
    const rad = rTop + (rBot - rTop) * v;
    for (let i = 0; i <= seg; i++) {
      const u = i / seg;
      const th = u * Math.PI * 2;
      const s = Math.sin(th), c = Math.cos(th);
      g.pos.push(rad * s, y, rad * c);
      const nl = Math.hypot(s, ny, c);
      g.nrm.push(s / nl, ny / nl, c / nl);
      g.uv.push(u, v);
    }
  }
  for (let r = 0; r < rows; r++) {
    for (let i = 0; i < seg; i++) {
      const a = r * (seg + 1) + i, b = a + 1, c = a + seg + 1, d = c + 1;
      g.idx.push(a, c, b, b, c, d);
    }
  }
  if (capped && rTop > 0) {
    const base = g.vertCount();
    g.pos.push(0, half, 0);
    g.nrm.push(0, 1, 0);
    g.uv.push(0.5, 0.5);
    for (let i = 0; i <= seg; i++) {
      const th = (i / seg) * Math.PI * 2;
      const s = Math.sin(th), c = Math.cos(th);
      g.pos.push(rTop * s, half, rTop * c);
      g.nrm.push(0, 1, 0);
      g.uv.push(0.5 + s * 0.5, 0.5 + c * 0.5);
    }
    for (let i = 0; i < seg; i++) {
      g.idx.push(base, base + 1 + i, base + 2 + i);
    }
  }
  if (capped && rBot > 0) {
    const base = g.vertCount();
    g.pos.push(0, -half, 0);
    g.nrm.push(0, -1, 0);
    g.uv.push(0.5, 0.5);
    for (let i = 0; i <= seg; i++) {
      const th = (i / seg) * Math.PI * 2;
      const s = Math.sin(th), c = Math.cos(th);
      g.pos.push(rBot * s, -half, rBot * c);
      g.nrm.push(0, -1, 0);
      g.uv.push(0.5 + s * 0.5, 0.5 - c * 0.5);
    }
    for (let i = 0; i < seg; i++) {
      g.idx.push(base, base + 2 + i, base + 1 + i);
    }
  }
  return g;
}

/** 球：可部分（thetaStart/Length 控制上下范围） */
export function sphereGeom(r: number, wSeg: number, hSeg: number, thetaStart: number = 0,
  thetaLength: number = Math.PI): Geom {
  const g = new Geom();
  for (let j = 0; j <= hSeg; j++) {
    const v = j / hSeg;
    const phi = thetaStart + v * thetaLength;
    const sp = Math.sin(phi), cp = Math.cos(phi);
    for (let i = 0; i <= wSeg; i++) {
      const u = i / wSeg;
      const th = u * Math.PI * 2;
      const s = Math.sin(th), c = Math.cos(th);
      const nx = -s * sp, ny = cp, nz = c * sp;
      g.pos.push(r * nx, r * ny, r * nz);
      g.nrm.push(nx, ny, nz);
      g.uv.push(u, 1 - v);
    }
  }
  for (let j = 0; j < hSeg; j++) {
    for (let i = 0; i < wSeg; i++) {
      const a = j * (wSeg + 1) + i, b = a + 1, c = a + wSeg + 1, d = c + 1;
      if (j !== 0 || thetaStart > 0) {
        g.idx.push(a, c, b);
      }
      if (j !== hSeg - 1 || thetaStart + thetaLength < Math.PI) {
        g.idx.push(b, c, d);
      }
    }
  }
  return g;
}

/** 胶囊：中间圆柱 + 上下半球，平滑法线 */
export function capsuleGeom(r: number, length: number, capSeg: number, radSeg: number): Geom {
  const g = new Geom();
  const half = length / 2;
  const rows: number[][] = []; // [y, radius, ny(法线 y 分量)]
  for (let j = capSeg; j >= 0; j--) {
    const ph = (j / capSeg) * (Math.PI / 2);
    rows.push([half + r * Math.cos(ph), r * Math.sin(ph), Math.cos(ph)]);
  }
  rows.push([-half, r, 0]);
  for (let j = 0; j <= capSeg; j++) {
    const ph = (j / capSeg) * (Math.PI / 2);
    rows.push([-half - r * Math.cos(ph), r * Math.sin(ph), -Math.cos(ph)]);
  }
  const R = rows.length;
  for (let j = 0; j < R; j++) {
    const y = rows[j][0], rad = rows[j][1], ny = rows[j][2];
    const hor = Math.sqrt(Math.max(0, 1 - ny * ny));
    for (let i = 0; i <= radSeg; i++) {
      const u = i / radSeg;
      const th = u * Math.PI * 2;
      const s = Math.sin(th), c = Math.cos(th);
      g.pos.push(rad * s, y, rad * c);
      g.nrm.push(hor * s, ny, hor * c);
      g.uv.push(u, j / (R - 1));
    }
  }
  for (let j = 0; j < R - 1; j++) {
    for (let i = 0; i < radSeg; i++) {
      const a = j * (radSeg + 1) + i, b = a + 1, c = a + radSeg + 1, d = c + 1;
      g.idx.push(a, c, b, b, c, d);
    }
  }
  return g;
}

/** 平面（XY 平面，法线 +Z） */
export function planeGeom(w: number, h: number): Geom {
  const g = new Geom();
  const hw = w / 2, hh = h / 2;
  g.pos.push(-hw, -hh, 0, hw, -hh, 0, hw, hh, 0, -hw, hh, 0);
  for (let i = 0; i < 4; i++) {
    g.nrm.push(0, 0, 1);
  }
  g.uv.push(0, 0, 1, 0, 1, 1, 0, 1);
  g.idx.push(0, 1, 2, 0, 2, 3);
  return g;
}

const _tv = new Vec3();

/** 就地变换几何（位置按点变换、法线按方向变换后归一化） */
export function transformGeom(g: Geom, m: Mat4): Geom {
  const mm = m.m;
  for (let i = 0; i < g.pos.length; i += 3) {
    const x = g.pos[i], y = g.pos[i + 1], z = g.pos[i + 2];
    g.pos[i] = mm[0] * x + mm[4] * y + mm[8] * z + mm[12];
    g.pos[i + 1] = mm[1] * x + mm[5] * y + mm[9] * z + mm[13];
    g.pos[i + 2] = mm[2] * x + mm[6] * y + mm[10] * z + mm[14];
  }
  for (let i = 0; i < g.nrm.length; i += 3) {
    const x = g.nrm[i], y = g.nrm[i + 1], z = g.nrm[i + 2];
    _tv.set(mm[0] * x + mm[4] * y + mm[8] * z, mm[1] * x + mm[5] * y + mm[9] * z, mm[2] * x + mm[6] * y + mm[10] * z);
    _tv.normalize();
    g.nrm[i] = _tv.x;
    g.nrm[i + 1] = _tv.y;
    g.nrm[i + 2] = _tv.z;
  }
  return g;
}

/** 合并多个几何（非索引化拼接） */
export function mergeGeoms(list: Geom[]): Geom {
  const out = new Geom();
  for (const g of list) {
    // 转为非索引
    for (const i of g.idx) {
      out.pos.push(g.pos[i * 3], g.pos[i * 3 + 1], g.pos[i * 3 + 2]);
      out.nrm.push(g.nrm[i * 3], g.nrm[i * 3 + 1], g.nrm[i * 3 + 2]);
      out.uv.push(g.uv[i * 2], g.uv[i * 2 + 1]);
    }
  }
  return out;
}

/** 将几何打包为渲染层顶点数据（stride 11：pos3 nrm3 uv2 col3；skin 时追加 boneIdx = stride 12） */
export function geomToVertexData(g: Geom, colR: number, colG: number, colB: number, skin: boolean,
  boneIdx: number = 0): Float32Array {
  const stride = skin ? 12 : 11;
  const n = g.idx.length;
  const out = new Float32Array(n * stride);
  let o = 0;
  for (const i of g.idx) {
    out[o++] = g.pos[i * 3];
    out[o++] = g.pos[i * 3 + 1];
    out[o++] = g.pos[i * 3 + 2];
    out[o++] = g.nrm[i * 3];
    out[o++] = g.nrm[i * 3 + 1];
    out[o++] = g.nrm[i * 3 + 2];
    out[o++] = g.uv[i * 2];
    out[o++] = g.uv[i * 2 + 1];
    out[o++] = colR;
    out[o++] = colG;
    out[o++] = colB;
    if (skin) {
      out[o++] = boneIdx;
    }
  }
  return out;
}

/** 索引化几何打包（保留索引） */
export function geomToIndexedData(g: Geom, colR: number, colG: number, colB: number, skin: boolean,
  boneIndices: Uint16Array | null): VertexData {
  const stride = skin ? 12 : 11;
  const n = g.pos.length / 3;
  const vdata = new Float32Array(n * stride);
  for (let i = 0; i < n; i++) {
    const o = i * stride;
    vdata[o] = g.pos[i * 3];
    vdata[o + 1] = g.pos[i * 3 + 1];
    vdata[o + 2] = g.pos[i * 3 + 2];
    vdata[o + 3] = g.nrm[i * 3];
    vdata[o + 4] = g.nrm[i * 3 + 1];
    vdata[o + 5] = g.nrm[i * 3 + 2];
    vdata[o + 6] = g.uv[i * 2];
    vdata[o + 7] = g.uv[i * 2 + 1];
    vdata[o + 8] = colR;
    vdata[o + 9] = colG;
    vdata[o + 10] = colB;
    if (skin) {
      vdata[o + 11] = boneIndices !== null ? boneIndices[i] : 0;
    }
  }
  return new VertexData(vdata, new Uint32Array(g.idx));
}

export class VertexData {
  vdata: Float32Array;
  idata: Uint32Array;

  constructor(vdata: Float32Array, idata: Uint32Array) {
    this.vdata = vdata;
    this.idata = idata;
  }
}

/**
 * 地图几何合批：按材质累积四边形与几何，最终打包上传。
 * 对应原版 map.js 的 Batch 类。
 */
export class Batch {
  pos: number[] = [];
  nrm: number[] = [];
  uv: number[] = [];
  idx: number[] = [];

  quad(v0: number[], v1: number[], v2: number[], v3: number[], n: number[], uvs: number[]): void {
    const b = this.pos.length / 3;
    this.pos.push(v0[0], v0[1], v0[2], v1[0], v1[1], v1[2], v2[0], v2[1], v2[2], v3[0], v3[1], v3[2]);
    for (let i = 0; i < 4; i++) {
      this.nrm.push(n[0], n[1], n[2]);
    }
    this.uv.push(uvs[0], uvs[1], uvs[2], uvs[3], uvs[4], uvs[5], uvs[6], uvs[7]);
    this.idx.push(b, b + 1, b + 2, b, b + 2, b + 3);
  }

  /** 追加已变换的几何（保留索引） */
  addGeom(g: Geom, m: Mat4): void {
    const mm = m.m;
    const base = this.pos.length / 3;
    const nm = new Float32Array(9); // 法线矩阵（取 3x3，假设均匀缩放）
    for (let c = 0; c < 3; c++) {
      nm[c * 3] = mm[c * 4];
      nm[c * 3 + 1] = mm[c * 4 + 1];
      nm[c * 3 + 2] = mm[c * 4 + 2];
    }
    for (let i = 0; i < g.pos.length; i += 3) {
      const x = g.pos[i], y = g.pos[i + 1], z = g.pos[i + 2];
      this.pos.push(mm[0] * x + mm[4] * y + mm[8] * z + mm[12],
        mm[1] * x + mm[5] * y + mm[9] * z + mm[13],
        mm[2] * x + mm[6] * y + mm[10] * z + mm[14]);
      const nx = g.nrm[i], ny = g.nrm[i + 1], nz = g.nrm[i + 2];
      _tv.set(nm[0] * nx + nm[3] * ny + nm[6] * nz, nm[1] * nx + nm[4] * ny + nm[7] * nz,
        nm[2] * nx + nm[5] * ny + nm[8] * nz);
      _tv.normalize();
      this.nrm.push(_tv.x, _tv.y, _tv.z);
    }
    for (let i = 0; i < g.uv.length; i++) {
      this.uv.push(g.uv[i]);
    }
    for (const i of g.idx) {
      this.idx.push(base + i);
    }
  }

  count(): number {
    return this.pos.length / 3;
  }

  build(colR: number, colG: number, colB: number): VertexData {
    const n = this.count();
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
      vdata[o + 8] = colR;
      vdata[o + 9] = colG;
      vdata[o + 10] = colB;
    }
    return new VertexData(vdata, new Uint32Array(this.idx));
  }
}

/**
 * 简单多边形三角化（ear clipping），points 为 [x,z] 数组。
 * 返回三角形索引，保证法线朝 +Y。
 */
export function triangulatePolygon(points: number[][]): number[] {
  const n = points.length;
  if (n < 3) {
    return [];
  }
  // 计算有符号面积决定绕向
  let area2 = 0;
  for (let i = 0; i < n; i++) {
    const p0 = points[i];
    const p1 = points[(i + 1) % n];
    area2 += p0[0] * p1[1] - p1[0] * p0[1];
  }
  // 内部按 2D 逆时针做耳切，输出时翻转绕向使法线朝 +Y（(x,z) 平面上顺时针）
  const ccw = area2 > 0;
  const order: number[] = [];
  for (let i = 0; i < n; i++) {
    order.push(ccw ? i : n - 1 - i);
  }
  const tris: number[] = [];
  const eps = 1e-10;
  let guard = 0;
  while (order.length > 3 && guard++ < n * n) {
    let clipped = false;
    for (let i = 0; i < order.length; i++) {
      const i0 = order[(i + order.length - 1) % order.length];
      const i1 = order[i];
      const i2 = order[(i + 1) % order.length];
      const a = points[i0], b = points[i1], c = points[i2];
      const cross = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
      if (cross <= eps) {
        continue; // 凹角或共线
      }
      // 检查耳内无其他点
      let ok = true;
      for (const j of order) {
        if (j === i0 || j === i1 || j === i2) {
          continue;
        }
        const p = points[j];
        const d0 = (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]);
        const d1 = (c[0] - b[0]) * (p[1] - b[1]) - (c[1] - b[1]) * (p[0] - b[0]);
        const d2 = (a[0] - c[0]) * (p[1] - c[1]) - (a[1] - c[1]) * (p[0] - c[0]);
        if (d0 > eps && d1 > eps && d2 > eps) {
          ok = false;
          break;
        }
      }
      if (!ok) {
        continue;
      }
      tris.push(i0, i2, i1); // 翻转绕向：法线 +Y
      order.splice(i, 1);
      clipped = true;
      break;
    }
    if (!clipped) {
      break; // 退化，退出
    }
  }
  if (order.length === 3) {
    tris.push(order[0], order[2], order[1]);
  }
  return tris;
}
