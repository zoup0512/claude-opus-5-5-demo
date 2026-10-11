/**
 * 碰撞世界：所有静态碰撞体都是绕 Y 轴旋转的 OBB（与原版 physics.js 一致）
 * local->world: (x,z) -> (c*x + s*z, -s*x + c*z)，c=cos(yaw), s=sin(yaw)
 */
import { Vec3 } from './math3d';

export class Collider {
  x: number;
  y: number;
  z: number; // 中心
  hx: number;
  hy: number;
  hz: number; // 半尺寸
  yaw: number = 0;
  c: number = 1;
  s: number = 0;
  mat: string; // 命中材质：metal | wood | mesh
  solid: boolean; // 是否阻挡移动
  bullet: string; // block | pass | pen
  sight: boolean; // 是否阻挡视线
  surface: string; // 脚步声表面
  top: number;
  bottom: number;
  minX: number;
  maxX: number;
  minZ: number;
  maxZ: number;
  stamp: number = 0;
  tag: string;

  constructor(x: number, y: number, z: number, sx: number, sy: number, sz: number, yaw: number,
    mat: string, bullet: string, solid: boolean, sight: boolean, surface: string, tag: string) {
    this.x = x;
    this.y = y;
    this.z = z;
    this.hx = sx / 2;
    this.hy = sy / 2;
    this.hz = sz / 2;
    this.yaw = yaw;
    this.c = Math.cos(yaw);
    this.s = Math.sin(yaw);
    this.mat = mat;
    this.solid = solid;
    this.bullet = bullet;
    this.sight = sight;
    this.surface = surface;
    this.tag = tag;
    this.top = y + this.hy;
    this.bottom = y - this.hy;
    const ex = Math.abs(this.c) * this.hx + Math.abs(this.s) * this.hz;
    const ez = Math.abs(this.s) * this.hx + Math.abs(this.c) * this.hz;
    this.minX = x - ex;
    this.maxX = x + ex;
    this.minZ = z - ez;
    this.maxZ = z + ez;
  }

  toLocalX(wx: number, wz: number): number {
    const dx = wx - this.x, dz = wz - this.z;
    return this.c * dx - this.s * dz;
  }

  toLocalZ(wx: number, wz: number): number {
    const dx = wx - this.x, dz = wz - this.z;
    return this.s * dx + this.c * dz;
  }
}

export class RayHit {
  t: number = 0;
  exit: number = 0;
  nx: number = 0;
  ny: number = 0;
  nz: number = 0;
  collider: Collider | null = null;
}

const CELL = 4;

export class World {
  colliders: Collider[] = [];
  grid: Map<number, Array<Collider>> = new Map();
  stamp: number = 1;
  private cand: Collider[] = [];

  add(x: number, y: number, z: number, sx: number, sy: number, sz: number, yaw: number,
    props: ColliderOpts): Collider {
    const surface = props.surface.length > 0 ? props.surface : (props.mat === 'wood' ? 'wood' : 'metal');
    const c = new Collider(x, y, z, sx, sy, sz, yaw, props.mat, props.bullet, props.solid, props.sight,
      surface, props.tag);
    this.colliders.push(c);
    return c;
  }

  build(): void {
    this.grid.clear();
    for (const c of this.colliders) {
      const x0 = Math.floor(c.minX / CELL);
      const x1 = Math.floor(c.maxX / CELL);
      const z0 = Math.floor(c.minZ / CELL);
      const z1 = Math.floor(c.maxZ / CELL);
      for (let x = x0; x <= x1; x++) {
        for (let z = z0; z <= z1; z++) {
          const k = x * 1000 + z;
          let arr = this.grid.get(k);
          if (!arr) {
            arr = [];
            this.grid.set(k, arr);
          }
          arr.push(c);
        }
      }
    }
  }

