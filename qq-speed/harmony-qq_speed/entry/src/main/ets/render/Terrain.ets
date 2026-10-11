// 地形：基础地形（按地图移植 H5 版 baseFor/tintFor）+ 赛道削填压平 + 环形 LOD 网格渲染
import { clamp, lerp, smoothstep, Noise2D, Rng } from '../common/Util';
import { MapCfg } from '../common/Config';
import { Track } from '../game/Track';
import { Renderer, MountainRing } from './Renderer';
import { Palette } from './Palette';

const SEG: number = 192;   // 192x192 网格
const SIZE: number = 3200; // 覆盖 3.2km

export class Terrain {
  map: MapCfg;
  track: Track;
  palette: Palette;
  private H: Float32Array = new Float32Array(0);
  private colId: Uint16Array = new Uint16Array(0);
  private x0: number = 0;
  private z0: number = 0;
  private cell: number = SIZE / SEG;
  private n: number = SEG + 1;
  private noise: Noise2D;
  private noiseT: Noise2D;
  oases: number[][] = [];

  constructor(map: MapCfg, track: Track, palette: Palette, seed: number) {
    this.map = map;
    this.track = track;
    this.palette = palette;
    this.noise = new Noise2D(seed);
    this.noiseT = new Noise2D(seed * 7 + 3);
    this.x0 = track.cx - SIZE / 2;
    this.z0 = track.cz - SIZE / 2;
  }

  // 分块构建（每块之间让出主线程，驱动进度条）
  build(step: number, progress: (p: number) => void): boolean {
    const n = this.n;
    if (this.H.length === 0) {
      this.H = new Float32Array(n * n);
      this.colId = new Uint16Array(n * n);
    }
    const rowsPerStep = 24;
    const j0 = step * rowsPerStep;
    const j1 = Math.min(n, j0 + rowsPerStep);
    for (let j = j0; j < j1; j++) {
      for (let i = 0; i < n; i++) {
        const x = this.x0 + i * this.cell;
        const z = this.z0 + j * this.cell;
        this.H[j * n + i] = this.base(x, z);
      }
    }
    progress(j1 / n);
    if (j1 < n) return false;
    this.flatten();
    this.tint();
    return true;
  }

  private base(x: number, z: number): number {
    const id = this.map.id;
    const cx = this.track.cx;
    const cz = this.track.cz;
    if (id === 'city') {
      const r = Math.abs(z);
      const river = r < 44 ? -6 : r < 64 ? lerp(-6, 0, smoothstep(44, 64, r)) : 0;
      return river + Math.max(0, Math.hypot(x - cx, z - cz) - 950) * 0.12;
    }
    if (id === 'aegean') {
      const land = Math.pow(clamp((z + 195) / 420, 0, 1), 0.8) * 16
        + this.noise.fbm(x * 0.008, z * 0.008, 4) * 5
        + Math.max(0, Math.hypot(x - cx, z - cz) - 900) * 0.1;
      return lerp(land, -14, smoothstep(-200, -262, z));
    }
    if (id === 'egypt') {
      let h = 2 + this.noise.fbm(x * 0.0045, z * 0.0045, 4) * 18
        + Math.max(0, Math.hypot(x - cx, z - cz) - 900) * 0.1;
      for (const o of this.oases) {
        const d = Math.hypot(x - o[0], z - o[1]);
        if (d < o[2] + 25) h = lerp(-2.6, h, smoothstep(o[2] - 6, o[2] + 25, d));
      }
      return h;
    }
    return 3 + this.noise.fbm(x * 0.004, z * 0.004, 4) * 26
      + Math.max(0, Math.hypot(x - cx, z - cz) - 650) * 0.18;
  }

