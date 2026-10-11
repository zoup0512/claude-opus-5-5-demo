/**
 * 程序化纹理：全部由像素运算生成（移植自原版 textures.js 并简化）。
 * 输出 TexData {w, h, pixels(RGBA)}，由 Game 层上传到原生渲染器。
 */

export function mulberry32(a: number): () => number {
  let s = a | 0;
  return function (): number {
    s |= 0;
    s = (s + 0x6D2B79F5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** 可平铺 fBm 值噪声 0..1 */
export function fbm(w: number, h: number, fx: number, fy: number, octaves: number, seed: number,
  persistence: number = 0.5): Float32Array {
  const out = new Float32Array(w * h);
  const rnd = mulberry32(seed);
  let amp = 1;
  let total = 0;
  for (let o = 0; o < octaves; o++) {
    const gx = (fx << o), gy = (fy << o);
    const lat = new Float32Array(gx * gy);
    for (let i = 0; i < lat.length; i++) {
      lat[i] = rnd();
    }
    const sxs = gx / w, sys = gy / h;
    for (let y = 0; y < h; y++) {
      const fyy = y * sys, y0 = fyy | 0, ty = fyy - y0, sy = ty * ty * (3 - 2 * ty);
      const r0 = (y0 % gy) * gx, r1 = ((y0 + 1) % gy) * gx;
      for (let x = 0; x < w; x++) {
        const fxx = x * sxs, x0 = fxx | 0, tx = fxx - x0, sx = tx * tx * (3 - 2 * tx);
        const c0 = x0 % gx, c1 = (x0 + 1) % gx;
        const a = lat[r0 + c0], b = lat[r0 + c1], c = lat[r1 + c0], d = lat[r1 + c1];
        const top = a + (b - a) * sx, bot = c + (d - c) * sx;
        out[y * w + x] += amp * (top + (bot - top) * sy);
      }
    }
    total += amp;
    amp *= persistence;
  }
  for (let i = 0; i < out.length; i++) {
    out[i] /= total;
  }
  return out;
}

export class TexData {
  w: number;
  h: number;
  pixels: Uint8Array;

  constructor(w: number, h: number, pixels: Uint8Array) {
    this.w = w;
    this.h = h;
    this.pixels = pixels;
  }
}

class PixBuf {
  w: number;
  h: number;
  data: Uint8ClampedArray;

  constructor(w: number, h: number) {
    this.w = w;
    this.h = h;
    this.data = new Uint8ClampedArray(w * h * 4);
    for (let i = 3; i < this.data.length; i += 4) {
      this.data[i] = 255;
    }
  }

  set(x: number, y: number, r: number, g: number, b: number, a: number = 255): void {
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) {
      return;
    }
    const i = (y * this.w + x) * 4;
    this.data[i] = r;
    this.data[i + 1] = g;
    this.data[i + 2] = b;
    this.data[i + 3] = a;
  }

  blend(x: number, y: number, r: number, g: number, b: number, a: number): void {
    if (x < 0 || y < 0 || x >= this.w || y >= this.h || a <= 0) {
      return;
    }
    const i = (y * this.w + x) * 4;
    const ia = Math.min(1, a);
    const d = this.data;
    d[i] = d[i] * (1 - ia) + r * ia;
    d[i + 1] = d[i + 1] * (1 - ia) + g * ia;
    d[i + 2] = d[i + 2] * (1 - ia) + b * ia;
    d[i + 3] = Math.min(255, d[i + 3] + ia * 255);
  }

  toTex(): TexData {
    const u8 = new Uint8Array(this.data.length);
    for (let i = 0; i < this.data.length; i++) {
      u8[i] = this.data[i];
    }
    return new TexData(this.w, this.h, u8);
  }
}

function clamp255(v: number): number {
  return v < 0 ? 0 : v > 255 ? 255 : v;
}

/** 白色 1x1（纯色材质用） */
export function makeWhite(): TexData {
  const p = new PixBuf(4, 4);
  for (let y = 0; y < 4; y++) {
    for (let x = 0; x < 4; x++) {
      p.set(x, y, 255, 255, 255);
    }
  }
  return p.toTex();
}

/** 甲板钢板：板块接缝 + 铆钉 + 锈迹 + 噪声 */
export function makeDeck(): TexData {
  const S = 256;
  const p = new PixBuf(S, S);
  const n1 = fbm(S, S, 8, 8, 4, 11);
  const n2 = fbm(S, S, 32, 32, 3, 12);
  const rnd = mulberry32(13);
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const i = y * S + x;
      let v = 0.5 + n1[i] * 0.22 + (n2[i] - 0.5) * 0.12;
      // 板缝十字网格（每 64px）
      const gx = x % 64, gy = y % 64;
      if (gx < 2 || gy < 2) {
        v *= 0.6;
      }
      if (gx > 60 || gy > 60) {
        v *= 1.06;
      }
      // 铆钉
      const rx = (gx - 32), ry = (gy - 32);
      const rd = Math.sqrt(rx * rx + ry * ry);
      if (rd > 20 && rd < 23 && Math.abs(rx) < Math.abs(ry) * 2.5 && Math.abs(ry) < Math.abs(rx) * 2.5) {
        v *= 1.2;
      }
      const g = clamp255(v * 168);
      p.set(x, y, g * 0.96, g, g * 1.08);
    }
  }
  // 锈迹条纹
  for (let i = 0; i < 26; i++) {
    const x0 = (rnd() * S) | 0;
    const y0 = (rnd() * S) | 0;
    const len = 20 + rnd() * 70;
    const wd = 1 + rnd() * 4;
    for (let yy = 0; yy < len; yy++) {
      for (let xx = 0; xx < wd; xx++) {
        const a = 0.28 * (1 - yy / len);
        p.blend((x0 + xx) % S, (y0 + yy) % S, 128, 66, 30, a);
      }
    }
  }
  return p.toTex();
}