  query(minX: number, minZ: number, maxX: number, maxZ: number): Collider[] {
    const out = this.cand;
    out.length = 0;
    const st = ++this.stamp;
    const x0 = Math.floor(minX / CELL);
    const x1 = Math.floor(maxX / CELL);
    const z0 = Math.floor(minZ / CELL);
    const z1 = Math.floor(maxZ / CELL);
    for (let x = x0; x <= x1; x++) {
      for (let z = z0; z <= z1; z++) {
        const arr = this.grid.get(x * 1000 + z);
        if (!arr) {
          continue;
        }
        for (const c of arr) {
          if (c.stamp === st) {
            continue;
          }
          c.stamp = st;
          if (c.maxX < minX || c.minX > maxX || c.maxZ < minZ || c.minZ > maxZ) {
            continue;
          }
          out.push(c);
        }
      }
    }
    return out;
  }

  /** 射线 vs 单个 OBB，返回 t 与世界法线 */
  static rayOBB(c: Collider, ox: number, oy: number, oz: number, dx: number, dy: number, dz: number,
    maxT: number, res: RayHit): boolean {
    const rx = ox - c.x, rz = oz - c.z;
    const lox = c.c * rx - c.s * rz, loz = c.s * rx + c.c * rz, loy = oy - c.y;
    const ldx = c.c * dx - c.s * dz, ldz = c.s * dx + c.c * dz, ldy = dy;
    let tmin = 0, tmax = maxT, axis = -1, sign = 0;
    // X 轴
    if (Math.abs(ldx) < 1e-9) {
      if (lox < -c.hx || lox > c.hx) {
        return false;
      }
    } else {
      let t1 = (-c.hx - lox) / ldx, t2 = (c.hx - lox) / ldx, sg = -1;
      if (t1 > t2) {
        const t = t1;
        t1 = t2;
        t2 = t;
        sg = 1;
      }
      if (t1 > tmin) {
        tmin = t1;
        axis = 0;
        sign = sg;
      }
      if (t2 < tmax) {
        tmax = t2;
      }
      if (tmin > tmax) {
        return false;
      }
    }
    if (Math.abs(ldy) < 1e-9) {
      if (loy < -c.hy || loy > c.hy) {
        return false;
      }
    } else {
      let t1 = (-c.hy - loy) / ldy, t2 = (c.hy - loy) / ldy, sg = -1;
      if (t1 > t2) {
        const t = t1;
        t1 = t2;
        t2 = t;
        sg = 1;
      }
      if (t1 > tmin) {
        tmin = t1;
        axis = 1;
        sign = sg;
      }
      if (t2 < tmax) {
        tmax = t2;
      }
      if (tmin > tmax) {
        return false;
      }
    }
    if (Math.abs(ldz) < 1e-9) {
      if (loz < -c.hz || loz > c.hz) {
        return false;
      }
    } else {
      let t1 = (-c.hz - loz) / ldz, t2 = (c.hz - loz) / ldz, sg = -1;
      if (t1 > t2) {
        const t = t1;
        t1 = t2;
        t2 = t;
        sg = 1;
      }
      if (t1 > tmin) {
        tmin = t1;
        axis = 2;
        sign = sg;
      }
      if (t2 < tmax) {
        tmax = t2;
      }
      if (tmin > tmax) {
        return false;
      }
    }
    if (axis < 0) { // 起点在盒内
      res.t = 0;
      res.exit = tmax;
      res.nx = -dx;
      res.ny = -dy;
      res.nz = -dz;
      return true;
    }
    res.t = tmin;
    res.exit = tmax;
    let lnx = 0, lny = 0, lnz = 0;
    if (axis === 0) {
      lnx = sign;
    } else if (axis === 1) {
      lny = sign;
    } else {
      lnz = sign;
    }
    res.nx = c.c * lnx + c.s * lnz;
    res.ny = lny;
    res.nz = -c.s * lnx + c.c * lnz;
    return true;
  }

