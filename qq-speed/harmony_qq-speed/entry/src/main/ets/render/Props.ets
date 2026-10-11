// 地图布景：按四张地图的标志性元素程序化摆放（自 H5 版 props.js 精选移植）
// 空间瓦片分块：每个 260m 瓦片一个 Mesh（含包围球），渲染期整片剔除不可见城区
import { MapCfg } from '../common/Config';
import { Track, TrackSample } from '../game/Track';
import { Terrain } from './Terrain';
import { Palette } from './Palette';
import { Mesh, MeshBuilder, addBox, addPrism, addCone } from './Mesh';
import { Rng, mulberry32 } from '../common/Util';

const TILE: number = 260;

class TileSink {
  private tiles: Map<string, MeshBuilder> = new Map<string, MeshBuilder>();
  pal: Palette;

  constructor(pal: Palette) {
    this.pal = pal;
  }

  get(x: number, z: number): MeshBuilder {
    const k = String(Math.floor(x / TILE)) + '_' + String(Math.floor(z / TILE));
    let b = this.tiles.get(k);
    if (b === undefined) {
      b = new MeshBuilder(this.pal);
      this.tiles.set(k, b);
    }
    return b;
  }

  all(maxDist: number): Mesh[] {
    const out: Mesh[] = [];
    this.tiles.forEach((b) => {
      out.push(b.build(maxDist));
    });
    return out;
  }
}

export class PropsBuilder {
  static build(map: MapCfg, track: Track, terrain: Terrain, pal: Palette, quality: string): Mesh[] {
    const rnd = mulberry32(map.id.length * 997 + 13);
    const propDist = quality === 'high' ? 1300 : quality === 'mid' ? 900 : 550;
    const out: Mesh[] = [];
    const t = new TileSink(pal);
    const tNear = new TileSink(pal); // 近景独立瓦片（路灯等，视距短）
    // 起点龙门架 + 看台
    PropsBuilder.startGate(t, track, pal);
    PropsBuilder.grandstand(t, track, pal, terrain);
    // 路灯（250m 视距）
    PropsBuilder.lamps(tNear, track, pal, terrain);
    for (const m of tNear.all(250)) out.push(m);

    if (map.id === 'city') {
      PropsBuilder.cityProps(t, track, terrain, pal, rnd);
      PropsBuilder.towerBridge(t, track, pal);
      PropsBuilder.balloons(t, track, terrain, pal, rnd, 0xff9a1f);
      PropsBuilder.blimp(t, track, pal);
    } else if (map.id === 'aegean') {
      PropsBuilder.aegeanProps(t, track, terrain, pal, rnd);
      PropsBuilder.sailboats(t, track, pal, terrain, rnd);
      PropsBuilder.windmill(t, track, terrain, pal);
    } else if (map.id === 'egypt') {
      PropsBuilder.egyptProps(t, track, terrain, pal, rnd);
    } else {
      PropsBuilder.snowProps(t, track, terrain, pal, rnd);
    }
    const tiled = t.all(propDist);
    for (const m of tiled) out.push(m);
    return out;
  }

  private static startGate(t: TileSink, track: Track, pal: Palette): void {
    const s = new TrackSample();
    track.sample(0, s);
    const b = t.get(s.x, s.z);
    const hw = track.halfW;
    const pillar = pal.add(0x3d4c66);
    const pillar2 = pal.add(0x526588);
    const beam = pal.add(0x1d6ff2);
    const lightR = pal.add(0xff3050);
    const lightG = pal.add(0x30ff70);
    for (const side of [-1, 1]) {
      const x = s.x + s.rx * side * (hw + 1.6);
      const z = s.z + s.rz * side * (hw + 1.6);
      addBox(b, x, 3.6, z, 1.2, 7.2, 1.2, s.hd, pillar, pillar2, pillar);
    }
    addBox(b, s.x, 7.5, s.z, (hw + 2.2) * 2, 1.1, 1.0, s.hd, beam, beam, beam);
    for (let k = 0; k < 4; k++) {
      const off = (k - 1.5) * 2.4;
      const lx = s.x + s.tx * 0.7 + s.rx * off;
      const lz = s.z + s.tz * 0.7 + s.rz * off;
      addBox(b, lx, 6.7, lz, 0.8, 0.8, 0.4, s.hd, k < 3 ? lightR : lightG, k < 3 ? lightR : lightG, k < 3 ? lightR : lightG);
    }
  }