export interface ContainerColor {
  name: string;
  r: number;
  g: number;
  b: number;
}

export const CONTAINER_COLORS: ContainerColor[] = [
  { name: '橙', r: 186, g: 78, b: 36 },
  { name: '蓝', r: 42, g: 82, b: 138 },
  { name: '绿', r: 62, g: 104, b: 64 },
  { name: '红', r: 148, g: 46, b: 42 },
  { name: '黄', r: 176, g: 142, b: 48 },
  { name: '灰', r: 108, g: 114, b: 120 },
  { name: '棕', r: 110, g: 76, b: 48 },
  { name: '青', r: 46, g: 118, b: 116 }
];

/** 集装箱侧板：竖向瓦楞 + 磨损 + 编号区 */
export function makeContainer(idx: number): TexData {
  const S = 256;
  const p = new PixBuf(S, S);
  const col = CONTAINER_COLORS[idx % CONTAINER_COLORS.length];
  const n = fbm(S, S, 16, 16, 4, 20 + idx);
  const n2 = fbm(S, S, 64, 64, 3, 30 + idx);
  const rnd = mulberry32(40 + idx);
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const i = y * S + x;
      // 瓦楞：周期 32px，波谷暗波峰亮
      const ph = (x % 32) / 32;
      const corr = 0.78 + Math.sin(ph * Math.PI * 2) * 0.16 + (ph < 0.06 || ph > 0.94 ? -0.12 : 0);
      let mul = corr * (0.86 + n[i] * 0.24 + (n2[i] - 0.5) * 0.1);
      // 上下边框加强
      if (y < 10 || y > S - 10) {
        mul *= 0.72;
      }
      p.set(x, y, clamp255(col.r * mul), clamp255(col.g * mul), clamp255(col.b * mul));
    }
  }
  // 锈迹
  for (let i = 0; i < 18; i++) {
    const x0 = (rnd() * S) | 0;
    const y0 = 10 + ((rnd() * (S - 40)) | 0);
    const len = 14 + rnd() * 56;
    const wd = 1 + rnd() * 3;
    for (let yy = 0; yy < len; yy++) {
      for (let xx = 0; xx < wd; xx++) {
        p.blend((x0 + xx) % S, Math.min(S - 1, y0 + yy), 120, 62, 26, 0.3 * (1 - yy / len));
      }
    }
  }
  // 划痕
  for (let i = 0; i < 10; i++) {
    const y0 = (rnd() * S) | 0;
    const x0 = (rnd() * S) | 0;
    const len = 6 + rnd() * 26;
    for (let xx = 0; xx < len; xx++) {
      p.blend((x0 + xx) % S, y0, 220, 220, 216, 0.18);
    }
  }
  return p.toTex();
}

