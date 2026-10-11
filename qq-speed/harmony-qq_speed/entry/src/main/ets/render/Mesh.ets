// 静态/动态几何：面 soup（四边形为主），世界坐标烘焙 + 3x4 矩阵用于活动物体
import { Palette } from './Palette';

// 行优先 3x4 矩阵：v' = M·v（旋转 3x3 + 平移）
export class Mat34 {
  m: Float32Array = new Float32Array(12);

  static identity(): Mat34 {
    const t = new Mat34();
    t.m[0] = 1;
    t.m[4] = 1;
    t.m[8] = 1;
    return t;
  }

  static compose(x: number, y: number, z: number, yaw: number, pitch: number, roll: number): Mat34 {
    const t = new Mat34();
    const cy = Math.cos(yaw);
    const sy = Math.sin(yaw);
    const cp = Math.cos(pitch);
    const sp = Math.sin(pitch);
    const cr = Math.cos(roll);
    const sr = Math.sin(roll);
    // 列向量约定 R = Ry·Rx·Rz（YXZ）：v' = M·v
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
    return t;
  }
}

export function matMul(a: Mat34, b: Mat34): Mat34 {
  const out = new Mat34();
  const A = a.m;
  const B = b.m;
  const O = out.m;
  for (let r = 0; r < 3; r++) {
    for (let c = 0; c < 4; c++) {
      let s = 0;
      if (c < 3) {
        s = A[r * 4] * B[c] + A[r * 4 + 1] * B[4 + c] + A[r * 4 + 2] * B[8 + c];
      } else {
        s = A[r * 4] * B[3] + A[r * 4 + 1] * B[7] + A[r * 4 + 2] * B[11] + A[r * 4 + 3];
      }
      O[r * 4 + c] = s;
    }
  }
  return out;
}

export class Mesh {
  v: Float32Array = new Float32Array(0);   // 顶点 xyz
  f: Int32Array = new Int32Array(0);       // 每面 4 个顶点序号（三角形末位 -1）
  col: Uint16Array = new Uint16Array(0);   // 每面调色板 id
  shade: Float32Array = new Float32Array(0);
  nrm: Float32Array | null = null;         // 每面法线（活动物体动态光照用）
  ambient: number = 0.55;
  diffuse: number = 0.55;
  faceCount: number = 0;
  // 包围球（剔除用）
  cx = 0; cy = 0; cz = 0;
  radius: number = 1;
  maxDist: number = 1000;

  // 剔除元数据（赛道分块用）
  dCenter: number = -1; // 沿路中心距离
  dSpan: number = 0;
}

export class MeshBuilder {
  pos: number[] = [];
  idx: number[] = [];
  col: number[] = [];
  shade: number[] = [];
  nrmArr: number[] = [];
  withNormals: boolean = false;
  palette: Palette;
  ambient: number = 0.55;
  diffuse: number = 0.55;

  constructor(palette: Palette, withNormals: boolean = false) {
    this.palette = palette;
    this.withNormals = withNormals;
  }

  private autoShade(nx: number, ny: number, nz: number): number {
    const d = nx * this.palette.sunX + ny * this.palette.sunY + nz * this.palette.sunZ;
    return this.ambient + this.diffuse * Math.max(0, d);
  }

  private vertex(x: number, y: number, z: number): number {
    this.pos.push(x, y, z);
    return this.pos.length / 3 - 1;
  }

  // 四边形 p0→p1→p2→p3，正面法线 = (p1-p0)×(p2-p0)。shade < 0 → 按法线自动光照
  quad(x0: number, y0: number, z0: number,
    x1: number, y1: number, z1: number,
    x2: number, y2: number, z2: number,
    x3: number, y3: number, z3: number,
    colId: number, shade: number): void {
    const ax = x1 - x0;
    const ay = y1 - y0;
    const az = z1 - z0;
    const bx = x2 - x0;
    const by = y2 - y0;
    const bz = z2 - z0;
    let nx = ay * bz - az * by;
    let ny = az * bx - ax * bz;
    let nz = ax * by - ay * bx;
    const l = Math.hypot(nx, ny, nz) || 1;
    nx /= l;
    ny /= l;
    nz /= l;
    const sh = shade >= 0 ? shade : this.autoShade(nx, ny, nz);
    const a = this.vertex(x0, y0, z0);
    const b = this.vertex(x1, y1, z1);
    const c = this.vertex(x2, y2, z2);
    const d = this.vertex(x3, y3, z3);
    this.idx.push(a, b, c, d);
    this.col.push(colId);
    this.shade.push(sh);
    this.nrmArr.push(nx, ny, nz);
  }

  tri(x0: number, y0: number, z0: number,
    x1: number, y1: number, z1: number,
    x2: number, y2: number, z2: number,
    colId: number, shade: number): void {
    this.quad(x0, y0, z0, x1, y1, z1, x2, y2, z2, x2, y2, z2, colId, shade);
    // 三角形复用第 3 点，渲染时按退化四边形处理
    const last = this.idx.length;
    this.idx[last - 1] = -1;
  }

