// 粒子池与轮胎印（自 H5 版 effects.js 移植为 CPU 数据，绘制交给 Renderer）
import { clamp } from '../common/Util';

export class ParticlePool {
  max: number;
  pos: Float32Array;
  vel: Float32Array;
  life: Float32Array;
  maxLife: Float32Array;
  s0: Float32Array;
  s1: Float32Array;
  a0: Float32Array;
  grav: Float32Array;
  drag: Float32Array;
  rgb: Float32Array;
  curSize: Float32Array;
  cursor: number = 0;

  constructor(max: number) {
    this.max = max;
    this.pos = new Float32Array(max * 3);
    this.vel = new Float32Array(max * 3);
    this.life = new Float32Array(max);
    this.maxLife = new Float32Array(max);
    this.s0 = new Float32Array(max);
    this.s1 = new Float32Array(max);
    this.a0 = new Float32Array(max);
    this.grav = new Float32Array(max);
    this.drag = new Float32Array(max);
    this.rgb = new Float32Array(max * 3);
    this.curSize = new Float32Array(max);
  }

  emit(x: number, y: number, z: number, vx: number, vy: number, vz: number,
    life: number, sz0: number, sz1: number, r: number, g: number, b: number, a: number,
    grav: number, drag: number): void {
    const i = this.cursor;
    this.cursor = (this.cursor + 1) % this.max;
    this.pos[i * 3] = x;
    this.pos[i * 3 + 1] = y;
    this.pos[i * 3 + 2] = z;
    this.vel[i * 3] = vx;
    this.vel[i * 3 + 1] = vy;
    this.vel[i * 3 + 2] = vz;
    this.life[i] = life;
    this.maxLife[i] = life;
    this.s0[i] = sz0;
    this.s1[i] = sz1;
    this.a0[i] = a;
    this.rgb[i * 3] = r;
    this.rgb[i * 3 + 1] = g;
    this.rgb[i * 3 + 2] = b;
    this.grav[i] = grav;
    this.drag[i] = drag;
    this.curSize[i] = sz0;
  }

  update(dt: number): void {
    for (let i = 0; i < this.max; i++) {
      if (this.life[i] <= 0) {
        this.curSize[i] = 0;
        continue;
      }
      this.life[i] -= dt;
      const k = 1 - Math.max(0, this.life[i]) / this.maxLife[i];
      const dr = Math.exp(-this.drag[i] * dt);
      this.vel[i * 3] *= dr;
      this.vel[i * 3 + 1] = this.vel[i * 3 + 1] * dr - this.grav[i] * dt;
      this.vel[i * 3 + 2] *= dr;
      this.pos[i * 3] += this.vel[i * 3] * dt;
      this.pos[i * 3 + 1] += this.vel[i * 3 + 1] * dt;
      this.pos[i * 3 + 2] += this.vel[i * 3 + 2] * dt;
      this.curSize[i] = this.s0[i] + (this.s1[i] - this.s0[i]) * k;
    }
  }

  clear(): void {
    this.life.fill(0);
    this.curSize.fill(0);
  }
}

interface SkidLast {
  x: number;
  y: number;
  z: number;
  rx: number;
  rz: number;
  s: number;
}

// 轮胎印：环形缓冲四边形带
export class SkidMarks {
  max: number;
  pos: Float32Array;      // 每格 4 顶点 xyz
  strength: Float32Array;
  head: number = 0;
  count: number = 0;
  private last: Map<string, SkidLast> = new Map<string, SkidLast>();

  constructor(max: number) {
    this.max = max;
    this.pos = new Float32Array(max * 12);
    this.strength = new Float32Array(max);
  }

  add(key: string, x: number, y: number, z: number, rx: number, rz: number, w: number, strength: number): void {
    const prev = this.last.get(key);
    const cy = y + 0.06;
    if (prev !== undefined && (x - prev.x) * (x - prev.x) + (z - prev.z) * (z - prev.z) < 25) {
      const q = this.head;
      this.head = (this.head + 1) % this.max;
      if (this.count < this.max) this.count++;
      const o = q * 12;
      this.pos[o] = prev.x - prev.rx * w;
      this.pos[o + 1] = prev.y;
      this.pos[o + 2] = prev.z - prev.rz * w;
      this.pos[o + 3] = prev.x + prev.rx * w;
      this.pos[o + 4] = prev.y;
      this.pos[o + 5] = prev.z + prev.rz * w;
      this.pos[o + 6] = x - rx * w;
      this.pos[o + 7] = cy;
      this.pos[o + 8] = z - rz * w;
      this.pos[o + 9] = x + rx * w;
      this.pos[o + 10] = cy;
      this.pos[o + 11] = z + rz * w;
      this.strength[q] = strength;
    }
    const cur: SkidLast = { x: x, y: cy, z: z, rx: rx, rz: rz, s: strength };
    this.last.set(key, cur);
  }

  cut(key: string): void {
    this.last.delete(key);
  }

  clear(): void {
    this.strength.fill(0);
    this.count = 0;
    this.head = 0;
    this.last.clear();
  }
}

// 飘字提示
export class FloatMsg {
  text: string = '';
  color: string = '#27c7ff';
  t: number = 0;
  small: boolean = false;
}

export class MsgList {
  items: FloatMsg[] = [];

  push(text: string, color: string, small: boolean): void {
    const m = new FloatMsg();
    m.text = text;
    m.color = color;
    m.small = small;
    m.t = 0;
    this.items.push(m);
    while (this.items.length > 3) this.items.shift();
  }

  update(dt: number): void {
    for (let i = this.items.length - 1; i >= 0; i--) {
      this.items[i].t += dt;
      if (this.items[i].t > 1.15) this.items.shift();
    }
  }

  clear(): void {
    this.items.length = 0;
  }
}

// 速度线
export class SpeedLine {
  a: number = 0;
  r: number = 0;
  v: number = 0;
  l: number = 0;
  w: number = 0;
}

export class SpeedLines {
  items: SpeedLine[] = [];

  update(dt: number, k: number): void {
    if (k <= 0.01 && this.items.length === 0) return;
    const spawn = k * 90 * dt;
    for (let i = 0; i < spawn * 1.2; i++) {
      const L = new SpeedLine();
      L.a = Math.random() * Math.PI * 2;
      L.r = 0.35 + Math.random() * 0.2;
      L.v = 1.8 + Math.random() * 1.6;
      L.l = 0.08 + Math.random() * 0.14;
      L.w = 1 + Math.random() * 2.5;
      this.items.push(L);
    }
    for (let i = this.items.length - 1; i >= 0; i--) {
      const L = this.items[i];
      L.r += L.v * dt;
      if (L.r > 1.2) this.items.splice(i, 1);
    }
  }

  clear(): void {
    this.items.length = 0;
  }
}

export function clampRef(v: number): number {
  return clamp(v, 0, 1);
}