  /** 射线检测。mode: 'move' | 'bullet' | 'sight'，返回最近命中或 null */
  raycast(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number, maxT: number,
    mode: string, out: RayHit): RayHit | null {
    const ex = ox + dx * maxT, ez = oz + dz * maxT;
    const cands = this.query(Math.min(ox, ex) - 0.1, Math.min(oz, ez) - 0.1, Math.max(ox, ex) + 0.1, Math.max(oz, ez) + 0.1);
    let best = maxT;
    let hit: Collider | null = null;
    const r = this.r;
    for (let i = 0; i < cands.length; i++) {
      const c = cands[i];
      if (mode === 'bullet' && c.bullet === 'pass') {
        continue;
      }
      if (mode === 'sight' && !c.sight) {
        continue;
      }
      if (mode === 'move' && !c.solid) {
        continue;
      }
      if (World.rayOBB(c, ox, oy, oz, dx, dy, dz, best, r) && r.t < best) {
        best = r.t;
        hit = c;
        out.nx = r.nx;
        out.ny = r.ny;
        out.nz = r.nz;
        out.exit = r.exit;
      }
    }
    if (!hit) {
      return null;
    }
    out.t = best;
    out.collider = hit;
    return out;
  }

  /** 沿射线所有命中（按 t 排序），用于穿透 */
  raycastAll(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number, maxT: number): PenHit[] {
    const ex = ox + dx * maxT, ez = oz + dz * maxT;
    const cands = this.query(Math.min(ox, ex) - 0.1, Math.min(oz, ez) - 0.1, Math.max(ox, ex) + 0.1, Math.max(oz, ez) + 0.1);
    const hits: PenHit[] = [];
    const r = this.r;
    for (const c of cands) {
      if (c.bullet === 'pass') {
        continue;
      }
      if (World.rayOBB(c, ox, oy, oz, dx, dy, dz, maxT, r)) {
        hits.push(new PenHit(r.t, r.exit, r.nx, r.ny, r.nz, c));
      }
    }
    hits.sort((a, b) => a.t - b.t);
    return hits;
  }

  /** 圆（XZ）与 OBB 的最近点关系 */
  static circleOBB(c: Collider, px: number, pz: number, r: number, out: PushOut): boolean {
    const lx = c.toLocalX(px, pz), lz = c.toLocalZ(px, pz);
    const qx = Math.max(-c.hx, Math.min(c.hx, lx));
    const qz = Math.max(-c.hz, Math.min(c.hz, lz));
    const dx = lx - qx, dz = lz - qz;
    const d2 = dx * dx + dz * dz;
    if (d2 >= r * r) {
      return false;
    }
    if (d2 > 1e-10) {
      const d = Math.sqrt(d2);
      const wx = c.c * (dx / d) + c.s * (dz / d);
      const wz = -c.s * (dx / d) + c.c * (dz / d);
      out.nx = wx;
      out.nz = wz;
      out.pen = r - d;
    } else {
      const px2 = c.hx - Math.abs(lx), pz2 = c.hz - Math.abs(lz);
      let lnx = 0, lnz = 0, pen: number;
      if (px2 < pz2) {
        lnx = lx >= 0 ? 1 : -1;
        pen = px2 + r;
      } else {
        lnz = lz >= 0 ? 1 : -1;
        pen = pz2 + r;
      }
      out.nx = c.c * lnx + c.s * lnz;
      out.nz = -c.s * lnx + c.c * lnz;
      out.pen = pen;
    }
    return true;
  }

  /** 胶囊空间是否被占用 */
  blocked(px: number, py: number, pz: number, r: number, h: number): boolean {
    const cands = this.query(px - r, pz - r, px + r, pz + r);
    for (const c of cands) {
      if (!c.solid) {
        continue;
      }
      if (c.top <= py + 0.001 || c.bottom >= py + h - 0.001) {
        continue;
      }
      if (World.circleOBB(c, px, pz, r, this.o)) {
        return true;
      }
    }
    return false;
  }

  /** 脚下最高支撑面 */
  support(px: number, pz: number, r: number, maxY: number): Support | null {
    const cands = this.query(px - r, pz - r, px + r, pz + r);
    let best = -Infinity;
    let bc: Collider | null = null;
    for (const c of cands) {
      if (!c.solid) {
        continue;
      }
      if (c.top > maxY || c.top <= best) {
        continue;
      }
      if (World.circleOBB(c, px, pz, r, this.o)) {
        best = c.top;
        bc = c;
      }
    }
    return bc !== null ? new Support(best, bc) : null;
  }