/** 木箱 / 军用铁皮箱 */
export function makeCrate(kind: string, seed: number): TexData {
  const S = 128;
  const p = new PixBuf(S, S);
  const n = fbm(S, S, 8, 8, 3, seed);
  const rnd = mulberry32(seed + 1);
  if (kind === 'wood') {
    for (let y = 0; y < S; y++) {
      for (let x = 0; x < S; x++) {
        const i = y * S + x;
        const plank = Math.floor(y / 32);
        const edge = y % 32 < 2 ? 0.7 : 1;
        const grain = Math.sin(x * 0.7 + plank * 13) * 0.05;
        const v = (0.62 + n[i] * 0.3 + grain) * edge;
        p.set(x, y, clamp255(150 * v), clamp255(100 * v), clamp255(56 * v));
      }
    }
    // 边框加固条
    for (let x = 0; x < S; x++) {
      for (let t = 0; t < 5; t++) {
        p.blend(x, t, 90, 92, 96, 0.5);
        p.blend(x, S - 1 - t, 90, 92, 96, 0.5);
      }
    }
    for (let y = 0; y < S; y++) {
      for (let t = 0; t < 5; t++) {
        p.blend(t, y, 90, 92, 96, 0.5);
        p.blend(S - 1 - t, y, 90, 92, 96, 0.5);
      }
    }
  } else {
    const base = kind === 'ammo' ? [96, 92, 52] : [70, 78, 86];
    for (let y = 0; y < S; y++) {
      for (let x = 0; x < S; x++) {
        const i = y * S + x;
        let v = 0.8 + n[i] * 0.3;
        // 横向筋
        if (y % 32 < 4) {
          v *= 1.15;
        }
        if (x < 4 || x > S - 5) {
          v *= 0.8;
        }
        p.set(x, y, clamp255(base[0] * v), clamp255(base[1] * v), clamp255(base[2] * v));
      }
    }
    // 铆钉
    for (let y = 16; y < S; y += 32) {
      for (let x = 12; x < S; x += 24) {
        for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            p.blend(x + dx, y + dy, 150, 152, 158, 0.7);
          }
        }
      }
    }
    void rnd;
  }
  return p.toTex();
}

/** 船体外板：红底 + 锈 + 吃水线 */
export function makeHull(): TexData {
  const W = 256;
  const H = 128;
  const p = new PixBuf(W, H);
  const n = fbm(W, H, 12, 6, 4, 50);
  const rnd = mulberry32(51);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const i = y * W + x;
      let r: number, g: number, b: number;
      const t = y / H;
      if (t < 0.18) {
        r = 96; g = 98; b = 100; // 干舷灰
      } else if (t < 0.24) {
        r = 200; g = 170; b = 60; // 吃水线
      } else {
        r = 108; g = 44; b = 36; // 红丹底漆
      }
      const v = 0.82 + n[i] * 0.3;
      p.set(x, y, clamp255(r * v), clamp255(g * v), clamp255(b * v));
    }
  }
  // 锈痕（从上往下）
  for (let i = 0; i < 40; i++) {
    const x0 = (rnd() * W) | 0;
    const y0 = (rnd() * 30) | 0;
    const len = 20 + rnd() * 90;
    const wd = 1 + rnd() * 5;
    for (let yy = 0; yy < len; yy++) {
      for (let xx = 0; xx < wd; xx++) {
        p.blend((x0 + xx) % W, Math.min(H - 1, y0 + yy), 116, 60, 28, 0.35 * (1 - yy / len));
      }
    }
  }
  return p.toTex();
}

/** 舱壁钢板：面板 + 螺栓 */
export function makeBulkhead(): TexData {
  const S = 128;
  const p = new PixBuf(S, S);
  const n = fbm(S, S, 8, 8, 3, 60);
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const i = y * S + x;
      let v = 0.82 + n[i] * 0.26;
      if (x % 64 < 2 || y % 64 < 2) {
        v *= 0.72;
      }
      p.set(x, y, clamp255(122 * v), clamp255(128 * v), clamp255(134 * v));
    }
  }
  for (let y = 16; y < S; y += 32) {
    for (let x = 16; x < S; x += 32) {
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          p.blend(x + dx, y + dy, 60, 62, 66, 0.55);
        }
      }
    }
  }
  return p.toTex();
}