  private static grandstand(t: TileSink, track: Track, pal: Palette, terrain: Terrain): void {
    const s = new TrackSample();
    track.sample(track.length * 0.02, s);
    const side = -1;
    const base = pal.add(0x2e6fd6);
    const base2 = pal.add(0x244f9e);
    const seatA = pal.add(0xd8e4f8);
    const seatB = pal.add(0xffd23a);
    const len = 70;
    const steps = 5;
    for (let k = 0; k < steps; k++) {
      const off = side * (track.halfW + 10 + k * 2.2);
      const x = s.x + s.rx * off;
      const z = s.z + s.rz * off;
      const b = t.get(x, z);
      const y = terrain.heightAt(x, z);
      addBox(b, x, y + 1 + k * 1.5, z, 2.4, 1.2 + k * 1.6, len,
        s.hd + Math.PI / 2, k % 2 === 0 ? seatA : seatB, base, base2);
    }
    const off2 = side * (track.halfW + 14);
    const x2 = s.x + s.rx * off2;
    const z2 = s.z + s.rz * off2;
    const b2 = t.get(x2, z2);
    const y2 = terrain.heightAt(x2, z2);
    addBox(b2, x2, y2 + 11, z2, 12, 0.5, len, s.hd + Math.PI / 2, base, base2, base);
  }

  private static lamps(t: TileSink, track: Track, pal: Palette, terrain: Terrain): void {
    const pole = pal.add(0x3a4150);
    const head = pal.add(0xfff4c8);
    for (let i = 0; i < track.N; i += 14) {
      const side = ((i / 14) % 2) === 0 ? -1 : 1;
      const off = side * (track.halfW + 2.4);
      const x = track.px[i] + track.rx[i] * off;
      const z = track.pz[i] + track.rz[i] * off;
      const b = t.get(x, z);
      const y = track.py[i] + side * track.halfW * Math.sin(track.bank[i]);
      const ry = track.hd[i] + (side < 0 ? 0 : Math.PI);
      addBox(b, x, y + 2.6, z, 0.16, 5.2, 0.16, ry, pole, pole, pole);
      const ax = x + Math.sin(ry + Math.PI / 2) * -0.9;
      const az = z + Math.cos(ry + Math.PI / 2) * -0.9;
      addBox(b, ax, y + 5.2, az, 1.8, 0.12, 0.2, ry, pole, pole, pole);
      addBox(b, ax - Math.sin(ry) * 0.2, y + 5.05, az - Math.cos(ry) * 0.2, 0.7, 0.18, 0.4, ry, head, head, head);
    }
  }

  private static free(track: Track, x: number, z: number, margin: number): boolean {
    return track.nearest(x, z, track.halfW + margin) < 0;
  }

