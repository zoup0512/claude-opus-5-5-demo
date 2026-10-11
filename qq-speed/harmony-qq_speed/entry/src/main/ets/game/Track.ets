// 赛道中心线采样与投影（自 H5 版 track.js 移植；曲线改为手写闭合向心 Catmull-Rom + 弧长均匀重采样）
import { clamp, wrapAngle } from '../common/Util';
import { Layout } from '../common/Config';

export class TrackSample {
  i: number = 0;
  t: number = 0;
  d: number = 0;
  x: number = 0;
  y: number = 0;
  z: number = 0;
  lat: number = 0;
  tx: number = 0;
  tz: number = 0;
  rx: number = 0;
  rz: number = 0;
  hd: number = 0;
  bank: number = 0;
  slope: number = 0;
  curv: number = 0;
  surfY: number = 0;
}

export class BoostPad {
  d: number = 0;
  lat: number = 0;
  len: number = 11;
  halfW: number = 2.8;
}

export class Track {
  halfW: number = 12;
  wallH: number = 1.25;
  N: number = 0;
  px: Float32Array = new Float32Array(0);
  py: Float32Array = new Float32Array(0);
  pz: Float32Array = new Float32Array(0);
  hd: Float32Array = new Float32Array(0);
  tx: Float32Array = new Float32Array(0);
  tz: Float32Array = new Float32Array(0);
  rx: Float32Array = new Float32Array(0);
  rz: Float32Array = new Float32Array(0);
  curv: Float32Array = new Float32Array(0);
  bank: Float32Array = new Float32Array(0);
  slope: Float32Array = new Float32Array(0);
  vcurv: Float32Array = new Float32Array(0);
  sslope: Float32Array = new Float32Array(0);
  bridge: Uint8Array = new Uint8Array(0);
  length: number = 0;
  ds: number = 0;
  cell: number = 16;
  grid: Map<number, number[]> = new Map<number, number[]>();
  minX: number = 0;
  maxX: number = 0;
  minZ: number = 0;
  maxZ: number = 0;
  cx: number = 0;
  cz: number = 0;
  boostPads: BoostPad[] = [];
  tunnels: number[][] = [];
  private _tmp: TrackSample = new TrackSample();
  private _tmp2: TrackSample = new TrackSample();

