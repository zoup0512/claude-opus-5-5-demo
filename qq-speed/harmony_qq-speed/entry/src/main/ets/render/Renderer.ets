// ArkTS Canvas 软件级 3D 渲染器：
// 视锥投影 + 近平面裁剪 + 背面剔除 + 桶排序(深度量化) + 同色合批填充 + 调色板雾化
// 低多边形平直着色画风；针对低端机做了路径合批与零分配热路径
import { Palette, FOG_LEVELS } from './Palette';
import { Mesh, Mat34 } from './Mesh';
import { ParticlePool, SkidMarks } from '../game/Effects';

const ZN: number = 0.6; // 近裁剪面

// 每帧面池容量（超出自动扩容）
const POOL_VERTS: number = 1 << 17;
const POOL_FACES: number = 1 << 14;
// 深度桶数（sqrt 非线性，近处细分）
const DEPTH_BANDS: number = 256;
// 同色连续段最大合并面数（限制合批引入的遮挡误差）

export class MountainRing {
  radius: number = 1500;
  heights: number[] = [];   // 采样点高度（世界米）
  colorId: number = 0;
  fog: number = 3;
  yBase: number = -40;
}

export class CloudDot {
  angle: number = 0;
  dist: number = 1200;
  y: number = 260;
  size: number = 260;
  alpha: number = 0.8;
}

export class FrameStat {
  fps: number = 0;
  facesPushed: number = 0;   // 通过剔除进入排序列表的面
  facesFilled: number = 0;   // 实际填充的面
  fills: number = 0;         // fill() 调用次数（合批后）
  runs: number = 0;          // 同色段数
  msFlush: number = 0;       // 排序+填充耗时 ms
  msGeo: number = 0;         // 几何生成(投影/剔除)耗时 ms
  msParts: number = 0;       // 粒子/轮胎印耗时 ms
}

export class Renderer {
  ctx: CanvasRenderingContext2D;
  W: number = 0;
  H: number = 0;
  palette: Palette = new Palette();
  // 相机
  camX = 0; camY = 0; camZ = 0;
  yaw = 0; pitch = 0;
  fov: number = 66;
  private rx = 1; private ry = 0; private rz = 0;      // right
  private ux = 0; private uy = 1; private uz = 0;      // up
  fx = 0; fy = 0; fz = 1;                              // forward（外部剔除用）
  focal: number = 500;
  private cx: number = 0;
  private cy: number = 0;
  cosHalfFov: number = 0.5;                            // 水平半视场角余弦（地形视锥剔除用）
  // 雾
  fogNear: number = 300;
  fogFar: number = 2000;
  viewScale: number = 1;
  // 天空
  skyTop: string = '#2f7fe0';
  skyHorizon: string = '#cfeaff';
  sunX: number = -0.45;
  sunY: number = 0.62;
  sunZ: number = -0.55;
  sunColor: string = '#fff4dc';
  mountains: MountainRing[] = [];
  clouds: CloudDot[] = [];
  mapCx: number = 0;
  mapCz: number = 0;
  // 性能
  stat: FrameStat = new FrameStat();
  lowGfx: boolean = false; // 低画质：跳过 shadowBlur 等昂贵装饰
  // —— 面池（类型化，热路径零分配）——
  private poolX: Float64Array = new Float64Array(POOL_VERTS);
  private poolY: Float64Array = new Float64Array(POOL_VERTS);
  private poolLen: number = 0;
  private fStart: Int32Array = new Int32Array(POOL_FACES);
  private fCount: Int32Array = new Int32Array(POOL_FACES);
  private fZ: Float64Array = new Float64Array(POOL_FACES);
  private fKey: Int32Array = new Int32Array(POOL_FACES);
  private fLen: number = 0;
  private maxZ: number = 1;
  // 桶排序暂存
  private bandCount: Int32Array = new Int32Array(DEPTH_BANDS + 1);
  private order: Int32Array = new Int32Array(POOL_FACES);
  // 顶点暂存（单 mesh）
  private sx: Float64Array = new Float64Array(0);
  private sy: Float64Array = new Float64Array(0);
  private sz: Float64Array = new Float64Array(0);
  // 裁剪暂存
  private cX: number[] = [];
  private cY: number[] = [];
  private cZ: number[] = [];
  private pX: number[] = [];
  private pY: number[] = [];
  // 半透明字符串缓存
  private rgbaCache: Map<number, string> = new Map<number, string>();
  frameTime: number = 0;

  constructor(ctx: CanvasRenderingContext2D) {
    this.ctx = ctx;
  }