  // ---------- 城市 ----------
  private static cityProps(t: TileSink, track: Track, terrain: Terrain, pal: Palette, rnd: Rng): void {
    const glass = pal.add(0x2a3a55);
    const glass2 = pal.add(0x374b6d);
    const roofC = pal.add(0x8f96a3);
    const walls: number[] = [pal.add(0x9aa3b5), pal.add(0x8a93a6), pal.add(0xa8b1c2), pal.add(0x768094), pal.add(0xb5bcc9)];
    const step = 62;
    let placed = 0;
    for (let gx = track.minX - 150; gx < track.maxX + 150 && placed < 130; gx += step) {
      for (let gz = track.minZ - 150; gz < track.maxZ + 150 && placed < 130; gz += step) {
        const jx = gx + (rnd() - 0.5) * 26;
        const jz = gz + (rnd() - 0.5) * 26;
        if (Math.abs(jz) < 78) continue;
        const w = 18 + rnd() * 26;
        const d = 18 + rnd() * 26;
        if (!PropsBuilder.free(track, jx, jz, Math.max(w, d) / 2 + 8)) continue;
        const b = t.get(jx, jz);
        const gy = terrain.heightAt(jx, jz);
        if (gy < -1) continue;
        const distC = Math.hypot(jx - track.cx, jz - track.cz);
        const h = 14 + rnd() * 40 + Math.max(0, 120 - distC / 4) * rnd();
        const c = walls[Math.floor(rnd() * walls.length)];
        addBox(b, jx, gy + h / 2, jz, w, h, d, rnd() * Math.PI, c, roofC, c);
        // 玻璃横带（每 16m 一条）
        const bands = Math.floor(h / 16);
        for (let k = 1; k <= bands; k++) {
          addBox(b, jx, gy + k * 16, jz, w * 1.01, 1.4, d * 1.01, 0, k % 2 === 0 ? glass : glass2, glass, glass);
        }
        if (rnd() < 0.5) addBox(b, jx, gy + h + 1.5, jz, w * 0.3, 3, d * 0.3, 0, roofC, roofC, roofC);
        placed++;
      }
    }
  }

  private static towerBridge(t: TileSink, track: Track, pal: Palette): void {
    const stone = pal.add(0x6d7484);
    const stone2 = pal.add(0x8b93a4);
    const cap = pal.add(0x3d4c66);
    for (const zPos of [-64, 64]) {
      let bx = 0;
      let best = 1e9;
      for (let x = -400; x <= 400; x += 8) {
        const n = track.nearest(x, zPos, 200);
        if (n >= 0) {
          const d = Math.hypot(track.px[n] - x, track.pz[n] - zPos);
          if (d < best) {
            best = d;
            bx = x;
          }
        }
      }
      for (const dx of [-24, 24]) {
        const x = bx + dx;
        const b = t.get(x, zPos);
        addBox(b, x, 18, zPos, 10, 36, 10, 0, stone, stone2, stone);
        addBox(b, x, 38, zPos, 12, 4, 12, 0, cap, cap, cap);
        addBox(b, x, 42, zPos, 6, 4, 6, 0, cap, cap, cap);
      }
    }
  }

  private static balloons(t: TileSink, track: Track, terrain: Terrain, pal: Palette, rnd: Rng, c1: number): void {
    const colors: number[] = [pal.add(c1), pal.add(0x27c7ff), pal.add(0xff5fa8), pal.add(0xffd23a)];
    const basket = pal.add(0x6b4a2a);
    for (let k = 0; k < 4; k++) {
      const a = rnd() * Math.PI * 2;
      const r = 300 + rnd() * 500;
      const x = track.cx + Math.cos(a) * r;
      const z = track.cz + Math.sin(a) * r;
      const y = 60 + rnd() * 60;
      const b = t.get(x, z);
      const col = colors[k % colors.length];
      const col2 = colors[(k + 1) % colors.length];
      for (let m = 0; m < 8; m++) {
        const a0 = (m / 8) * Math.PI * 2;
        addPrism(b, x + Math.sin(a0) * 5, y - 7, z + Math.cos(a0) * 5, 2, 2, y + 7, 8, a0,
          m % 2 === 0 ? col : col2, col, -1);
      }
      addBox(b, x, y - 10.5, z, 2.4, 2.4, 2.4, 0, basket, basket, basket);
    }
  }