  private flatten(): void {
    // 与原版一致：赛道周围削高填低，桥段不填
    const n = this.n;
    const track = this.track;
    const flatR = track.halfW + (this.map.track.shoulderWidth > 0 ? this.map.track.shoulderWidth + 2.5 : 3.5);
    const R = flatR + this.cell + 48;
    const slope = 0.55;
    const flat = flatR + this.cell * 0.7;
    const hi = new Float32Array(n * n).fill(1e9);
    const lo = new Float32Array(n * n).fill(-1e9);
    for (let k = 0; k < track.N; k++) {
      const px = track.px[k];
      const pz = track.pz[k];
      const py = track.py[k] - 0.6;
      const fill = track.bridge[k] === 0;
      const i0 = Math.max(0, Math.floor((px - R - this.x0) / this.cell));
      const i1 = Math.min(SEG, Math.ceil((px + R - this.x0) / this.cell));
      const j0 = Math.max(0, Math.floor((pz - R - this.z0) / this.cell));
      const j1 = Math.min(SEG, Math.ceil((pz + R - this.z0) / this.cell));
      for (let j = j0; j <= j1; j++) {
        for (let i = i0; i <= i1; i++) {
          const dx = this.x0 + i * this.cell - px;
          const dz = this.z0 + j * this.cell - pz;
          const dist = Math.sqrt(dx * dx + dz * dz);
          if (dist > R) continue;
          const kk = Math.max(0, dist - flat) * slope;
          const id = j * n + i;
          if (py + kk < hi[id]) hi[id] = py + kk;
          if (fill && py - kk * 1.2 > lo[id]) lo[id] = py - kk * 1.2;
        }
      }
    }
    for (let id = 0; id < n * n; id++) {
      let h = this.H[id];
      if (h > hi[id]) h = hi[id];
      if (h < lo[id]) h = Math.min(lo[id], hi[id]);
      this.H[id] = h;
    }
  }

  private tint(): void {
    const n = this.n;
    const id = this.map.id;
    for (let j = 0; j < n; j++) {
      for (let i = 0; i < n; i++) {
        const x = this.x0 + i * this.cell;
        const z = this.z0 + j * this.cell;
        const h = this.H[j * n + i];
        const nn = this.noiseT.at(x * 0.02, z * 0.02);
        let r: number;
        let g: number;
        let b: number;
        if (id === 'city') {
          if (h < -0.8) {
            r = 1.0;
            g = 0.82;
            b = 0.6;
          } else {
            r = 0.55 + nn * 0.12;
            g = 0.66 + nn * 0.08;
            b = 0.5;
          }
        } else if (id === 'aegean') {
          if (h < -0.5) {
            r = 1.0;
            g = 0.93;
            b = 0.75;
          } else {
            const t = clamp(0.5 + nn * 1.2, 0, 1);
            r = lerp(0.72, 0.86, t);
            g = lerp(0.78, 0.82, t);
            b = lerp(0.6, 0.72, t);
          }
        } else if (id === 'egypt') {
          if (h < -1) {
            r = 0.5;
            g = 0.7;
            b = 0.4;
          } else {
            r = 0.82 + nn * 0.08;
            g = 0.72 + nn * 0.06;
            b = 0.55;
          }
        } else {
          r = 0.9 + nn * 0.05;
          g = 0.92 + nn * 0.04;
          b = 0.96;
        }
        this.colId[j * n + i] = this.palette.add(
          (Math.round(r * 255) << 16) | (Math.round(g * 255) << 8) | Math.round(b * 255));
      }
    }
  }

  heightAt(x: number, z: number): number {
    const fx = clamp((x - this.x0) / this.cell, 0, SEG - 0.001);
    const fz = clamp((z - this.z0) / this.cell, 0, SEG - 0.001);
    const i = Math.floor(fx);
    const j = Math.floor(fz);
    const tx = fx - i;
    const tz = fz - j;
    const n = this.n;
    const a = this.H[j * n + i];
    const b = this.H[j * n + i + 1];
    const c = this.H[(j + 1) * n + i];
    const d = this.H[(j + 1) * n + i + 1];
    return lerp(lerp(a, b, tx), lerp(c, d, tx), tz);
  }