/** 上层建筑墙：带窗 */
export function makeSuperWall(): TexData {
  const S = 128;
  const p = new PixBuf(S, S);
  const n = fbm(S, S, 8, 8, 3, 70);
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const i = y * S + x;
      const v = 0.85 + n[i] * 0.2;
      p.set(x, y, clamp255(205 * v), clamp255(208 * v), clamp255(202 * v));
    }
  }
  // 窗户两排
  for (let wy = 0; wy < 2; wy++) {
    for (let wx = 0; wx < 6; wx++) {
      const x0 = 12 + wx * 20;
      const y0 = 28 + wy * 44;
      for (let y = y0; y < y0 + 20; y++) {
        for (let x = x0; x < x0 + 12; x++) {
          p.set(x, y, 30, 44, 58);
        }
      }
      for (let x = x0; x < x0 + 12; x++) {
        p.set(x, y0 + 20, 120, 124, 128);
      }
    }
  }
  return p.toTex();
}

/** 铁丝网（alpha） */
export function makeFence(): TexData {
  const S = 64;
  const p = new PixBuf(S, S);
  // 对角线网格
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const d1 = Math.abs(((x + y) % 16) - 8);
      const d2 = Math.abs(((x - y + 64) % 16) - 8);
      const wire = Math.min(d1, d2) < 1.4;
      p.set(x, y, 168, 170, 172, wire ? 255 : 0);
    }
  }
  return p.toTex();
}

/** 格栅（alpha 圆孔） */
export function makeGrating(): TexData {
  const S = 64;
  const p = new PixBuf(S, S);
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const cx = (x % 16) - 8;
      const cy = (y % 16) - 8;
      const d = Math.sqrt(cx * cx + cy * cy);
      p.set(x, y, 150, 152, 156, d < 5 ? 0 : 255);
    }
  }
  return p.toTex();
}

/** 加色发光粒子（径向） */
export function makeGlow(): TexData {
  const S = 64;
  const p = new PixBuf(S, S);
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const d = Math.hypot(x - S / 2 + 0.5, y - S / 2 + 0.5) / (S / 2);
      const a = Math.max(0, 1 - d * d);
      p.set(x, y, 255, 255, 255, clamp255(a * 255));
    }
  }
  return p.toTex();
}

/** 柔和烟雾（不规则） */
export function makePuff(): TexData {
  const S = 64;
  const p = new PixBuf(S, S);
  const n = fbm(S, S, 4, 4, 3, 80);
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const i = y * S + x;
      const d = Math.hypot(x - S / 2 + 0.5, y - S / 2 + 0.5) / (S / 2);
      const a = Math.max(0, 1 - d) * (0.4 + n[i] * 0.6);
      p.set(x, y, 255, 255, 255, clamp255(a * 255));
    }
  }
  return p.toTex();
}

/** 枪口火焰（四角星） */
export function makeFlash(): TexData {
  const S = 64;
  const p = new PixBuf(S, S);
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const dx = Math.abs(x - S / 2 + 0.5);
      const dy = Math.abs(y - S / 2 + 0.5);
      const star = Math.max(0, 1 - Math.pow(dx / (S / 2), 0.35)) * Math.max(0, 1 - Math.pow(dy / (S / 2), 3));
      const star2 = Math.max(0, 1 - Math.pow(dy / (S / 2), 0.35)) * Math.max(0, 1 - Math.pow(dx / (S / 2), 3));
      const core = Math.max(0, 1 - Math.hypot(dx, dy) / (S * 0.18));
      const a = Math.min(1, star + star2 + core);
      p.set(x, y, 255, clamp255(220 + core * 35), clamp255(150 + core * 105), clamp255(a * 255));
    }
  }
  return p.toTex();
}

/** 曳光条带（沿 X 渐隐） */
export function makeTracer(): TexData {
  const W = 64;
  const H = 16;
  const p = new PixBuf(W, H);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const vy = 1 - Math.abs(y - H / 2 + 0.5) / (H / 2);
      const vx = Math.pow(1 - x / W, 0.6);
      const a = Math.pow(vy, 1.6) * vx;
      p.set(x, y, 255, 240, 190, clamp255(a * 255));
    }
  }
  return p.toTex();
}

function makeHole(S: number, seed: number, rr: number, gg: number, bb: number): TexData {
  const p = new PixBuf(S, S);
  const rnd = mulberry32(seed);
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const d = Math.hypot(x - S / 2 + 0.5, y - S / 2 + 0.5) / (S / 2);
      if (d < 0.32) {
        p.set(x, y, 12, 10, 10, 255);
      } else if (d < 0.42) {
        p.set(x, y, rr, gg, bb, 230);
      } else {
        const a = Math.max(0, 1 - (d - 0.42) * 3.2) * 0.5 * (0.5 + rnd() * 0.5);
        p.set(x, y, rr * 0.6, gg * 0.6, bb * 0.6, clamp255(a * 255));
      }
    }
  }
  return p.toTex();
}

