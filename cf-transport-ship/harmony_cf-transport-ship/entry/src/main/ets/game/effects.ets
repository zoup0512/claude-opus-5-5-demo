/**
 * 特效：粒子、贴花、曳光、枪口火焰、爆炸、烟囱排烟（数据层，渲染由 Game 装入帧缓冲）。
 * 移植自原版 effects.js。
 */
import { Vec3 } from './math3d';

export interface Particle {
  x: number; y: number; z: number;
  vx: number; vy: number; vz: number;
  life: number; max: number;
  s0: number; s1: number;
  r: number; g: number; b: number;
  a0: number; a1: number;
  grav: number; drag: number;
  floor: number;
  use: boolean;
}

export function newParticle(): Particle {
  return {
    x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0, life: 0, max: 1, s0: 0.1, s1: 0.1, r: 1, g: 1, b: 1, a0: 1, a1: 0,
    grav: 0, drag: 0, floor: -100, use: false
  };
}

/** 粒子池（0=加色发光纹理，1=普通烟雾纹理） */
export class Particles {
  texId: number;
  max: number;
  pool: Particle[] = [];

  constructor(texId: number, max: number) {
    this.texId = texId;
    this.max = max;
    for (let i = 0; i < max; i++) {
      this.pool.push(newParticle());
    }
  }

  emit(x: number, y: number, z: number, vx: number, vy: number, vz: number, max: number, s0: number, s1: number,
    r: number, g: number, b: number, a0: number, a1: number, grav: number, drag: number,
    floor: number = -100): void {
    for (const p of this.pool) {
      if (!p.use) {
        p.x = x;
        p.y = y;
        p.z = z;
        p.vx = vx;
        p.vy = vy;
        p.vz = vz;
        p.life = 0;
        p.max = max;
        p.s0 = s0;
        p.s1 = s1;
        p.r = r;
        p.g = g;
        p.b = b;
        p.a0 = a0;
        p.a1 = a1;
        p.grav = grav;
        p.drag = drag;
        p.floor = floor;
        p.use = true;
        return;
      }
    }
  }

  update(dt: number): void {
    for (const p of this.pool) {
      if (!p.use) {
        continue;
      }
      p.life += dt;
      if (p.life >= p.max) {
        p.use = false;
        continue;
      }
      const dr = Math.exp(-p.drag * dt);
      p.vx *= dr;
      p.vy = p.vy * dr - p.grav * dt;
      p.vz *= dr;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.z += p.vz * dt;
      if (p.y < p.floor) {
        p.y = p.floor;
        p.vy *= -0.3;
        p.vx *= 0.5;
        p.vz *= 0.5;
      }
    }
  }
}

export interface Decal {
  x: number; y: number; z: number;
  nx: number; ny: number; nz: number;
  size: number;
  age: number;
}

export class DecalRing {
  texId: number;
  max: number;
  items: Decal[] = [];
  i: number = 0;

  constructor(texId: number, max: number) {
    this.texId = texId;
    this.max = max;
    for (let k = 0; k < max; k++) {
      this.items.push({ x: 0, y: 0, z: 0, nx: 0, ny: 1, nz: 0, size: 0.1, age: 999 });
    }
  }

  add(p: Vec3, nx: number, ny: number, nz: number, size: number): void {
    const d = this.items[this.i % this.max];
    this.i++;
    d.x = p.x + nx * 0.004;
    d.y = p.y + ny * 0.004;
    d.z = p.z + nz * 0.004;
    d.nx = nx;
    d.ny = ny;
    d.nz = nz;
    d.size = size;
    d.age = 0;
  }

  update(dt: number): void {
    for (const d of this.items) {
      d.age += dt;
    }
  }
}

export interface Tracer {
  x: number; y: number; z: number;
  dx: number; dy: number; dz: number;
  len: number;
  t: number;
}

export interface MuzzleFlash {
  x: number; y: number; z: number;
  dx: number; dy: number; dz: number;
  t: number;
  big: number;
}