  private static blimp(t: TileSink, track: Track, pal: Palette): void {
    const body = pal.add(0xe8ecf4);
    const fin = pal.add(0x1d6ff2);
    const x = track.cx - 320;
    const y = 120;
    const z = track.cz - 260;
    const b = t.get(x, z);
    addPrism(b, x, y - 4, z, 4, 4, y + 4, 10, 0.3, body, body, body);
    addBox(b, x - 14, y, z, 8, 0.4, 10, 0, fin, fin, fin);
    addBox(b, x - 14, y, z, 8, 10, 0.4, 0, fin, fin, fin);
    addBox(b, x, y - 6, z, 3, 1.4, 3, 0, fin, fin, fin);
  }

  // ---------- 爱琴海 ----------
  private static aegeanProps(t: TileSink, track: Track, terrain: Terrain, pal: Palette, rnd: Rng): void {
    const wallC = pal.add(0xf2eee6);
    const wallC2 = pal.add(0xe6e0d2);
    const roofC = pal.add(0x2f7fd8);
    const roofD = pal.add(0x2468b8);
    const trunk = pal.add(0x8a6a4a);
    const leaf = pal.add(0x3f9f5a);
    const leaf2 = pal.add(0x54b86e);
    let placed = 0;
    let tries = 0;
    while (placed < 90 && tries < 1200) {
      tries++;
      const x = track.minX - 60 + rnd() * (track.maxX - track.minX + 120);
      const z = -240 + rnd() * (track.maxZ + 340);
      if (z < -262) continue;
      if (!PropsBuilder.free(track, x, z, 16)) continue;
      const gy = terrain.heightAt(x, z);
      if (gy < 0.5) continue;
      const b = t.get(x, z);
      const w = 8 + rnd() * 7;
      const d = 8 + rnd() * 7;
      const h = 7 + rnd() * 5;
      const yaw = Math.round(rnd() * 4) * (Math.PI / 4);
      addBox(b, x, gy + h / 2, z, w, h, d, yaw, rnd() < 0.5 ? wallC : wallC2, wallC, wallC);
      addCone(b, x, gy + h, z, Math.max(w, d) * 0.78, 3.4 + rnd() * 2, 4, yaw + Math.PI / 4, rnd() < 0.5 ? roofC : roofD);
      if (rnd() < 0.6) {
        addBox(b, x + Math.sin(yaw + Math.PI / 2) * (w / 2 + 2), gy + 0.5, z + Math.cos(yaw + Math.PI / 2) * (w / 2 + 2), w + 3, 1, 0.5, yaw, wallC2, wallC2, wallC2);
      }
      placed++;
    }
    placed = 0;
    tries = 0;
    while (placed < 70 && tries < 900) {
      tries++;
      const x = track.minX + rnd() * (track.maxX - track.minX);
      const z = -230 + rnd() * (track.maxZ + 240);
      if (!PropsBuilder.free(track, x, z, 7)) continue;
      const gy = terrain.heightAt(x, z);
      if (gy < 0) continue;
      const b = t.get(x, z);
      const h = 5 + rnd() * 4;
      addPrism(b, x, gy, z, 0.22, 0.16, gy + h, 6, rnd(), trunk, trunk, -1);
      const lc = rnd() < 0.5 ? leaf : leaf2;
      for (let k = 0; k < 5; k++) {
        const a = (k / 5) * Math.PI * 2 + rnd();
        addBox(b, x + Math.sin(a) * 1.4, gy + h - 0.2, z + Math.cos(a) * 1.4, 2.6, 0.16, 0.7, a, lc, lc, lc);
      }
      placed++;
    }
  }