  resize(w: number, h: number): void {
    // ArkUI Canvas 的绘制坐标系是 vp，缓冲区由组件决定；只记录逻辑宽高
    this.W = w;
    this.H = h;
    const halfFov = Math.atan((w / 2) / this.focal);
    this.cosHalfFov = Math.cos(halfFov + 0.12); // 留少量余量
  }

  setCamera(x: number, y: number, z: number, yaw: number, pitch: number, fov: number): void {
    this.camX = x;
    this.camY = y;
    this.camZ = z;
    this.yaw = yaw;
    this.pitch = pitch;
    this.fov = fov;
    const cy = Math.cos(yaw);
    const sy = Math.sin(yaw);
    const cp = Math.cos(pitch);
    const sp = Math.sin(pitch);
    this.fx = sy * cp;
    this.fy = sp;
    this.fz = cy * cp;
    this.rx = cy;
    this.ry = 0;
    this.rz = -sy;
    // up = right × forward
    this.ux = this.ry * this.fz - this.rz * this.fy;
    this.uy = this.rz * this.fx - this.rx * this.fz;
    this.uz = this.rx * this.fy - this.ry * this.fx;
    this.focal = (this.H / 2) / Math.tan((fov * Math.PI / 180) / 2);
    this.cx = this.W / 2;
    this.cy = this.H / 2;
    this.cosHalfFov = Math.cos(Math.atan((this.W / 2) / this.focal) + 0.12);
  }

  // 世界坐标 → 屏幕与深度；在相机前方返回 true
  project(x: number, y: number, z: number, out: number[]): boolean {
    const dx = x - this.camX;
    const dy = y - this.camY;
    const dz = z - this.camZ;
    const vz = dx * this.fx + dy * this.fy + dz * this.fz;
    if (vz < ZN) return false;
    const vx = dx * this.rx + dy * this.ry + dz * this.rz;
    const vy = dx * this.ux + dy * this.uy + dz * this.uz;
    out[0] = this.cx + (vx / vz) * this.focal;
    out[1] = this.cy - (vy / vz) * this.focal;
    out[2] = vz;
    return true;
  }

  private fogOf(z: number): number {
    if (z <= this.fogNear) return 0;
    const t = (z - this.fogNear) / (this.fogFar - this.fogNear);
    if (t >= 1) return FOG_LEVELS;
    return Math.round(t * (FOG_LEVELS - 1));
  }

  // ---------- 天空 / 远景 ----------
  // 远山/云缓存：按 (朝向4° / 俯仰2° / fov) 分桶，构建期一次性投影成 Path2D，
  // 之后每帧只做一次 fill(path) —— 把每帧数百次 lineTo+fill 压缩到 2~4 次调用
  private mtnYaw: number = 1e9;
  private mtnPitch: number = 1e9;
  private mtnFov: number = -1;
  private mtnCount: number = 0;
  private skyGradKey: number = -1;
  private skyGrad: CanvasGradient | null = null;

  horizonY(): number {
    return this.cy + Math.tan(this.pitch) * this.focal;
  }

  drawSky(): void {
    const g = this.ctx;
    const hy = this.horizonY();
    const top = Math.min(0, hy);
    // 渐变对象按地平线位置分桶缓存（createLinearGradient 每帧新建开销大）
    const gKey = Math.round(hy / 48);
    if (gKey !== this.skyGradKey || this.skyGrad === null) {
      this.skyGradKey = gKey;
      const grd = g.createLinearGradient(0, top, 0, Math.max(hy + 1, top + 1));
      grd.addColorStop(0, this.skyTop);
      grd.addColorStop(1, this.skyHorizon);
      this.skyGrad = grd;
    }
    g.fillStyle = this.skyGrad;
    g.fillRect(0, 0, this.W, Math.max(0, Math.ceil(hy)));
    // 太阳（低画质用平涂圆代替径向渐变）
    const sd = this.projectDir(this.sunX, this.sunY, this.sunZ);
    if (sd[2] > 0) {
      const r = Math.max(24, this.W * 0.035);
      if (this.lowGfx) {
        g.globalAlpha = 0.35;
        g.fillStyle = this.sunColor;
        g.beginPath();
        g.arc(sd[0], sd[1], r * 2.2, 0, Math.PI * 2);
        g.fill();
        g.globalAlpha = 1;
        g.beginPath();
        g.arc(sd[0], sd[1], r * 0.55, 0, Math.PI * 2);
        g.fill();
      } else {
        const gl = g.createRadialGradient(sd[0], sd[1], 0, sd[0], sd[1], r * 3.2);
        gl.addColorStop(0, this.sunColor);
        gl.addColorStop(0.35, 'rgba(255,244,214,0.45)');
        gl.addColorStop(1, 'rgba(255,244,214,0)');
        g.fillStyle = gl;
        g.fillRect(sd[0] - r * 3.2, sd[1] - r * 3.2, r * 6.4, r * 6.4);
        g.fillStyle = '#fffbe8';
        g.beginPath();
        g.arc(sd[0], sd[1], r * 0.55, 0, Math.PI * 2);
        g.fill();
      }
    }
  }