export class Effects {
  add: Particles = new Particles(0, 700);      // 加色发光（纹理 0）
  smoke: Particles = new Particles(1, 700);    // 普通烟雾（纹理 1）
  decalsMetal: DecalRing = new DecalRing(10, 140);
  decalsWood: DecalRing = new DecalRing(11, 90);
  decalsBlood: DecalRing = new DecalRing(12, 60);
  decalsScorch: DecalRing = new DecalRing(13, 12);
  tracers: Tracer[] = [];
  flashes: MuzzleFlash[] = [];
  shake: number = 0;
  private funnelT: number = 0;
  funnelTop: Vec3 | null = null;

  muzzle(pos: Vec3, dir: Vec3, big: number): void {
    this.flashes.push({
      x: pos.x + dir.x * 0.06, y: pos.y + dir.y * 0.06, z: pos.z + dir.z * 0.06,
      dx: dir.x, dy: dir.y, dz: dir.z, t: 0.05, big: big * (0.8 + Math.random() * 0.4)
    });
    this.smoke.emit(pos.x, pos.y, pos.z, dir.x * 1.5, 0.4, dir.z * 1.5, 0.7, 0.1, 0.5, 0.7, 0.7, 0.7, 0.18, 0,
      -0.3, 3);
  }

  vmFlashT: number = 0;

  tracer(from: Vec3, to: Vec3): void {
    const dx = to.x - from.x, dy = to.y - from.y, dz = to.z - from.z;
    const L = Math.sqrt(dx * dx + dy * dy + dz * dz);
    if (L < 2) {
      return;
    }
    this.tracers.push({ x: from.x, y: from.y, z: from.z, dx: dx / L, dy: dy / L, dz: dz / L, len: L, t: 0 });
    if (this.tracers.length > 48) {
      this.tracers.shift();
    }
  }

  impact(p: Vec3, nx: number, ny: number, nz: number, mat: string, dirx: number, diry: number, dirz: number): void {
    if (mat === 'flesh') {
      for (let i = 0; i < 10; i++) {
        this.smoke.emit(p.x, p.y, p.z, dirx * 2 + (Math.random() - 0.5) * 1.5, Math.random() * 1.2,
          dirz * 2 + (Math.random() - 0.5) * 1.5, 0.35 + Math.random() * 0.3, 0.06, 0.28, 0.45, 0.02, 0.02, 0.8, 0,
          2, 4);
      }
      for (let i = 0; i < 6; i++) {
        this.smoke.emit(p.x, p.y, p.z, dirx * 3 + (Math.random() - 0.5) * 2, Math.random() * 2,
          dirz * 3 + (Math.random() - 0.5) * 2, 0.6, 0.035, 0.03, 0.35, 0.0, 0.0, 1, 0.6, 9, 0.5, 0.01);
      }
      return;
    }
    if (mat === 'metal') {
      const cnt = 6 + ((Math.random() * 6) | 0);
      for (let i = 0; i < cnt; i++) {
        const sp = 3 + Math.random() * 5;
        this.add.emit(p.x, p.y, p.z, (nx + (Math.random() - 0.5) * 1.4) * sp, (ny + Math.random() * 0.8) * sp,
          (nz + (Math.random() - 0.5) * 1.4) * sp, 0.18 + Math.random() * 0.25, 0.035, 0.01, 1.6, 1.1, 0.5, 1, 0.3,
          9, 1.5);
      }
      this.add.emit(p.x + nx * 0.02, p.y + ny * 0.02, p.z + nz * 0.02, 0, 0, 0, 0.05, 0.25, 0.1, 1.5, 1.2, 0.7, 1,
        0, 0, 0);
      this.decalsMetal.add(p, nx, ny, nz, 0.07 + Math.random() * 0.03);
    } else if (mat === 'wood') {
      for (let i = 0; i < 8; i++) {
        this.smoke.emit(p.x, p.y, p.z, (nx + (Math.random() - 0.5)) * 3, (ny + Math.random()) * 3,
          (nz + (Math.random() - 0.5)) * 3, 0.6, 0.03, 0.025, 0.55, 0.4, 0.25, 1, 0.8, 9, 1, 0.01);
      }
      this.decalsWood.add(p, nx, ny, nz, 0.08 + Math.random() * 0.03);
    }
    // 尘烟
    const dr = mat === 'wood' ? 0.62 : 0.55;
    const dg = mat === 'wood' ? 0.52 : 0.55;
    const db = mat === 'wood' ? 0.4 : 0.53;
    for (let i = 0; i < 3; i++) {
      this.smoke.emit(p.x + nx * 0.05, p.y + ny * 0.05, p.z + nz * 0.05,
        nx * (0.5 + Math.random()) + (Math.random() - 0.5) * 0.4, ny * 0.8 + 0.3,
        nz * (0.5 + Math.random()) + (Math.random() - 0.5) * 0.4, 0.8 + Math.random() * 0.6, 0.12, 0.6, dr, dg, db,
        0.35, 0, -0.2, 2.5);
    }
  }