  /** 角色移动 */
  move(ent: MoveEntity, dt: number): void {
    const vx = ent.vel.x, vy = ent.vel.y, vz = ent.vel.z;
    const dist = Math.hypot(vx, vy, vz) * dt;
    const n = Math.max(1, Math.ceil(dist / 0.12));
    const h = dt / n;
    const o = this.o;
    const r = ent.radius;
    let landed = false;
    let landSpeed = 0;
    for (let s = 0; s < n; s++) {
      const p = ent.pos;
      p.x += ent.vel.x * h;
      p.z += ent.vel.z * h;
      for (let it = 0; it < 3; it++) {
        const cands = this.query(p.x - r, p.z - r, p.x + r, p.z + r);
        let any = false;
        for (const c of cands) {
          if (!c.solid) {
            continue;
          }
          const head = p.y + ent.height;
          if (c.top <= p.y + 0.001 || c.bottom >= head - 0.001) {
            continue;
          }
          if (!World.circleOBB(c, p.x, p.z, r, o)) {
            continue;
          }
          const rise = c.top - p.y;
          if (ent.onGround && rise > 0 && rise <= ent.stepHeight &&
            !this.blocked(p.x, c.top, p.z, r * 0.95, ent.height)) {
            p.y = c.top;
            ent.stepped = (ent.stepped || 0) + rise;
            any = true;
            continue;
          }
          p.x += o.nx * (o.pen + 0.0005);
          p.z += o.nz * (o.pen + 0.0005);
          const vn = ent.vel.x * o.nx + ent.vel.z * o.nz;
          if (vn < 0) {
            ent.vel.x -= o.nx * vn;
            ent.vel.z -= o.nz * vn;
          }
          any = true;
        }
        if (!any) {
          break;
        }
      }
      // 垂直
      const prevY = p.y;
      p.y += ent.vel.y * h;
      if (ent.vel.y <= 0) {
        const sup = this.support(p.x, p.z, r * 0.92, prevY + 0.001);
        const snap = ent.onGround && ent.vel.y <= 0.01 ? Math.max(0.3, -ent.vel.y * h) : 0;
        if (sup && p.y <= sup.y + snap) {
          if (!ent.onGround) {
            landed = true;
            landSpeed = -ent.vel.y;
          }
          p.y = sup.y;
          ent.vel.y = 0;
          ent.onGround = true;
          ent.ground = sup.collider;
        } else {
          ent.onGround = false;
          ent.ground = null;
        }
      } else {
        ent.onGround = false;
        ent.ground = null;
        // 顶头
        const cands = this.query(p.x - r, p.z - r, p.x + r, p.z + r);
        for (const c of cands) {
          if (!c.solid) {
            continue;
          }
          const headPrev = prevY + ent.height, head = p.y + ent.height;
          if (c.bottom >= headPrev - 0.01 && c.bottom < head && World.circleOBB(c, p.x, p.z, r * 0.9, o)) {
            p.y = c.bottom - ent.height - 0.001;
            ent.vel.y = 0;
          }
        }
      }
    }
    ent.landed = landed;
    ent.landSpeed = landSpeed;
  }

  private r: RayHit = new RayHit();
  private o: PushOut = new PushOut();
}

export interface ColliderOpts {
  mat: string;
  bullet: string;
  solid: boolean;
  sight: boolean;
  surface: string;
  tag: string;
}

export class PenHit {
  t: number;
  exit: number;
  nx: number;
  ny: number;
  nz: number;
  collider: Collider;

  constructor(t: number, exit: number, nx: number, ny: number, nz: number, collider: Collider) {
    this.t = t;
    this.exit = exit;
    this.nx = nx;
    this.ny = ny;
    this.nz = nz;
    this.collider = collider;
  }
}

export class PushOut {
  nx: number = 0;
  nz: number = 0;
  pen: number = 0;
}

export class Support {
  y: number;
  collider: Collider;

  constructor(y: number, collider: Collider) {
    this.y = y;
    this.collider = collider;
  }
}

export interface MoveEntity {
  pos: Vec3;
  vel: Vec3;
  radius: number;
  height: number;
  onGround: boolean;
  ground: Collider | null;
  stepHeight: number;
  landed: boolean;
  landSpeed: number;
  stepped?: number;
}

