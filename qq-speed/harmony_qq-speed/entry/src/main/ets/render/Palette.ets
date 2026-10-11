// 颜色调色板：面基色 + 静态光照档 + 雾档 → 预生成的颜色字符串缓存
// （把每帧的字符串拼接与颜色混合前置到加载期，渲染循环内只做查表）
import { clamp } from '../common/Util';

export const FOG_LEVELS: number = 14;
const SHADE_STEPS: number = 10;

export function parseHex(hex: string): number {
  let s = hex;
  if (s.charAt(0) === '#') s = s.substring(1);
  if (s.length === 3) {
    s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2);
  }
  return parseInt(s, 16);
}

function toHex2(v: number): string {
  const s = v.toString(16);
  return s.length < 2 ? '0' + s : s;
}

export class Palette {
  private map: Map<number, number> = new Map<number, number>();
  colors: number[] = [];
  fogColor: number = 0xcfe6fb;
  // 平行光方向（世界系，单位向量）
  sunX: number = 0.4;
  sunY: number = 0.8;
  sunZ: number = 0.3;
  private cache: Map<number, string> = new Map<number, string>();

  setSun(x: number, y: number, z: number): void {
    const l = Math.hypot(x, y, z) || 1;
    this.sunX = x / l;
    this.sunY = y / l;
    this.sunZ = z / l;
  }

  add(c: number): number {
    const found = this.map.get(c);
    if (found !== undefined) return found;
    const id = this.colors.length;
    this.colors.push(c);
    this.map.set(c, id);
    return id;
  }

  count(): number {
    return this.colors.length;
  }

  // 量化 key：(色 × 光照档 × 雾档) —— 面填充按 key 分桶合批
  keyOf(id: number, shade: number, fog: number): number {
    const sq = clamp(Math.round((shade - 0.3) / 1.3 * (SHADE_STEPS - 1)), 0, SHADE_STEPS - 1);
    const f = clamp(fog, 0, FOG_LEVELS - 1);
    return (id * SHADE_STEPS + sq) * FOG_LEVELS + f;
  }

  strByKey(key: number): string {
    const hit = this.cache.get(key);
    if (hit !== undefined) return hit;
    const fog = key % FOG_LEVELS;
    const rest = (key - fog) / FOG_LEVELS;
    const sq = rest % SHADE_STEPS;
    const id = (rest - sq) / SHADE_STEPS;
    const base = this.colors[id];
    let r = (base >> 16) & 255;
    let g = (base >> 8) & 255;
    let b = base & 255;
    const sh = 0.3 + (sq / (SHADE_STEPS - 1)) * 1.3;
    r = clamp(Math.round(r * sh), 0, 255);
    g = clamp(Math.round(g * sh), 0, 255);
    b = clamp(Math.round(b * sh), 0, 255);
    const t = fog / (FOG_LEVELS - 1);
    const fr = (this.fogColor >> 16) & 255;
    const fg = (this.fogColor >> 8) & 255;
    const fb = this.fogColor & 255;
    r = Math.round(r + (fr - r) * t);
    g = Math.round(g + (fg - g) * t);
    b = Math.round(b + (fb - b) * t);
    const s = '#' + toHex2(r) + toHex2(g) + toHex2(b);
    this.cache.set(key, s);
    return s;
  }

  // shade 0.3~1.6 连续值；fog 0..FOG_LEVELS-1
  str(id: number, shade: number, fog: number): string {
    return this.strByKey(this.keyOf(id, shade, fog));
  }
}