export function makeHoleMetal(): TexData {
  return makeHole(32, 90, 90, 92, 96);
}

export function makeHoleWood(): TexData {
  return makeHole(32, 91, 128, 96, 62);
}

export function makeBlood(): TexData {
  const S = 64;
  const p = new PixBuf(S, S);
  const rnd = mulberry32(92);
  for (let i = 0; i < 9; i++) {
    const cx = S / 2 + (rnd() - 0.5) * 24;
    const cy = S / 2 + (rnd() - 0.5) * 24;
    const r = 5 + rnd() * 13;
    for (let y = 0; y < S; y++) {
      for (let x = 0; x < S; x++) {
        const d = Math.hypot(x - cx, y - cy) / r;
        if (d < 1) {
          p.blend(x, y, 96, 10, 8, 0.9 * (1 - d * d));
        }
      }
    }
  }
  return p.toTex();
}

export function makeScorch(): TexData {
  const S = 128;
  const p = new PixBuf(S, S);
  const n = fbm(S, S, 6, 6, 3, 93);
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const i = y * S + x;
      const d = Math.hypot(x - S / 2 + 0.5, y - S / 2 + 0.5) / (S / 2);
      const a = Math.max(0, 1 - d * 1.3) * (0.4 + n[i] * 0.8);
      p.blend(x, y, 22, 20, 18, Math.min(0.92, a));
    }
  }
  return p.toTex();
}

/** 士兵布料迷彩（顶点色相乘的灰度纹理） */
export function makeSoldierFabric(): TexData {
  const S = 128;
  const p = new PixBuf(S, S);
  const n = fbm(S, S, 8, 8, 3, 94);
  const camo = fbm(S, S, 4, 4, 2, 95);
  const camo2 = fbm(S, S, 4, 4, 2, 96);
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const i = y * S + x;
      const qx = (Math.floor(x / 4) * 4), qy = (Math.floor(y / 4) * 4);
      const qi = qy * S + qx;
      let v: number;
      const a = camo[qi], b = camo2[qi];
      if (a > 0.56) {
        v = 0.55;
      } else if (b > 0.58) {
        v = 1.25;
      } else if (a < 0.42) {
        v = 0.8;
      } else {
        v = 1.0;
      }
      v *= 0.9 + n[i] * 0.16;
      p.set(x, y, clamp255(v * 190), clamp255(v * 190), clamp255(v * 190));
    }
  }
  return p.toTex();
}

/** 枪械金属磨损 */
export function makeGunWear(): TexData {
  const S = 128;
  const p = new PixBuf(S, S);
  const n = fbm(S, S, 8, 8, 5, 97);
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const i = y * S + x;
      const v = 0.86 + n[i] * 0.22;
      p.set(x, y, clamp255(v * 230), clamp255(v * 230), clamp255(v * 230));
    }
  }
  return p.toTex();
}

/** 枪托木纹 */
export function makeGunWood(): TexData {
  const S = 128;
  const p = new PixBuf(S, S);
  const g = fbm(S, S, 1, 12, 4, 98);
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const i = y * S + x;
      const v = 0.72 + g[i] * 0.5;
      p.set(x, y, clamp255(128 * v), clamp255(66 * v), clamp255(32 * v));
    }
  }
  return p.toTex();
}

/** 队友名牌（Canvas 文字渲染）宽 256 高 48 */
export function makeNameTag(name: string, team: string): TexData {
  const W = 256;
  const H = 48;
  const canvas = new OffscreenCanvas(W, H);
  const ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, W, H);
  ctx.font = 'bold 30px sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.lineWidth = 5;
  ctx.strokeStyle = 'rgba(0,0,0,0.8)';
  ctx.strokeText(name, W / 2, H / 2);
  ctx.fillStyle = team === 'BL' ? '#ff9b70' : '#8cc8ff';
  ctx.fillText(name, W / 2, H / 2);
  const img = ctx.getImageData(0, 0, W, H);
  const u8 = new Uint8Array(W * H * 4);
  for (let i = 0; i < u8.length; i++) {
    u8[i] = img.data[i];
  }
  return new TexData(W, H, u8);
}