  // 方向（单位向量）→ 屏幕；out[2] > 0 表示在前方
  private projectDir(dx: number, dy: number, dz: number): number[] {
    const vz = dx * this.fx + dy * this.fy + dz * this.fz;
    if (vz <= 0.0001) {
      return [-9999, -9999, -1];
    }
    const vx = dx * this.rx + dy * this.ry + dz * this.rz;
    const vy = dx * this.ux + dy * this.uy + dz * this.uz;
    return [this.cx + (vx / vz) * this.focal, this.cy - (vy / vz) * this.focal, vz];
  }

  drawClouds(): void {
    // 云并入远山缓存：同一批重建，translate 后一次 fill(path)
    if (this.cloudPath !== null) {
      const g = this.ctx;
      g.save();
      g.translate(0, this.mtnDy());
      g.globalAlpha = 0.7;
      g.fillStyle = '#ffffff';
      g.fill(this.cloudPath);
      g.restore();
      g.globalAlpha = 1;
    }
  }

  // 缓存后相机俯仰/高度的小变化 → 整条天际线的屏幕平移量
  private mtnDy(): number {
    return Math.tan(this.pitch - this.mtnPitch) * this.focal
      + (this.camY - this.mtnCamY) / 1500 * this.focal;
  }

  drawMountains(): void {
    const g = this.ctx;
    // 只按朝向分桶重建（4°）；俯仰/高度变化用 translate 平移补偿
    const qYaw = Math.round(this.yaw / 0.11);
    if (qYaw !== this.mtnYaw || this.fov !== this.mtnFov) {
      this.mtnYaw = qYaw;
      this.mtnPitch = this.pitch;
      this.mtnCamY = this.camY;
      this.mtnFov = this.fov;
      this.mtnPaths = [];
      this.mtnFill = [];
      this.mtnCount = 0;
      this.cloudPath = new Path2D();
      for (const c of this.clouds) {
        const wx = this.mapCx + Math.sin(c.angle) * c.dist;
        const wz = this.mapCz + Math.cos(c.angle) * c.dist;
        const dx = wx - this.camX;
        const dz = wz - this.camZ;
        const dist = Math.hypot(dx, dz, c.y - this.camY);
        const s = this.projectDir(dx / dist, (c.y - this.camY) / dist, dz / dist);
        if (s[2] <= 0) continue;
        const r = (c.size / dist) * this.focal;
        if (r < 6) continue;
        this.cloudPath.ellipse(s[0], s[1], r, r * 0.42, 0, 0, Math.PI * 2);
      }
      for (const ring of this.mountains) {
        const n = ring.heights.length;
        let started = false;
        let lastX = -1e9;
        const p = new Path2D();
        for (let i = 0; i <= n; i++) {
          const k = i % n;
          const wx = this.mapCx + Math.sin((k / n) * Math.PI * 2) * ring.radius;
          const wz = this.mapCz + Math.cos((k / n) * Math.PI * 2) * ring.radius;
          const dx = wx - this.camX;
          const dy = ring.heights[k] - this.camY;
          const dz = wz - this.camZ;
          const dist = Math.hypot(dx, dz);
          if (dist < 1) continue;
          const s = this.projectDir(dx / dist, dy / dist, dz / dist);
          if (s[2] < 0.004) continue;
          if (!started || s[0] >= lastX - 0.5) {
            if (!started) {
              p.moveTo(s[0] - 2, s[1]);
              started = true;
            } else {
              p.lineTo(s[0], s[1]);
            }
            lastX = s[0];
          }
        }
        if (!started) continue;
        p.lineTo(this.W + 2, this.H + 2);
        p.lineTo(-2, this.H + 2);
        p.closePath();
        this.mtnPaths.push(p);
        this.mtnFill.push(this.palette.str(ring.colorId, 1, ring.fog));
        this.mtnCount++;
      }
    }
    // 每帧：translate 补偿 + 缓存 Path 直接填充（每环一次调用）
    const dy = this.mtnDy();
    g.save();
    g.translate(0, dy);
    for (let ri = 0; ri < this.mtnCount; ri++) {
      g.fillStyle = this.mtnFill[ri];
      g.fill(this.mtnPaths[ri]);
    }
    g.restore();
  }