// ============== 寻路网格（地面层） ==============
export class NavGrid {
  x0: number;
  z0: number;
  cell: number;
  w: number;
  h: number;
  block: Uint8Array;
  cost: Float32Array;
  private open: Int32Array;
  private g: Float32Array;
  private f: Float32Array;
  private parent: Int32Array;
  private seen: Uint32Array;
  private closed: Uint32Array;
  private gen: number = 1;

  constructor(world: World, x0: number, z0: number, x1: number, z1: number, cell: number, agentR: number) {
    this.x0 = x0;
    this.z0 = z0;
    this.cell = cell;
    this.w = Math.ceil((x1 - x0) / cell);
    this.h = Math.ceil((z1 - z0) / cell);
    this.block = new Uint8Array(this.w * this.h);
    this.cost = new Float32Array(this.w * this.h);
    const o = new PushOut();
    for (let j = 0; j < this.h; j++) {
      for (let i = 0; i < this.w; i++) {
        const cx = x0 + (i + 0.5) * cell, cz = z0 + (j + 0.5) * cell;
        const cands = world.query(cx - agentR - 0.3, cz - agentR - 0.3, cx + agentR + 0.3, cz + agentR + 0.3);
        let b = 0, near = 0;
        for (const c of cands) {
          if (!c.solid) {
            continue;
          }
          if (c.bottom > 1.7 || c.top < 0.36) {
            continue;
          }
          if (World.circleOBB(c, cx, cz, agentR, o)) {
            b = 1;
            break;
          }
          if (World.circleOBB(c, cx, cz, agentR + 0.45, o)) {
            near = 1;
          }
        }
        this.block[j * this.w + i] = b;
        this.cost[j * this.w + i] = near ? 1.6 : 1;
      }
    }
    // 屋顶过低（<2m）的格子不可走
    for (let j = 0; j < this.h; j++) {
      for (let i = 0; i < this.w; i++) {
        if (this.block[j * this.w + i]) {
          continue;
        }
        const cx = x0 + (i + 0.5) * cell, cz = z0 + (j + 0.5) * cell;
        if (world.blocked(cx, 0.4, cz, agentR * 0.8, 1.4)) {
          this.block[j * this.w + i] = 1;
        }
      }
    }
    this.open = new Int32Array(this.w * this.h);
    this.g = new Float32Array(this.w * this.h);
    this.f = new Float32Array(this.w * this.h);
    this.parent = new Int32Array(this.w * this.h);
    this.seen = new Uint32Array(this.w * this.h);
    this.closed = new Uint32Array(this.w * this.h);
  }

  idx(x: number, z: number): number {
    const i = Math.floor((x - this.x0) / this.cell);
    const j = Math.floor((z - this.z0) / this.cell);
    if (i < 0 || j < 0 || i >= this.w || j >= this.h) {
      return -1;
    }
    return j * this.w + i;
  }

  centerC(k: number): number {
    return this.x0 + ((k % this.w) + 0.5) * this.cell;
  }

  centerZ(k: number): number {
    return this.z0 + (Math.floor(k / this.w) + 0.5) * this.cell;
  }

  walkable(k: number): boolean {
    return k >= 0 && !this.block[k];
  }

  nearestFree(k: number): number {
    if (this.walkable(k)) {
      return k;
    }
    const i0 = k % this.w, j0 = Math.floor(k / this.w);
    for (let r = 1; r < 12; r++) {
      for (let dj = -r; dj <= r; dj++) {
        for (let di = -r; di <= r; di++) {
          if (Math.max(Math.abs(di), Math.abs(dj)) !== r) {
            continue;
          }
          const i = i0 + di, j = j0 + dj;
          if (i < 0 || j < 0 || i >= this.w || j >= this.h) {
            continue;
          }
          const kk = j * this.w + i;
          if (!this.block[kk]) {
            return kk;
          }
        }
      }
    }
    return -1;
  }

  lineFree(ax: number, az: number, bx: number, bz: number): boolean {
    const d = Math.hypot(bx - ax, bz - az);
    const n = Math.ceil(d / (this.cell * 0.5));
    for (let i = 1; i < n; i++) {
      const t = i / n;
      const k = this.idx(ax + (bx - ax) * t, az + (bz - az) * t);
      if (k < 0 || this.block[k]) {
        return false;
      }
    }
    return true;
  }