  constructor(layout: Layout, isBridgeY: number) {
    this.halfW = layout.width / 2;
    // 闭合向心 Catmull-Rom：稠密采样 → 弧长均匀重采样
    const pts = layout.points;
    const dense: number[][] = [];
    const segs = pts.length;
    const sub = 24;
    for (let i = 0; i < segs; i++) {
      const p0 = pts[(i - 1 + segs) % segs];
      const p1 = pts[i];
      const p2 = pts[(i + 1) % segs];
      const p3 = pts[(i + 2) % segs];
      // 向心参数
      let t0 = 0;
      let t1 = t0 + Math.pow(dist2(p0, p1), 0.25);
      let t2 = t1 + Math.pow(dist2(p1, p2), 0.25);
      let t3 = t2 + Math.pow(dist2(p2, p3), 0.25);
      for (let k = 0; k < sub; k++) {
        const t = t1 + (t2 - t1) * (k / sub);
        const a = p0.map((v) => v);
        const A1 = lerp3(a, p1, (t - t0) / (t1 - t0));
        const A2 = lerp3(p1, p2, (t - t1) / (t2 - t1));
        const A3 = lerp3(p2, p3, (t - t2) / (t3 - t2));
        const B1 = lerp3(A1, A2, (t - t0) / (t2 - t0));
        const B2 = lerp3(A2, A3, (t - t1) / (t3 - t1));
        const C = lerp3(B1, B2, (t - t1) / (t2 - t1));
        dense.push([C[0], C[1], C[2]]);
      }
    }
    // 累计弧长
    const cum: number[] = [0];
    for (let i = 1; i <= dense.length; i++) {
      const a = dense[i - 1];
      const b = dense[i % dense.length];
      cum.push(cum[i - 1] + Math.hypot(b[0] - a[0], b[2] - a[2], b[1] - a[1]));
    }
    const total = cum[dense.length];
    const N = Math.max(64, Math.round(total / 1.5));
    this.N = N;
    this.px = new Float32Array(N);
    this.py = new Float32Array(N);
    this.pz = new Float32Array(N);
    let di = 0;
    for (let i = 0; i < N; i++) {
      const target = (i / N) * total;
      while (di < dense.length - 1 && cum[di + 1] < target) di++;
      const t = (target - cum[di]) / Math.max(1e-6, cum[di + 1] - cum[di]);
      const a = dense[di];
      const b = dense[(di + 1) % dense.length];
      // 布局点为 [x, z, y]：水平面 x/z 取 [0]/[1]，高度取 [2]
      this.px[i] = a[0] + (b[0] - a[0]) * t;
      this.py[i] = a[2] + (b[2] - a[2]) * t;
      this.pz[i] = a[1] + (b[1] - a[1]) * t;
    }
    let len = 0;
    for (let i = 0; i < N; i++) {
      const j = (i + 1) % N;
      len += Math.hypot(this.px[j] - this.px[i], this.pz[j] - this.pz[i]);
    }
    this.length = len;
    this.ds = len / N;

    this.hd = new Float32Array(N);
    this.tx = new Float32Array(N);
    this.tz = new Float32Array(N);
    this.rx = new Float32Array(N);
    this.rz = new Float32Array(N);
    this.curv = new Float32Array(N);
    this.bank = new Float32Array(N);
    this.slope = new Float32Array(N);
    for (let i = 0; i < N; i++) {
      const a = (i - 1 + N) % N;
      const b = (i + 1) % N;
      const h = Math.atan2(this.px[b] - this.px[a], this.pz[b] - this.pz[a]);
      this.hd[i] = h;
      this.tx[i] = Math.sin(h);
      this.tz[i] = Math.cos(h);
      this.rx[i] = -Math.cos(h);
      this.rz[i] = Math.sin(h);
      this.slope[i] = (this.py[b] - this.py[a]) / (2 * this.ds);
    }
    const raw = new Float32Array(N);
    for (let i = 0; i < N; i++) raw[i] = wrapAngle(this.hd[(i + 1) % N] - this.hd[i]) / this.ds;
    const W = 7;
    for (let i = 0; i < N; i++) {
      let s = 0;
      for (let k = -W; k <= W; k++) s += raw[(i + k + N) % N];
      this.curv[i] = s / (2 * W + 1);
    }
    const bk = new Float32Array(N);
    for (let i = 0; i < N; i++) bk[i] = clamp(this.curv[i] * 5.5, -0.13, 0.13);
    for (let i = 0; i < N; i++) {
      let s = 0;
      for (let k = -12; k <= 12; k++) s += bk[(i + k + N) % N];
      this.bank[i] = s / 25;
    }
    const sy = new Float32Array(N);
    for (let i = 0; i < N; i++) {
      let a = 0;
      for (let k = -3; k <= 3; k++) a += this.py[(i + k + N) % N];
      sy[i] = a / 7;
    }
    this.vcurv = new Float32Array(N);
    this.sslope = new Float32Array(N);
    const K = 4;
    for (let i = 0; i < N; i++) {
      const s0 = (sy[i] - sy[(i - K + N) % N]) / (K * this.ds);
      const s1 = (sy[(i + K) % N] - sy[i]) / (K * this.ds);
      this.vcurv[i] = (s1 - s0) / (K * this.ds);
      this.sslope[i] = (sy[(i + 1) % N] - sy[(i - 1 + N) % N]) / (2 * this.ds);
    }
    this.bridge = new Uint8Array(N);
    for (let i = 0; i < N; i++) this.bridge[i] = this.py[i] > isBridgeY ? 1 : 0;

    // 空间哈希
    for (let i = 0; i < N; i++) {
      const k = this.key(Math.floor(this.px[i] / this.cell), Math.floor(this.pz[i] / this.cell));
      let arr = this.grid.get(k);
      if (!arr) {
        arr = [];
        this.grid.set(k, arr);
      }
      arr.push(i);
    }
    let minX = 1e9;
    let maxX = -1e9;
    let minZ = 1e9;
    let maxZ = -1e9;
    for (let i = 0; i < N; i++) {
      if (this.px[i] < minX) minX = this.px[i];
      if (this.px[i] > maxX) maxX = this.px[i];
      if (this.pz[i] < minZ) minZ = this.pz[i];
      if (this.pz[i] > maxZ) maxZ = this.pz[i];
    }
    this.minX = minX;
    this.maxX = maxX;
    this.minZ = minZ;
    this.maxZ = maxZ;
    this.cx = (minX + maxX) / 2;
    this.cz = (minZ + maxZ) / 2;
  }

  private key(cx: number, cz: number): number {
    return (cx * 73856093 ^ cz * 19349663) | 0;
  }

  nearest(x: number, z: number, maxDist: number): number {
    const r = Math.ceil(maxDist / this.cell);
    const cx = Math.floor(x / this.cell);
    const cz = Math.floor(z / this.cell);
    let best = maxDist * maxDist;
    let bi = -1;
    for (let a = -r; a <= r; a++) {
      for (let b = -r; b <= r; b++) {
        const arr = this.grid.get(this.key(cx + a, cz + b));
        if (!arr) continue;
        for (const i of arr) {
          const dx = this.px[i] - x;
          const dz = this.pz[i] - z;
          const d2 = dx * dx + dz * dz;
          if (d2 < best) {
            best = d2;
            bi = i;
          }
        }
      }
    }
    return bi;
  }

