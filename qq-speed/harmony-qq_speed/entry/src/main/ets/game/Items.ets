// 道具系统（自 H5 版 items.js 移植）：道具箱、导弹、香蕉皮、天使、磁铁、氮气
import { Rng } from '../common/Util';
import { Track, TrackSample } from './Track';
import { RacerBase } from './RacerBase';
import { PlayerCar } from './Vehicle';

export interface ItemHost {
  sfx(name: string, r: RacerBase): void;
  racerAhead(r: RacerBase): RacerBase | null;
  hitRacer(r: RacerBase, kind: string): void;
  burst(x: number, y: number, z: number, color: number): void;
  explode(x: number, y: number, z: number): void;
  trail(x: number, y: number, z: number): void;
  onItemGet(): void;
  onMissileLock(): void;
}

export class ItemBox {
  x = 0; y = 0; z = 0;
  respawn: number = 0;
  visible: boolean = true;
  spin: number = 0;
}

export class Missile {
  x = 0; y = 0; z = 0;
  dx = 0; dy = 0; dz = 1;
  target: RacerBase | null = null;
  owner: RacerBase | null = null;
  life: number = 6;
  v: number = 80;
}

export class Banana {
  x = 0; y = 0; z = 0;
  owner: RacerBase | null = null;
  age: number = 0;
}

const WEIGHTS: Record<string, Record<string, number>> = {
  'lead': { 'banana': 35, 'shield': 30, 'nitro': 20, 'missile': 10, 'magnet': 5 },
  'mid': { 'missile': 25, 'nitro': 25, 'banana': 20, 'magnet': 15, 'shield': 15 },
  'back': { 'missile': 32, 'nitro': 30, 'magnet': 25, 'shield': 10, 'banana': 3 },
};

function pick(w: Record<string, number>, rnd: Rng): string {
  let tot = 0;
  for (const k of Object.keys(w)) tot += w[k];
  let r = rnd() * tot;
  for (const k of Object.keys(w)) {
    r -= w[k];
    if (r <= 0) return k;
  }
  return 'nitro';
}

export class ItemSystem {
  track: Track;
  host: ItemHost;
  rnd: Rng;
  boxes: ItemBox[] = [];
  missiles: Missile[] = [];
  bananas: Banana[] = [];

  constructor(track: Track, host: ItemHost, rnd: Rng) {
    this.track = track;
    this.host = host;
    this.rnd = rnd;
    const hw = track.halfW;
    for (const f of [0.1, 0.35, 0.6, 0.85]) {
      const d = f * track.length;
      const s = new TrackSample();
      track.sample(d, s);
      for (const lat of [-0.6, -0.3, 0, 0.3, 0.6]) {
        const L = lat * hw;
        const b = new ItemBox();
        b.x = s.x + s.rx * L;
        b.y = s.y + L * Math.sin(s.bank) + 1.6;
        b.z = s.z + s.rz * L;
        this.boxes.push(b);
      }
    }
  }

  reset(): void {
    for (const b of this.boxes) {
      b.respawn = 0;
      b.visible = true;
    }
    this.missiles.length = 0;
    this.bananas.length = 0;
  }

  giveRandom(r: RacerBase, rank: number, total: number): void {
    if (r.items.length >= 2) return;
    const w = rank === 1 ? WEIGHTS['lead'] : rank >= total - 1 ? WEIGHTS['back'] : WEIGHTS['mid'];
    const it = pick(w, this.rnd);
    r.items.push(it);
    if (r.isPlayer) this.host.onItemGet();
  }

  swap(r: RacerBase): void {
    if (r.items.length === 2) {
      const t = r.items[0];
      r.items[0] = r.items[1];
      r.items[1] = t;
    }
  }