  private static sailboats(t: TileSink, track: Track, pal: Palette, terrain: Terrain, rnd: Rng): void {
    const hull = pal.add(0xf2eee6);
    void terrain;
    const sail = pal.add(0xffffff);
    const sailB = pal.add(0x2f7fd8);
    for (let k = 0; k < 7; k++) {
      const x = track.cx + (rnd() - 0.5) * 900;
      const z = -320 - rnd() * 400;
      const yaw = rnd() * Math.PI * 2;
      const b = t.get(x, z);
      addBox(b, x, -1.4, z, 2.4, 1.2, 7.5, yaw, hull, hull, hull);
      addBox(b, x, -0.4, z, 0.18, 6.5, 0.18, yaw, hull, hull, hull);
      for (const side of [-1, 1]) {
        const ox = side * 0.35;
        b.quad(
          x + Math.sin(yaw) * -3.4 + Math.cos(yaw) * ox, -0.2, z + Math.cos(yaw) * -3.4 - Math.sin(yaw) * ox,
          x + Math.sin(yaw) * -3.4 + Math.cos(yaw) * ox, 5.8, z + Math.cos(yaw) * -3.4 - Math.sin(yaw) * ox,
          x + Math.sin(yaw) * 1.6 + Math.cos(yaw) * ox, 5.2, z + Math.cos(yaw) * 1.6 - Math.sin(yaw) * ox,
          x + Math.sin(yaw) * 1.6 + Math.cos(yaw) * ox, -0.2, z + Math.cos(yaw) * 1.6 - Math.sin(yaw) * ox,
          side < 0 ? sail : sailB, -1);
      }
    }
  }

  private static windmill(t: TileSink, track: Track, terrain: Terrain, pal: Palette): void {
    let x = track.cx - 500;
    let z = track.cz + 200;
    for (let tries = 0; tries < 200; tries++) {
      const tx = track.cx + (Math.random() - 0.5) * 800;
      const tz = track.cz + (Math.random() - 0.5) * 800;
      if (PropsBuilder.free(track, tx, tz, 30)) {
        x = tx;
        z = tz;
        break;
      }
    }
    const gy = terrain.heightAt(x, z);
    const b = t.get(x, z);
    const wallC = pal.add(0xf2eee6);
    const roofC = pal.add(0x9c9a74);
    const blade = pal.add(0xfff8e8);
    addPrism(b, x, gy, z, 3.4, 2.3, gy + 12, 8, 0.2, wallC, wallC, wallC);
    addCone(b, x, gy + 12, z, 3.6, 4, 8, 0.6, roofC);
    for (let k = 0; k < 4; k++) {
      const a = k * Math.PI / 2 + 0.6;
      const bx = x + Math.cos(a) * 5;
      const bz = z + Math.sin(a) * 5;
      addBox(b, bx, gy + 11, bz, 1.4, 0.3, 8, a, blade, blade, blade);
    }
  }