  forEachNear(x: number, z: number, maxDist: number, fn: (i: number, dist: number) => void): void {
    const r = Math.ceil(maxDist / this.cell);
    const cx = Math.floor(x / this.cell);
    const cz = Math.floor(z / this.cell);
    const md2 = maxDist * maxDist;
    for (let a = -r; a <= r; a++) {
      for (let b = -r; b <= r; b++) {
        const arr = this.grid.get(this.key(cx + a, cz + b));
        if (!arr) continue;
        for (const i of arr) {
          const dx = this.px[i] - x;
          const dz = this.pz[i] - z;
          const d2 = dx * dx + dz * dz;
          if (d2 < md2) fn(i, Math.sqrt(d2));
        }
      }
    }
  }

  sample(d: number, out?: TrackSample): TrackSample {
    const o = out ?? new TrackSample();
    const L = this.length;
    let dd = ((d % L) + L) % L;
    const f = dd / this.ds;
    const i = Math.floor(f) % this.N;
    const j = (i + 1) % this.N;
    const t = f - Math.floor(f);
    o.i = i;
    o.t = t;
    o.d = dd;
    o.x = this.px[i] + (this.px[j] - this.px[i]) * t;
    o.z = this.pz[i] + (this.pz[j] - this.pz[i]) * t;
    o.y = this.py[i] + (this.py[j] - this.py[i]) * t;
    const h = this.hd[i] + wrapAngle(this.hd[j] - this.hd[i]) * t;
    o.hd = h;
    o.tx = Math.sin(h);
    o.tz = Math.cos(h);
    o.rx = -o.tz;
    o.rz = o.tx;
    o.bank = this.bank[i] + (this.bank[j] - this.bank[i]) * t;
    o.slope = this.slope[i] + (this.slope[j] - this.slope[i]) * t;
    o.curv = this.curv[i] + (this.curv[j] - this.curv[i]) * t;
    o.lat = 0;
    return o;
  }

  freshSample(): TrackSample {
    return new TrackSample();
  }

  project(x: number, y: number, z: number, hint: number, out: TrackSample): TrackSample {
    const N = this.N;
    let bi = 0;
    let best = Infinity;
    if (hint < 0) {
      for (let i = 0; i < N; i++) {
        const dx = this.px[i] - x;
        const dz = this.pz[i] - z;
        const dy = (this.py[i] - y) * 3;
        const d2 = dx * dx + dz * dz + dy * dy;
        if (d2 < best) {
          best = d2;
          bi = i;
        }
      }
    } else {
      for (let k = -30; k <= 30; k++) {
        const i = (hint + k + N) % N;
        const dx = this.px[i] - x;
        const dz = this.pz[i] - z;
        const d2 = dx * dx + dz * dz;
        if (d2 < best) {
          best = d2;
          bi = i;
        }
      }
    }
    let i = bi;
    let j = (i + 1) % N;
    let ex = this.px[j] - this.px[i];
    let ez = this.pz[j] - this.pz[i];
    let t = ((x - this.px[i]) * ex + (z - this.pz[i]) * ez) / (ex * ex + ez * ez);
    if (t < 0) {
      i = (bi - 1 + N) % N;
      j = bi;
      ex = this.px[j] - this.px[i];
      ez = this.pz[j] - this.pz[i];
      t = ((x - this.px[i]) * ex + (z - this.pz[i]) * ez) / (ex * ex + ez * ez);
    }
    t = clamp(t, 0, 1);
    const s = this.sample((i + t) * this.ds, out);
    s.lat = (x - s.x) * s.rx + (z - s.z) * s.rz;
    s.surfY = s.y + s.lat * Math.sin(s.bank);
    return s;
  }

  surfaceY(s: TrackSample, lat: number): number {
    return s.y + lat * Math.sin(s.bank);
  }

  curvAhead(d: number, range: number): number {
    const N = this.N;
    const i0 = Math.floor((((d % this.length) + this.length) % this.length) / this.ds);
    const steps = Math.max(1, Math.floor(range / this.ds));
    let m = 0;
    for (let k = 0; k < steps; k += 2) {
      const c = this.curv[(i0 + k) % N];
      if (Math.abs(c) > Math.abs(m)) m = c;
    }
    return m;
  }

  dAt(x: number, z: number): number {
    const n = this.nearest(x, z, 400);
    return n >= 0 ? n * this.ds : 0;
  }

  inTunnel(d: number): boolean {
    if (!this.tunnels) return false;
    for (const ab of this.tunnels) {
      if ((d > ab[0] && d < ab[1]) || (d + this.length > ab[0] && d + this.length < ab[1])) return true;
    }
    return false;
  }
}

function dist2(a: number[], b: number[]): number {
  const dx = a[0] - b[0];
  const dy = a[1] - b[1];
  const dz = a[2] - b[2];
  return dx * dx + dy * dy + dz * dz;
}

function lerp3(a: number[], b: number[], t: number): number[] {
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
}