  use(r: RacerBase): void {
    const it = r.items.shift();
    if (it === undefined) return;
    const g = this.host;
    if (it === 'nitro') {
      if (r.isPlayer) {
        const p = r as PlayerCar;
        p.triggerNitro(true);
      } else {
        r.nitroTime = 2.6;
      }
    } else if (it === 'shield') {
      r.shield = 7;
      g.sfx('shield', r);
    } else if (it === 'magnet') {
      r.magnet = 3;
      r.magnetTarget = g.racerAhead(r);
      g.sfx('item', r);
    } else if (it === 'banana') {
      const b = new Banana();
      b.owner = r;
      const bx = r.x - Math.sin(r.h) * 3.2;
      const bz = r.z - Math.cos(r.h) * 3.2;
      const p = new TrackSample();
      this.track.project(bx, r.y, bz, r.hint, p);
      b.x = bx;
      b.y = p.y + p.lat * Math.sin(p.bank) + 0.25;
      b.z = bz;
      this.bananas.push(b);
      g.sfx('banana', r);
    } else if (it === 'missile') {
      const target = g.racerAhead(r);
      const m = new Missile();
      m.owner = r;
      m.target = target;
      m.x = r.x;
      m.y = r.y + 1.8;
      m.z = r.z;
      m.dx = Math.sin(r.h);
      m.dy = 0;
      m.dz = Math.cos(r.h);
      m.v = Math.max(80, Math.abs(r.s) + 30);
      this.missiles.push(m);
      g.sfx('missile', r);
      if (target !== null && target.isPlayer) g.onMissileLock();
    }
  }

  update(dt: number, racers: RacerBase[], standings: RacerBase[]): void {
    // 道具箱
    for (const b of this.boxes) {
      if (b.respawn > 0) {
        b.respawn -= dt;
        if (b.respawn <= 0) b.visible = true;
        continue;
      }
      b.spin += dt * 1.6;
      for (const r of racers) {
        const dx = r.x - b.x;
        const dz = r.z - b.z;
        const dy = r.y + 0.8 - b.y;
        if (dx * dx + dz * dz < 6.5 && Math.abs(dy) < 3) {
          b.visible = false;
          b.respawn = 2.5;
          const rank = standings.indexOf(r) + 1;
          this.giveRandom(r, rank, racers.length);
          this.host.burst(b.x, b.y, b.z, 0x55c8ff);
          break;
        }
      }
    }
    // 香蕉皮
    for (let i = this.bananas.length - 1; i >= 0; i--) {
      const bn = this.bananas[i];
      bn.age += dt;
      let hit: RacerBase | null = null;
      for (const r of racers) {
        if (r === bn.owner && bn.age < 1.2) continue;
        const dx = r.x - bn.x;
        const dz = r.z - bn.z;
        if (dx * dx + dz * dz < 4.4 && Math.abs(r.y - bn.y) < 2.5) {
          hit = r;
          break;
        }
      }
      if (hit !== null || bn.age > 90) {
        if (hit !== null) this.host.hitRacer(hit, 'banana');
        this.bananas.splice(i, 1);
      }
    }
    // 导弹
    for (let i = this.missiles.length - 1; i >= 0; i--) {
      const m = this.missiles[i];
      m.life -= dt;
      if (m.target !== null && !m.target.finished) {
        const tox = m.target.x - m.x;
        const toy = m.target.y + 0.8 - m.y;
        const toz = m.target.z - m.z;
        const dist = Math.hypot(tox, toy, toz);
        const il = 1 / Math.max(1e-6, dist);
        const k = Math.min(1, dt * 6);
        m.dx += (tox * il - m.dx) * k;
        m.dy += (toy * il - m.dy) * k;
        m.dz += (toz * il - m.dz) * k;
        const nl = 1 / Math.max(1e-6, Math.hypot(m.dx, m.dy, m.dz));
        m.dx *= nl;
        m.dy *= nl;
        m.dz *= nl;
        m.v = Math.max(m.v, Math.abs(m.target.s) + 35);
        if (dist < 2.6) {
          this.host.hitRacer(m.target, 'missile');
          this.host.explode(m.x, m.y, m.z);
          this.missiles.splice(i, 1);
          continue;
        }
      }
      m.x += m.dx * m.v * dt;
      m.y += m.dy * m.v * dt;
      m.z += m.dz * m.v * dt;
      this.host.trail(m.x - m.dx, m.y - m.dy, m.z - m.dz);
      if (m.life <= 0) {
        this.host.explode(m.x, m.y, m.z);
        this.missiles.splice(i, 1);
      }
    }
  }

  aiThink(r: RacerBase, dt: number): void {
    if (r.items.length === 0) return;
    r.itemTimer -= dt;
    if (r.itemTimer > 0) return;
    r.itemTimer = 1 + this.rnd() * 3;
    const it = r.items[0];
    const ahead = this.host.racerAhead(r);
    const gap = ahead !== null ? ahead.progress - r.progress : 1e9;
    if (it === 'missile' && (ahead === null || gap > 350)) {
      if (r.items.length > 1) this.swap(r);
      return;
    }
    if (it === 'magnet' && (ahead === null || gap > 150)) return;
    this.use(r);
  }
}