  build(maxDist: number): Mesh {
    const m = new Mesh();
    m.v = new Float32Array(this.pos);
    m.f = new Int32Array(this.idx);
    m.col = new Uint16Array(this.col);
    m.shade = new Float32Array(this.shade);
    if (this.withNormals) m.nrm = new Float32Array(this.nrmArr);
    m.ambient = this.ambient;
    m.diffuse = this.diffuse;
    m.faceCount = this.col.length;
    m.maxDist = maxDist;
    let minX = 1e9, minY = 1e9, minZ = 1e9, maxX = -1e9, maxY = -1e9, maxZ = -1e9;
    const p = this.pos;
    for (let i = 0; i < p.length; i += 3) {
      if (p[i] < minX) minX = p[i];
      if (p[i] > maxX) maxX = p[i];
      if (p[i + 1] < minY) minY = p[i + 1];
      if (p[i + 1] > maxY) maxY = p[i + 1];
      if (p[i + 2] < minZ) minZ = p[i + 2];
      if (p[i + 2] > maxZ) maxZ = p[i + 2];
    }
    if (p.length === 0) {
      minX = maxX = minY = maxY = minZ = maxZ = 0;
    }
    m.cx = (minX + maxX) / 2;
    m.cy = (minY + maxY) / 2;
    m.cz = (minZ + maxZ) / 2;
    m.radius = Math.hypot(maxX - minX, maxY - minY, maxZ - minZ) / 2;
    return m;
  }
}

// 便捷：加一个任意朝向的盒子（中心 cx,cy,cz；尺寸 sx,sy,sz；绕 Y 旋转 yaw）
export function addBox(b: MeshBuilder, cx: number, cy: number, cz: number,
  sx: number, sy: number, sz: number, yaw: number,
  colSide: number, colTop: number, colBottom: number): void {
  const hx = sx / 2;
  const hy = sy / 2;
  const hz = sz / 2;
  const c = Math.cos(yaw);
  const s = Math.sin(yaw);
  // 局部角（绕 Y 旋转）→ 世界
  const P: number[][] = [];
  for (let i = 0; i < 8; i++) {
    const lx = (i & 1 ? hx : -hx);
    const ly = (i & 2 ? hy : -hy);
    const lz = (i & 4 ? hz : -hz);
    P.push([cx + lx * c + lz * s, cy + ly, cz - lx * s + lz * c]);
  }
  // 索引约定：bit0=x bit1=y bit2=z
  const q = (a: number, bb: number, cc: number, d: number, col: number): void => {
    b.quad(P[a][0], P[a][1], P[a][2], P[bb][0], P[bb][1], P[bb][2],
      P[cc][0], P[cc][1], P[cc][2], P[d][0], P[d][1], P[d][2], col, -1);
  };
  // +z 面 (法线朝 +z)
  q(4, 5, 7, 6, colSide);
  // -z 面
  q(1, 0, 2, 3, colSide);
  // +x 面
  q(5, 1, 3, 7, colSide);
  // -x 面
  q(0, 4, 6, 2, colSide);
  // +y 顶面
  q(2, 3, 7, 6, colTop);
  // -y 底面
  q(0, 1, 5, 4, colBottom);
}

// 竖直 n 棱柱（圆柱近似），bottom→top
export function addPrism(b: MeshBuilder, cx: number, y0: number, cz: number,
  r0: number, r1: number, y1: number, n: number, yaw: number,
  colSide: number, colTop: number, colBottom: number): void {
  const px: number[] = [];
  const pz: number[] = [];
  for (let i = 0; i < n; i++) {
    const a = yaw + (i / n) * Math.PI * 2;
    px.push(Math.sin(a));
    pz.push(Math.cos(a));
  }
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n;
    // 侧面（法线朝外）
    b.quad(
      cx + px[i] * r0, y0, cz + pz[i] * r0,
      cx + px[j] * r0, y0, cz + pz[j] * r0,
      cx + px[j] * r1, y1, cz + pz[j] * r1,
      cx + px[i] * r1, y1, cz + pz[i] * r1,
      colSide, -1);
  }
  // 顶盖（扇形三角）
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n;
    b.quad(
      cx, y1, cz,
      cx + px[i] * r1, y1, cz + pz[i] * r1,
      cx + px[j] * r1, y1, cz + pz[j] * r1,
      cx + px[j] * r1, y1, cz + pz[j] * r1,
      colTop, -1);
  }
  if (colBottom >= 0) {
    for (let i = 0; i < n; i++) {
      const j = (i + 1) % n;
      b.quad(
        cx + px[j] * r0, y0, cz + pz[j] * r0,
        cx + px[i] * r0, y0, cz + pz[i] * r0,
        cx, y0, cz,
        cx, y0, cz,
        colBottom, -1);
    }
  }
}

// 竖直圆锥（树冠/金字塔）
export function addCone(b: MeshBuilder, cx: number, y0: number, cz: number,
  r: number, y1: number, n: number, yaw: number, col: number): void {
  const px: number[] = [];
  const pz: number[] = [];
  for (let i = 0; i < n; i++) {
    const a = yaw + (i / n) * Math.PI * 2;
    px.push(Math.sin(a));
    pz.push(Math.cos(a));
  }
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n;
    b.quad(
      cx + px[i] * r, y0, cz + pz[i] * r,
      cx + px[j] * r, y0, cz + pz[j] * r,
      cx, y1, cz,
      cx, y1, cz,
      col, -1);
  }
}