  findPath(ax: number, az: number, bx: number, bz: number): number[][] | null {
    let s = this.idx(ax, az);
    let e = this.idx(bx, bz);
    if (s < 0 || e < 0) {
      return null;
    }
    s = this.nearestFree(s);
    e = this.nearestFree(e);
    if (s < 0 || e < 0) {
      return null;
    }
    const gen = ++this.gen;
    const W = this.w;
    const heap: number[] = [];
    const g = this.g, f = this.f;
    const push = (k: number): void => {
      heap.push(k);
      let i = heap.length - 1;
      while (i > 0) {
        const p = (i - 1) >> 1;
        if (f[heap[p]] <= f[heap[i]]) {
          break;
        }
        const tmp = heap[p];
        heap[p] = heap[i];
        heap[i] = tmp;
        i = p;
      }
    };
    const pop = (): number => {
      const top = heap[0] as number;
      const last = heap.pop() as number;
      if (heap.length) {
        heap[0] = last;
        let i = 0;
        for (; ;) {
          const l = i * 2 + 1, r = l + 1;
          let m = i;
          if (l < heap.length && f[heap[l]] < f[heap[m]]) {
            m = l;
          }
          if (r < heap.length && f[heap[r]] < f[heap[m]]) {
            m = r;
          }
          if (m === i) {
            break;
          }
          const tmp = heap[m];
          heap[m] = heap[i];
          heap[i] = tmp;
          i = m;
        }
      }
      return top;
    };
    const ex = e % W, ez = Math.floor(e / W);
    const hfn = (k: number): number => {
      const dx = Math.abs(k % W - ex), dz = Math.abs(Math.floor(k / W) - ez);
      return dx + dz + (1.4142 - 2) * Math.min(dx, dz);
    };
    g[s] = 0;
    f[s] = hfn(s);
    this.seen[s] = gen;
    this.parent[s] = -1;
    push(s);
    let found = false;
    let iter = 0;
    while (heap.length && iter++ < 20000) {
      const k = pop();
      if (this.closed[k] === gen) {
        continue;
      }
      this.closed[k] = gen;
      if (k === e) {
        found = true;
        break;
      }
      const ki = k % W, kj = Math.floor(k / W);
      for (let dj = -1; dj <= 1; dj++) {
        for (let di = -1; di <= 1; di++) {
          if (!di && !dj) {
            continue;
          }
          const ni = ki + di, nj = kj + dj;
          if (ni < 0 || nj < 0 || ni >= W || nj >= this.h) {
            continue;
          }
          const nk = nj * W + ni;
          if (this.block[nk] || this.closed[nk] === gen) {
            continue;
          }
          if (di && dj && (this.block[kj * W + ni] || this.block[nj * W + ki])) {
            continue;
          }
          const ng = g[k] + (di && dj ? 1.4142 : 1) * this.cost[nk];
          if (this.seen[nk] !== gen || ng < g[nk]) {
            this.seen[nk] = gen;
            g[nk] = ng;
            f[nk] = ng + hfn(nk);
            this.parent[nk] = k;
            push(nk);
          }
        }
      }
    }
    if (!found) {
      return null;
    }
    const raw: number[][] = [];
    for (let k = e; k !== -1; k = this.parent[k]) {
      raw.push([this.centerC(k), this.centerZ(k)]);
    }
    raw.reverse();
    raw[raw.length - 1] = [bx, bz];
    // 路径拉直
    const out: number[][] = [raw[0]];
    let a = 0;
    while (a < raw.length - 1) {
      let b = raw.length - 1;
      while (b > a + 1 && !this.lineFree(raw[a][0], raw[a][1], raw[b][0], raw[b][1])) {
        b--;
      }
      out.push(raw[b]);
      a = b;
    }
    return out;
  }

  randomFree(rnd: () => number, x0: number, z0: number, x1: number, z1: number): number[] | null {
    for (let t = 0; t < 60; t++) {
      const x = x0 + rnd() * (x1 - x0), z = z0 + rnd() * (z1 - z0);
      const k = this.idx(x, z);
      if (this.walkable(k)) {
        return [x, z];
      }
    }
    return null;
  }
}