  // ---------- 埃及 ----------
  private static egyptProps(t: TileSink, track: Track, terrain: Terrain, pal: Palette, rnd: Rng): void {
    const sand = pal.add(0xd9b77a);
    const sand2 = pal.add(0xc9a36a);
    const stone = pal.add(0xcfb383);
    const gold = pal.add(0xffd23a);
    const trunk = pal.add(0x8a6a4a);
    const leaf = pal.add(0x3f9f5a);
    const spots: number[][] = [[-420, -140], [430, 180], [-80, -520], [520, -350]];
    for (const sp of spots) {
      if (!PropsBuilder.free(track, sp[0], sp[1], 120)) continue;
      const b = t.get(sp[0], sp[1]);
      const gy = terrain.heightAt(sp[0], sp[1]);
      const size = 90 + rnd() * 60;
      for (let m = 0; m < 4; m++) {
        const a0 = (m / 4) * Math.PI * 2 + Math.PI / 4;
        const a1 = ((m + 1) / 4) * Math.PI * 2 + Math.PI / 4;
        const r = size * 0.72;
        const h = size * 0.62;
        b.quad(
          sp[0], gy + h, sp[1],
          sp[0] + Math.sin(a0) * r, gy, sp[1] + Math.cos(a0) * r,
          sp[0] + Math.sin(a1) * r, gy, sp[1] + Math.cos(a1) * r,
          sp[0] + Math.sin(a1) * r, gy, sp[1] + Math.cos(a1) * r,
          m % 2 === 0 ? sand : sand2, -1);
      }
    }
    {
      const s = new TrackSample();
      track.sample(track.length * 0.06, s);
      const off = track.halfW + 26;
      const x = s.x + s.rx * off;
      const z = s.z + s.rz * off;
      const b = t.get(x, z);
      const gy = terrain.heightAt(x, z);
      const yaw = s.hd + Math.PI / 2;
      addBox(b, x, gy + 3, z, 8, 6, 22, yaw, stone, sand2, stone);
      addBox(b, x + Math.sin(yaw) * 8, gy + 6.5, z + Math.cos(yaw) * 8, 6, 6, 6, yaw, sand, gold, sand);
      addBox(b, x + Math.sin(yaw) * 8, gy + 10, z + Math.cos(yaw) * 8, 7, 2.4, 7, yaw, gold, gold, gold);
      for (const side of [-1, 1]) {
        addBox(b, x + Math.sin(yaw + Math.PI / 2) * side * 3.4, gy + 0.8, z + Math.cos(yaw + Math.PI / 2) * side * 3.4, 2, 1.6, 18, yaw, stone, stone, stone);
      }
    }
    for (let i = 0; i < track.N; i += 46) {
      const side = ((i / 46) % 2) === 0 ? -1 : 1;
      const off = side * (track.halfW + 14 + rnd() * 8);
      const x = track.px[i] + track.rx[i] * off;
      const z = track.pz[i] + track.rz[i] * off;
      if (!PropsBuilder.free(track, x, z, 4)) continue;
      const b = t.get(x, z);
      const gy = terrain.heightAt(x, z);
      if ((i / 46) % 3 < 1) {
        addPrism(b, x, gy, z, 1.2, 0.8, gy + 16, 4, track.hd[i], sand, gold, sand);
        addCone(b, x, gy + 16, z, 1.1, 2.4, 4, track.hd[i] + Math.PI / 4, gold);
      } else {
        const h = 5 + rnd() * 4;
        addPrism(b, x, gy, z, 0.22, 0.16, gy + h, 6, rnd(), trunk, trunk, -1);
        for (let k = 0; k < 5; k++) {
          const a = (k / 5) * Math.PI * 2 + rnd();
          addBox(b, x + Math.sin(a) * 1.4, gy + h - 0.2, z + Math.cos(a) * 1.4, 2.6, 0.16, 0.7, a, leaf, leaf, leaf);
        }
      }
    }
  }

  // ---------- 雪地 ----------
  private static snowProps(t: TileSink, track: Track, terrain: Terrain, pal: Palette, rnd: Rng): void {
    const pine = pal.add(0x2a6444);
    const pine2 = pal.add(0x357552);
    const snowC = pal.add(0xf4f8ff);
    const trunk = pal.add(0x6b4a2a);
    let placed = 0;
    let tries = 0;
    while (placed < 200 && tries < 1500) {
      tries++;
      const x = track.minX - 80 + rnd() * (track.maxX - track.minX + 160);
      const z = track.minZ - 80 + rnd() * (track.maxZ - track.minZ + 160);
      if (!PropsBuilder.free(track, x, z, 10)) continue;
      const b = t.get(x, z);
      const gy = terrain.heightAt(x, z);
      const h = 6 + rnd() * 7;
      const c = rnd() < 0.5 ? pine : pine2;
      addPrism(b, x, gy, z, 0.3, 0.2, gy + h * 0.35, 5, rnd(), trunk, trunk, -1);
      addCone(b, x, gy + h * 0.2, z, 2.6, h * 0.6, 7, rnd(), c);
      addCone(b, x, gy + h * 0.55, z, 2.0, h * 0.45, 7, rnd() + 0.3, c);
      addCone(b, x, gy + h * 0.78, z, 1.1, h * 0.28, 6, rnd() + 0.6, snowC);
      placed++;
    }
    PropsBuilder.balloons(t, track, terrain, pal, rnd, 0xd84a4a);
  }
}