  bloodSplat(p: Vec3): void {
    this.decalsBlood.add(p, 0, 1, 0, 0.5 + Math.random() * 0.4);
  }

  explosion(p: Vec3): void {
    this.add.emit(p.x, p.y + 0.3, p.z, 0, 0, 0, 0.18, 2, 7, 2.2, 1.6, 0.9, 1, 0, 0, 0);
    for (let i = 0; i < 26; i++) {
      const a = Math.random() * 6.28;
      const e = Math.random() * 1.2;
      const sp = 3 + Math.random() * 6;
      this.add.emit(p.x, p.y + 0.3, p.z, Math.cos(a) * Math.cos(e) * sp, Math.sin(e) * sp + 1,
        Math.sin(a) * Math.cos(e) * sp, 0.35 + Math.random() * 0.35, 0.9, 2.2, 1.8, 0.8, 0.25, 0.9, 0, -1, 4);
    }
    for (let i = 0; i < 40; i++) {
      const a = Math.random() * 6.28;
      const sp = 8 + Math.random() * 14;
      this.add.emit(p.x, p.y + 0.2, p.z, Math.cos(a) * sp, Math.random() * 10, Math.sin(a) * sp,
        0.4 + Math.random() * 0.5, 0.06, 0.02, 1.8, 1.2, 0.5, 1, 0.4, 12, 1.2, 0.02);
    }
    for (let i = 0; i < 22; i++) {
      const a = Math.random() * 6.28;
      const sp = 1 + Math.random() * 3;
      this.smoke.emit(p.x + Math.cos(a) * 0.5, p.y + 0.4 + Math.random(), p.z + Math.sin(a) * 0.5,
        Math.cos(a) * sp, 1 + Math.random() * 2, Math.sin(a) * sp, 3 + Math.random() * 3, 1.2, 5, 0.22, 0.21, 0.2,
        0.75, 0, -0.4, 1.2);
    }
    this.decalsScorch.add(new Vec3(p.x, 0.01, p.z), 0, 1, 0, 3.2);
    this.shake = Math.max(this.shake, 1);
  }

  initAmbient(funnelTop: Vec3): void {
    this.funnelTop = funnelTop;
  }

  update(dt: number, shipSpeed: number): void {
    this.add.update(dt);
    this.smoke.update(dt);
    this.decalsMetal.update(dt);
    this.decalsWood.update(dt);
    this.decalsBlood.update(dt);
    this.decalsScorch.update(dt);
    const speed = 380;
    for (let i = this.tracers.length - 1; i >= 0; i--) {
      const tr = this.tracers[i];
      tr.t += dt;
      if (Math.max(0, tr.t * speed - 7) >= tr.len) {
        this.tracers.splice(i, 1);
      }
    }
    for (let i = this.flashes.length - 1; i >= 0; i--) {
      this.flashes[i].t -= dt;
      if (this.flashes[i].t <= 0) {
        this.flashes.splice(i, 1);
      }
    }
    this.shake *= Math.exp(-dt * 5);
    // 烟囱排烟
    if (this.funnelTop !== null) {
      this.funnelT -= dt;
      if (this.funnelT <= 0) {
        this.funnelT = 0.14;
        const f = this.funnelTop;
        const g = 0.18 + Math.random() * 0.1;
        this.smoke.emit(f.x + (Math.random() - 0.5) * 2, f.y, f.z + (Math.random() - 0.5) * 1.5,
          -shipSpeed * 0.9 - Math.random(), 2.2 + Math.random(), (Math.random() - 0.5) * 0.8, 9, 2.2, 11, g, g,
          g * 1.02, 0.42, 0, -0.05, 0.08);
      }
    }
  }
}