  // 与缓存平行的填充路径与颜色
  private mtnPaths: Path2D[] = [];
  private mtnFill: string[] = [];
  private cloudPath: Path2D | null = null;
  private mtnCamY: number = 0;

  // 大面积水面：地平线以下整片渐变 + 波光（地形随后覆盖陆地部分）
  private waterGradKey: number = -1;
  private waterGrad: CanvasGradient | null = null;

  drawWater(y: number, deep: string, shallow: string, time: number): void {
    const g = this.ctx;
    const hy = this.horizonY();
    if (hy >= this.H) return;
    const gKey = Math.round(hy / 48) * 2 + (this.lowGfx ? 1 : 0);
    if (gKey !== this.waterGradKey || this.waterGrad === null) {
      this.waterGradKey = gKey;
      const grd = g.createLinearGradient(0, hy, 0, this.H);
      grd.addColorStop(0, shallow);
      grd.addColorStop(1, deep);
      this.waterGrad = grd;
    }
    g.fillStyle = this.waterGrad;
    g.fillRect(0, Math.max(0, hy), this.W, this.H - Math.max(0, hy));
    // 太阳反光带（高画质）
    if (!this.lowGfx) {
      const sd = this.projectDir(this.sunX, Math.max(0.01, this.sunY), this.sunZ);
      if (sd[2] > 0) {
        const g2 = g.createLinearGradient(0, hy, 0, this.H);
        g2.addColorStop(0, 'rgba(255,250,230,0.5)');
        g2.addColorStop(1, 'rgba(255,250,230,0)');
        g.fillStyle = g2;
        g.fillRect(sd[0] - this.W * 0.06, hy, this.W * 0.12, this.H - hy);
      }
    }
    // 波纹线（低画质 1 行；高画质 3 行）
    g.strokeStyle = 'rgba(255,255,255,0.10)';
    g.lineWidth = Math.max(1, this.H / 480);
    const rows = this.lowGfx ? 1 : 3;
    const step = this.lowGfx ? 64 : 32;
    for (let i = 0; i < rows; i++) {
      const t = (time * 0.05 + i / rows) % 1;
      const yy = hy + t * t * (this.H - hy);
      g.globalAlpha = (1 - t) * 0.5;
      g.beginPath();
      const amp = 6 + t * 40;
      const ph = time * (1 + i * 0.3) + i * 3;
      for (let x = 0; x <= this.W; x += step) {
        const y2 = yy + Math.sin(x * 0.013 + ph) * amp * 0.2;
        if (x === 0) g.moveTo(x, y2);
        else g.lineTo(x, y2);
      }
      g.stroke();
    }
    g.globalAlpha = 1;
  }

  // ---------- 几何列表 ----------
  clearList(): void {
    this.poolLen = 0;
    this.fLen = 0;
    this.maxZ = ZN + 1;
    this.stat.facesPushed = 0;
    this.stat.facesFilled = 0;
    this.stat.fills = 0;
    this.stat.runs = 0;
  }