  // 环形 LOD：近密远疏（近 20m 格 → 远 180m 格）+ 视锥余弦剔除
  render(r: Renderer): void {
    const water = this.map.water;
    const waterY = water !== null && !water.local ? water.y : -9999;
    const levels: number[][] = [
      [this.cell, 210],
      [this.cell * 3, 580],
      [this.cell * 9, 1250],
    ];
    const fx = r.fx;
    const fz = r.fz;
    const cosH = r.cosHalfFov;
    const fogLimit = r.fogFar * 1.02;
    for (let li = 0; li < levels.length; li++) {
      const cell = levels[li][0];
      const range = Math.min(levels[li][1] * r.viewScale, fogLimit);
      const inner = li > 0 ? levels[li - 1][1] * 0.9 * r.viewScale : 0;
      const ci = Math.round(r.camX / cell);
      const cj = Math.round(r.camZ / cell);
      const ext = Math.ceil(range / cell);
      const inn = Math.floor(inner / cell);
      const nearKeep = cell * 3;
      for (let j = -ext; j <= ext; j++) {
        for (let i = -ext; i <= ext; i++) {
          if (Math.max(Math.abs(i), Math.abs(j)) <= inn) continue;
          const x = (ci + i) * cell;
          const z = (cj + j) * cell;
          // 视锥剔除：格中心方向与视线的夹角（近处放宽）
          const dx = x + cell * 0.5 - r.camX;
          const dz = z + cell * 0.5 - r.camZ;
          const dist = Math.sqrt(dx * dx + dz * dz);
          if (dist > nearKeep) {
            if (dist > fogLimit) continue;
            const cosang = (dx * fx + dz * fz) / dist;
            if (cosang < cosH - cell * 2.2 / dist) continue;
          }
          const x1 = x + cell;
          const z1 = z + cell;
          const h00 = this.heightAt(x, z);
          const h10 = this.heightAt(x1, z);
          const h11 = this.heightAt(x1, z1);
          const h01 = this.heightAt(x, z1);
          // 水面以下不画（水面由 Renderer 绘制）
          if (h00 < waterY - 0.3 && h10 < waterY - 0.3 && h11 < waterY - 0.3 && h01 < waterY - 0.3) continue;
          const col = this.colIdAt(x + cell / 2, z + cell / 2);
          r.pushWorldQuad(x, h00, z, x1, h10, z, x1, h11, z1, x, h01, z1, col, 1);
        }
      }
    }
  }

  colIdAt(x: number, z: number): number {
    const i = clamp(Math.round((x - this.x0) / this.cell), 0, SEG);
    const j = clamp(Math.round((z - this.z0) / this.cell), 0, SEG);
    return this.colId[j * this.n + i];
  }

  // 生成绿洲（埃及）
  setupOases(): void {
    if (this.map.id !== 'egypt') return;
    const cands: number[][] = [[-110, -60, 22], [200, -330, 24], [-120, 320, 20], [140, 200, 18], [-300, 60, 24]];
    this.oases = [];
    for (const c of cands) {
      if (this.track.nearest(c[0], c[1], this.track.halfW + c[2] + 14) < 0) this.oases.push(c);
    }
  }

  buildMountains(rnd: Rng, renderer: Renderer): void {
    const m = this.map;
    const noise = new Noise2D(Math.floor(rnd() * 1000));
    const count = m.id === 'egypt' ? 200 : 260;
    // 先画远环（更大半径、更浓雾），再画近环 → 正确的层次遮盖
    for (let q = 1; q >= 0; q--) {
      const R = q === 0 ? m.mountainR0 : m.mountainR0 + m.mountainR1 * 0.9;
      const hh = q === 0 ? m.mountainH0 + m.mountainH1 * 0.5 : (m.mountainH0 + m.mountainH1) * 1.25;
      const fogLv = q === 0 ? 2 : 5;
      const baseHeights: number[] = [];
      const capHeights: number[] = [];
      for (let i = 0; i < count; i++) {
        const a = (i / count) * Math.PI * 2;
        const nx = Math.cos(a) * 3;
        const nz = Math.sin(a) * 3;
        const top = hh * (0.35 + 0.65 * Math.max(0, 0.5 + noise.fbm(nx + R * 0.001, nz, 5) * 1.3));
        baseHeights.push(top);
        // 雪顶环：高峰抬高，低山与基础环同高（保证只露出雪顶部分）
        capHeights.push(m.mountainCap !== 0 && top > hh * 0.45 ? top + 6 : top);
      }
      const ringObj = new MountainRing();
      ringObj.radius = R;
      ringObj.heights = baseHeights;
      ringObj.colorId = renderer.palette.add(m.mountainColor);
      ringObj.fog = fogLv;
      renderer.mountains.push(ringObj);
      if (m.mountainCap !== 0) {
        const capRing = new MountainRing();
        capRing.radius = R + 4;
        capRing.heights = capHeights;
        capRing.colorId = renderer.palette.add(m.mountainCap);
        capRing.fog = fogLv;
        renderer.mountains.push(capRing);
      }
    }
  }
}
