// 通用数学 / 随机 / 噪声工具（自 H5 版 util.js 移植，ArkTS 化）

export function clamp(v: number, a: number, b: number): number {
  return v < a ? a : v > b ? b : v;
}

export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

export function damp(a: number, b: number, lambda: number, dt: number): number {
  return lerp(a, b, 1 - Math.exp(-lambda * dt));
}

export function smoothstep(a: number, b: number, x: number): number {
  const t = clamp((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
}

export function wrapAngle(a: number): number {
  let r = a;
  while (r > Math.PI) r -= Math.PI * 2;
  while (r < -Math.PI) r += Math.PI * 2;
  return r;
}

export function dampAngle(a: number, b: number, lambda: number, dt: number): number {
  return a + wrapAngle(b - a) * (1 - Math.exp(-lambda * dt));
}

// 32 位整数乘法（替代 Math.imul，保证 ArkTS 兼容）
export function imul32(a: number, b: number): number {
  const ah = (a >>> 16) & 0xffff;
  const al = a & 0xffff;
  const bh = (b >>> 16) & 0xffff;
  const bl = b & 0xffff;
  const lo = al * bl;
  const mid = (ah * bl + al * bh) << 16;
  return ((lo + mid) >>> 0) | 0;
}

// mulberry32 伪随机数
export type Rng = () => number;

export function mulberry32(seed: number): Rng {
  let s = seed >>> 0;
  const f: Rng = () => {
    s = (s + 0x6d2b79f5) | 0;
    let t = imul32(s ^ (s >>> 15), 1 | s);
    t = (t + imul32(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return f;
}

// 简单 2D value noise，用于地形
export class Noise2D {
  private perm: Uint8Array = new Uint8Array(512);
  private grad: Float32Array = new Float32Array(256);

  constructor(seed: number) {
    const rnd = mulberry32(seed);
    const p: number[] = [];
    for (let i = 0; i < 256; i++) p.push(i);
    for (let i = 255; i > 0; i--) {
      const j = Math.floor(rnd() * (i + 1));
      const t = p[i];
      p[i] = p[j];
      p[j] = t;
    }
    for (let i = 0; i < 512; i++) this.perm[i] = p[i & 255];
    for (let i = 0; i < 256; i++) this.grad[i] = rnd() * 2 - 1;
  }

  private fade(t: number): number {
    return t * t * t * (t * (t * 6 - 15) + 10);
  }

  at(x: number, y: number): number {
    const xi = Math.floor(x);
    const yi = Math.floor(y);
    const xf = x - xi;
    const yf = y - yi;
    const X = xi & 255;
    const Y = yi & 255;
    const a = this.grad[this.perm[X + this.perm[Y]]];
    const b = this.grad[this.perm[X + 1 + this.perm[Y]]];
    const c = this.grad[this.perm[X + this.perm[Y + 1]]];
    const d = this.grad[this.perm[X + 1 + this.perm[Y + 1]]];
    const u = this.fade(xf);
    const v = this.fade(yf);
    return lerp(lerp(a, b, u), lerp(c, d, u), v);
  }

  fbm(x: number, y: number, oct: number): number {
    let s = 0;
    let amp = 0.5;
    let f = 1;
    for (let i = 0; i < oct; i++) {
      s += amp * this.at(x * f, y * f);
      f *= 2.03;
      amp *= 0.5;
    }
    return s;
  }
}

export function formatTime(t: number): string {
  if (!isFinite(t) || t <= 0) {
    return '--:--.--';
  }
  const m = Math.floor(t / 60);
  const s = t - m * 60;
  const ss = s.toFixed(2);
  const padded = ss.length >= 5 ? ss : '0' + ss;
  const ms = m < 10 ? '0' + m : '' + m;
  return ms + ':' + padded;
}

export function hex6(c: number): string {
  const s = c.toString(16);
  return '#' + '000000'.substring(0, 6 - s.length) + s;
}