  private pushFace(px: number[], py: number[], z: number, key: number): void {
    const n = px.length;
    if (n < 3) return;
    // 背面剔除（屏幕空间有向面积）
    let area = 0;
    for (let i = 0; i < n; i++) {
      const j = (i + 1) % n;
      area += px[i] * py[j] - px[j] * py[i];
    }
    if (area <= 0.5) return;
    // 屏幕外剔除
    let minX = px[0];
    let maxX = px[0];
    let minY = py[0];
    let maxY = py[0];
    for (let i = 1; i < n; i++) {
      const x = px[i];
      const y = py[i];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    if (maxX < 0 || minX > this.W || maxY < 0 || minY > this.H) return;
    // 近平面投影爆炸防护：包围盒超过屏幕 6 倍的面视为退化（正常近景面不会这么大）
    if (maxX - minX > this.W * 6 || maxY - minY > this.H * 6) return;
    let fl = this.fLen;
    if (fl >= POOL_FACES) return;
    let v = this.poolLen;
    if (v + n > POOL_VERTS) return;
    for (let i = 0; i < n; i++) {
      this.poolX[v] = px[i];
      this.poolY[v] = py[i];
      v++;
    }
    this.poolLen = v;
    this.fStart[fl] = v - n;
    this.fCount[fl] = n;
    this.fZ[fl] = z;
    this.fKey[fl] = key;
    this.fLen = fl + 1;
    if (z > this.maxZ) this.maxZ = z;
    this.stat.facesPushed++;
  }

  pushWorldQuad(x0: number, y0: number, z0: number,
    x1: number, y1: number, z1: number,
    x2: number, y2: number, z2: number,
    x3: number, y3: number, z3: number,
    colId: number, shade: number): void {
    const d0x = x0 - this.camX, d0y = y0 - this.camY, d0z = z0 - this.camZ;
    const d1x = x1 - this.camX, d1y = y1 - this.camY, d1z = z1 - this.camZ;
    const d2x = x2 - this.camX, d2y = y2 - this.camY, d2z = z2 - this.camZ;
    const d3x = x3 - this.camX, d3y = y3 - this.camY, d3z = z3 - this.camZ;
    const z0v = d0x * this.fx + d0y * this.fy + d0z * this.fz;
    const z1v = d1x * this.fx + d1y * this.fy + d1z * this.fz;
    const z2v = d2x * this.fx + d2y * this.fy + d2z * this.fz;
    const z3v = d3x * this.fx + d3y * this.fy + d3z * this.fz;
    if (z0v < ZN || z1v < ZN || z2v < ZN || z3v < ZN) return;
    const zm = (z0v + z1v + z2v + z3v) / 4;
    const fog = this.fogOf(zm);
    if (fog >= FOG_LEVELS) return;
    const x0v = d0x * this.rx + d0y * this.ry + d0z * this.rz;
    const y0v = d0x * this.ux + d0y * this.uy + d0z * this.uz;
    const x1v = d1x * this.rx + d1y * this.ry + d1z * this.rz;
    const y1v = d1x * this.ux + d1y * this.uy + d1z * this.uz;
    const x2v = d2x * this.rx + d2y * this.ry + d2z * this.rz;
    const y2v = d2x * this.ux + d2y * this.uy + d2z * this.uz;
    const x3v = d3x * this.rx + d3y * this.ry + d3z * this.rz;
    const y3v = d3x * this.ux + d3y * this.uy + d3z * this.uz;
    this.pX.length = 0;
    this.pY.length = 0;
    this.pX.push(this.cx + (x0v / z0v) * this.focal, this.cx + (x1v / z1v) * this.focal,
      this.cx + (x2v / z2v) * this.focal, this.cx + (x3v / z3v) * this.focal);
    this.pY.push(this.cy - (y0v / z0v) * this.focal, this.cy - (y1v / z1v) * this.focal,
      this.cy - (y2v / z2v) * this.focal, this.cy - (y3v / z3v) * this.focal);
    this.pushFace(this.pX, this.pY, zm, this.palette.keyOf(colId, shade, fog));
  }

  // 通用网格绘制：支持可选模型矩阵（活动物体）与按朝向的动态光照
  drawMesh(mesh: Mesh, mat: Mat34 | null, dynYaw: number): void {
    let bcx = mesh.cx;
    let bcy = mesh.cy;
    let bcz = mesh.cz;
    if (mat) {
      const m = mat.m;
      const nx = m[0] * bcx + m[1] * bcy + m[2] * bcz + m[3];
      const ny = m[4] * bcx + m[5] * bcy + m[6] * bcz + m[7];
      const nz = m[8] * bcx + m[9] * bcy + m[10] * bcz + m[11];
      bcx = nx;
      bcy = ny;
      bcz = nz;
    }
    const dx = bcx - this.camX;
    const dy = bcy - this.camY;
    const dz = bcz - this.camZ;
    const dist = Math.hypot(dx, dy, dz);
    if (dist > mesh.maxDist * this.viewScale + mesh.radius) return;
    const fwdDot = dx * this.fx + dy * this.fy + dz * this.fz;
    if (fwdDot < -mesh.radius) return;
    // 视锥角度剔除（包围球超出视锥整片跳过）
    if (dist > mesh.radius * 1.05) {
      const cosang = fwdDot / dist;
      if (cosang < this.cosHalfFov - mesh.radius * 1.8 / dist) return;
    }

    const nv = mesh.v.length / 3;
    if (this.sz.length < nv) {
      this.sx = new Float64Array(nv);
      this.sy = new Float64Array(nv);
      this.sz = new Float64Array(nv);
    }
    const m = mat ? mat.m : null;
    const v = mesh.v;
    for (let i = 0; i < nv; i++) {
      let wx = v[i * 3];
      let wy = v[i * 3 + 1];
      let wz = v[i * 3 + 2];
      if (m) {
        const ox = wx;
        const oy = wy;
        const oz = wz;
        wx = m[0] * ox + m[1] * oy + m[2] * oz + m[3];
        wy = m[4] * ox + m[5] * oy + m[6] * oz + m[7];
        wz = m[8] * ox + m[9] * oy + m[10] * oz + m[11];
      }
      const px = wx - this.camX;
      const py = wy - this.camY;
      const pz = wz - this.camZ;
      this.sx[i] = px * this.rx + py * this.ry + pz * this.rz;
      this.sy[i] = px * this.ux + py * this.uy + pz * this.uz;
      this.sz[i] = px * this.fx + py * this.fy + pz * this.fz;
    }

    const cosY = dynYaw !== 0 ? Math.cos(dynYaw) : 1;
    const sinY = dynYaw !== 0 ? Math.sin(dynYaw) : 0;
    const f = mesh.f;
    const nFaces = mesh.faceCount;
    for (let fi = 0; fi < nFaces; fi++) {
      const i0 = f[fi * 4];
      const i1 = f[fi * 4 + 1];
      const i2 = f[fi * 4 + 2];
      const i3 = f[fi * 4 + 3];
      const z0 = this.sz[i0];
      const z1 = this.sz[i1];
      const z2 = this.sz[i2];
      const z3 = i3 >= 0 ? this.sz[i3] : z2;
      const zmin = Math.min(z0, Math.min(z1, Math.min(z2, z3)));
      if (zmin < ZN) {
        if (z0 < ZN && z1 < ZN && z2 < ZN && (i3 < 0 || z3 < ZN)) continue;
        this.clipAndPush(mesh, fi, dynYaw, cosY, sinY);
        continue;
      }
      const zm = (z0 + z1 + z2 + z3) / (i3 >= 0 ? 4 : 3);
      const fog = this.fogOf(zm);
      if (fog >= FOG_LEVELS) continue;
      this.pX.length = 0;
      this.pY.length = 0;
      this.pX.push(this.cx + (this.sx[i0] / z0) * this.focal, this.cx + (this.sx[i1] / z1) * this.focal,
        this.cx + (this.sx[i2] / z2) * this.focal);
      this.pY.push(this.cy - (this.sy[i0] / z0) * this.focal, this.cy - (this.sy[i1] / z1) * this.focal,
        this.cy - (this.sy[i2] / z2) * this.focal);
      if (i3 >= 0) {
        this.pX.push(this.cx + (this.sx[i3] / z3) * this.focal);
        this.pY.push(this.cy - (this.sy[i3] / z3) * this.focal);
      }
      this.pushFace(this.pX, this.pY, zm, this.palette.keyOf(mesh.col[fi], this.dynShade(mesh, fi, cosY, sinY), fog));
    }
  }

  private dynShade(mesh: Mesh, fi: number, cosY: number, sinY: number): number {
    if (mesh.nrm === null) return mesh.shade[fi];
    const nx = mesh.nrm[fi * 3];
    const ny = mesh.nrm[fi * 3 + 1];
    const nz = mesh.nrm[fi * 3 + 2];
    const rx2 = nx * cosY + nz * sinY;
    const rz2 = -nx * sinY + nz * cosY;
    const d = rx2 * this.sunX + ny * this.sunY + rz2 * this.sunZ;
    return mesh.ambient + mesh.diffuse * Math.max(0, d);
  }

  private clipAndPush(mesh: Mesh, fi: number, dynYaw: number, cosY: number, sinY: number): void {
    const f = mesh.f;
    this.cX.length = 0;
    this.cY.length = 0;
    this.cZ.length = 0;
    for (let k = 0; k < 4; k++) {
      const i = f[fi * 4 + k];
      if (i < 0) continue;
      this.cX.push(this.sx[i]);
      this.cY.push(this.sy[i]);
      this.cZ.push(this.sz[i]);
    }
    const outX: number[] = [];
    const outY: number[] = [];
    const outZ: number[] = [];
    const n = this.cX.length;
    for (let i = 0; i < n; i++) {
      const j = (i + 1) % n;
      const za = this.cZ[i];
      const zb = this.cZ[j];
      if (za >= ZN) {
        outX.push(this.cX[i]);
        outY.push(this.cY[i]);
        outZ.push(za);
        if (zb < ZN) {
          const t = (ZN - za) / (zb - za);
          outX.push(this.cX[i] + (this.cX[j] - this.cX[i]) * t);
          outY.push(this.cY[i] + (this.cY[j] - this.cY[i]) * t);
          outZ.push(ZN);
        }
      } else if (zb >= ZN) {
        const t = (ZN - za) / (zb - za);
        outX.push(this.cX[i] + (this.cX[j] - this.cX[i]) * t);
        outY.push(this.cY[i] + (this.cY[j] - this.cY[i]) * t);
        outZ.push(ZN);
      }
    }
    if (outX.length < 3) return;
    let zs = 0;
    this.pX.length = 0;
    this.pY.length = 0;
    for (let i = 0; i < outX.length; i++) {
      const z = outZ[i];
      zs += z;
      this.pX.push(this.cx + (outX[i] / z) * this.focal);
      this.pY.push(this.cy - (outY[i] / z) * this.focal);
    }
    const zm = zs / outX.length;
    const fog = this.fogOf(zm);
    if (fog >= FOG_LEVELS) return;
    this.pushFace(this.pX, this.pY, zm, this.palette.keyOf(mesh.col[fi], this.dynShade(mesh, fi, cosY, sinY), fog));
  }

  // ---------- 排序 + 同色合批填充 ----------
  // 深度量化到 256 个 sqrt 非线性桶（O(n) 计数排序），
  // 桶内按「连续同色段」合并为一个 Path 一次 fill（fill 调用次数降 1~2 个数量级）
  flushGeometry(): void {
    const t0 = Date.now();
    const g = this.ctx;
    const n = this.fLen;
    if (n > 0) {
      const bands = DEPTH_BANDS;
      const counts = this.bandCount;
      counts.fill(0);
      let zSpan = this.maxZ - ZN;
      if (zSpan <= 0.001) zSpan = 0.001;
      // pass1: 计数
      for (let i = 0; i < n; i++) {
        const t = Math.sqrt(Math.max(0, this.fZ[i] - ZN) / zSpan);
        let b = (t * bands) | 0;
        if (b >= bands) b = bands - 1;
        counts[b]++;
        this.fKey[i] = this.fKey[i] | (b << 20); // 高位存桶号（key < 2^20）
      }
      // 前缀和 → 起始偏移（桶号大的 = 更远 = 先画）
      let acc = 0;
      for (let b = bands - 1; b >= 0; b--) {
        const c = counts[b];
        counts[b] = acc;
        acc += c;
      }
      // pass2: 放置（桶内保序）
      for (let i = 0; i < n; i++) {
        const b = this.fKey[i] >>> 20;
        this.order[counts[b]++] = i;
      }
      // 还原 key 并绘制：远→近逐桶；桶内按颜色分组，同色一次 fill
      // （深度薄片内遮挡近似成立，同色互遮不可见，合批安全）
      const pal = this.palette;
      let idx = 0;
      const gKeys = this.grpKeys;
      const gCnt = this.grpCnt;
      while (idx < n) {
        const band = this.fKey[this.order[idx]] >>> 20;
        let cnt = 0;
        while (idx + cnt < n && (this.fKey[this.order[idx + cnt]] >>> 20) === band) {
          const fi = this.order[idx + cnt];
          this.fKey[fi] = this.fKey[fi] & 0xFFFFF;
          this.bandIdx[cnt] = fi;
          cnt++;
        }
        // 组装组
        let nG = 0;
        for (let k = 0; k < cnt; k++) {
          const key = this.fKey[this.bandIdx[k]];
          let gi = 0;
          while (gi < nG && gKeys[gi] !== key) gi++;
          if (gi === nG) {
            gKeys[nG] = key;
            gCnt[nG] = 0;
            nG++;
          }
          gCnt[gi]++;
        }
        // 逐组绘制
        for (let gi = 0; gi < nG; gi++) {
          const key = gKeys[gi];
          g.beginPath();
          let emitted = 0;
          for (let k = 0; k < cnt && emitted < gCnt[gi]; k++) {
            const fi = this.bandIdx[k];
            if (this.fKey[fi] !== key) continue;
            emitted++;
            const s = this.fStart[fi];
            const fc = this.fCount[fi];
            g.moveTo(this.poolX[s], this.poolY[s]);
            for (let k2 = 1; k2 < fc; k2++) {
              g.lineTo(this.poolX[s + k2], this.poolY[s + k2]);
            }
            g.closePath();
          }
          g.fillStyle = pal.strByKey(key);
          g.fill();
          this.stat.fills++;
          this.stat.facesFilled += gCnt[gi];
        }
        this.stat.runs += nG;
        idx += cnt;
      }
    }
    this.msFlushInternal = Date.now() - t0;
  }

  private grpKeys: Int32Array = new Int32Array(64);
  private grpCnt: Int32Array = new Int32Array(64);
  private bandIdx: Int32Array = new Int32Array(POOL_FACES);

  private msFlushInternal: number = 0;

  getFlushMs(): number {
    return this.msFlushInternal;
  }

  // ---------- 粒子 / 轮胎印 ----------
  private rgba(r: number, g2: number, b: number, a: number): string {
    const rq = Math.round(r * 15) & 15;
    const gq = Math.round(g2 * 15) & 15;
    const bq = Math.round(b * 15) & 15;
    const aq = Math.round(a * 11);
    const key = (((rq * 16 + gq) * 16 + bq) * 12 + aq);
    const hit = this.rgbaCache.get(key);
    if (hit !== undefined) return hit;
    const s = 'rgba(' + Math.round(r * 255) + ',' + Math.round(g2 * 255) + ',' + Math.round(b * 255) + ',' + (aq / 11).toFixed(2) + ')';
    this.rgbaCache.set(key, s);
    return s;
  }

  private tmpP: number[] = [0, 0, 0];

  drawParticles(p: ParticlePool, additive: boolean): void {
    const g = this.ctx;
    if (additive) {
      try {
        g.globalCompositeOperation = 'lighter';
      } catch (e) {
        // 低版本回退：普通合成
      }
    }
    const fogR = (this.palette.fogColor >> 16) & 255;
    const fogG = (this.palette.fogColor >> 8) & 255;
    const fogB = this.palette.fogColor & 255;
    for (let i = 0; i < p.max; i++) {
      const life = p.life[i];
      if (life <= 0) continue;
      const ok = this.project(p.pos[i * 3], p.pos[i * 3 + 1], p.pos[i * 3 + 2], this.tmpP);
      if (!ok) continue;
      const z = this.tmpP[2];
      if (z > this.fogFar) continue;
      const size = (p.curSize[i] / z) * this.focal;
      if (size < 0.7 || this.tmpP[0] < -size || this.tmpP[0] > this.W + size || this.tmpP[1] < -size || this.tmpP[1] > this.H + size) continue;
      const k = 1 - life / p.maxLife[i];
      const alpha = p.a0[i] * (1 - k) * Math.min(1, k * 8 + 0.2);
      if (alpha <= 0.02) continue;
      const fogT = this.fogOf(z) / (FOG_LEVELS - 1);
      let r = p.rgb[i * 3] * 255;
      let gg = p.rgb[i * 3 + 1] * 255;
      let b = p.rgb[i * 3 + 2] * 255;
      r = r + (fogR - r) * fogT * 0.7;
      gg = gg + (fogG - gg) * fogT * 0.7;
      b = b + (fogB - b) * fogT * 0.7;
      g.fillStyle = this.rgba(r / 255, gg / 255, b / 255, alpha * (additive ? 0.9 : 1));
      const h = size / 2;
      g.fillRect(this.tmpP[0] - h, this.tmpP[1] - h, size, size);
    }
    if (additive) {
      g.globalCompositeOperation = 'source-over';
    }
  }

  drawSkids(sk: SkidMarks): void {
    // 全部轮胎印同色 → 单路径一次 fill
    const g = this.ctx;
    g.beginPath();
    let any = false;
    for (let q = 0; q < sk.count; q++) {
      const o = (sk.head + q) % sk.max;
      if (sk.strength[o] <= 0) continue;
      // 先投影 4 点，任一在相机后则整块跳过
      let ok = true;
      for (let k = 0; k < 4; k++) {
        if (!this.project(sk.pos[o * 12 + k * 3], sk.pos[o * 12 + k * 3 + 1], sk.pos[o * 12 + k * 3 + 2], this.tmpP)) {
          ok = false;
          break;
        }
        this.qX[k] = this.tmpP[0];
        this.qY[k] = this.tmpP[1];
      }
      if (!ok) continue;
      g.moveTo(this.qX[0], this.qY[0]);
      g.lineTo(this.qX[1], this.qY[1]);
      g.lineTo(this.qX[2], this.qY[2]);
      g.lineTo(this.qX[3], this.qY[3]);
      g.closePath();
      any = true;
    }
    if (any) {
      g.fillStyle = 'rgba(12,12,16,0.4)';
      g.fill();
    }
  }

  private qX: number[] = [0, 0, 0, 0];
  private qY: number[] = [0, 0, 0, 0];

  // 屏幕上覆盖文字（排行榜名签 / 3D 场景内提示）；labelStroke=false 时省掉 strokeText
  labelStroke: boolean = true;

  drawLabel(text: string, wx: number, wy: number, wz: number, px: number, bold: boolean, glow: string): void {
    if (!this.project(wx, wy, wz, this.tmpP)) return;
    if (this.tmpP[2] > this.fogFar * 0.9) return;
    const g = this.ctx;
    g.font = (bold ? '900 ' : '700 ') + px + 'px sans-serif';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    if (this.labelStroke && !this.lowGfx) {
      g.lineWidth = px * 0.22;
      g.strokeStyle = 'rgba(0,0,0,0.7)';
      g.strokeText(text, this.tmpP[0], this.tmpP[1]);
    }
    g.fillStyle = glow;
    g.fillText(text, this.tmpP[0], this.tmpP[1]);
  }
}
