// 玩家车辆物理（自 H5 版 vehicle.js 移植，手感参数 1:1 保留）
import { clamp, wrapAngle, damp } from '../common/Util';
import { Track, TrackSample } from './Track';
import { RacerBase } from './RacerBase';

export class TUNE {
  static readonly vmax: number = 55;          // ~198 km/h
  static readonly vmaxNitro: number = 76;     // ~274 km/h
  static readonly accel: number = 24;
  static readonly nitroAccel: number = 40;
  static readonly brake: number = 45;
  static readonly reverseMax: number = 12;
  static readonly roll: number = 2.2;
  static readonly turnRate: number = 1.9;
  static readonly grip: number = 12;
  static readonly driftMinSpeed: number = 13;
  static readonly driftYaw: number = 1.5;
  static readonly driftYawAlign: number = 0.85;
  static readonly driftGrip: number = 2.0;
  static readonly driftGripRelease: number = 5.2;
  static readonly maxDriftAngle: number = 1.15;
  static readonly smallWindow: number = 0.5;
  static readonly gaugeRate: number = 0.36;
  static readonly nitroTime: number = 2.8;
  static readonly gravity: number = 30;
}

export class InputState {
  up: boolean = false;
  down: boolean = false;
  left: boolean = false;
  right: boolean = false;
  shift: boolean = false;
  upPressed: boolean = false;
  wPressed: boolean = false;
  nitroPressed: boolean = false;
  swapPressed: boolean = false;
  resetPressed: boolean = false;
}

export const NO_INPUT: InputState = new InputState();

export class GameEvent {
  type: string = '';
  p0: number = 0;
  p1: number = 0;
  x: number = 0;
  z: number = 0;
  perfect: boolean = false;
  dbl: boolean = false;
}

export class PlayerCar extends RacerBase {
  track: Track;
  events: GameEvent[] = [];
  proj: TrackSample = new TrackSample();
  vyGround: number = 0;
  airTime: number = 0;
  steer: number = 0;
  driftDir: number = 0;
  driftTime: number = 0;
  driftAngle: number = 0;
  releaseTime: number = 0;
  nitroCount: number = 0;
  smallBoostPower: number = 0;
  smallWindow: number = 0;
  windowKind: string = '';
  impact: number = 0;
  wrongWay: number = 0;
  vmaxNow: number = 55;
  lastD: number = 0;
  owed: boolean = true;
  half: boolean = false;

  constructor(track: Track, name: string) {
    super();
    this.track = track;
    this.isPlayer = true;
    this.name = name;
    this.reset(0, 0);
  }

  reset(d: number, lat: number): void {
    const s = this.track.sample(d, new TrackSample());
    this.x = s.x + s.rx * lat;
    this.z = s.z + s.rz * lat;
    this.y = s.y + 0.05;
    this.h = s.hd;
    this.m = s.hd;
    this.s = 0;
    this.vy = 0;
    this.airborne = false;
    this.airTime = 0;
    this.steer = 0;
    this.drifting = false;
    this.driftDir = 0;
    this.driftTime = 0;
    this.driftAngle = 0;
    this.gauge = 0;
    this.nitroCount = 0;
    this.nitroTime = 0;
    this.smallBoost = 0;
    this.smallBoostPower = 0;
    this.smallWindow = 0;
    this.padTime = 0;
    this.startBoost = 0;
    this.spin = 0;
    this.shield = 0;
    this.slowTime = 0;
    this.magnet = 0;
    this.hint = -1;
    this.track.project(this.x, this.y, this.z, -1, this.proj);
    this.hint = this.proj.i;
    this.d = this.proj.d;
    this.lat = this.proj.lat;
  }

  emit(type: string): void {
    const e = new GameEvent();
    e.type = type;
    this.events.push(e);
  }

  emitData(type: string, p0: number, p1: number, x: number, z: number): void {
    const e = new GameEvent();
    e.type = type;
    e.p0 = p0;
    e.p1 = p1;
    e.x = x;
    e.z = z;
    this.events.push(e);
  }

  get boosting(): boolean {
    return this.nitroTime > 0 || this.smallBoost > 0 || this.padTime > 0 || this.startBoost > 0;
  }

  triggerNitro(fromItem: boolean): boolean {
    if (!fromItem) {
      if (this.nitroCount <= 0) return false;
      this.nitroCount--;
    }
    const wasSmall = this.smallBoost > 0.35;
    this.nitroTime = Math.min(4.5, Math.max(0, this.nitroTime) + TUNE.nitroTime);
    this.s = Math.max(this.s, 20) + 4;
    const ev = new GameEvent();
    ev.type = 'nitro';
    ev.dbl = wasSmall;
    this.events.push(ev);
    if (wasSmall) this.emit('double');
    return true;
  }

  endDrift(clean: boolean): void {
    if (!this.drifting) return;
    this.drifting = false;
    if (clean && this.driftTime > 0.22) {
      this.smallWindow = TUNE.smallWindow;
      this.windowKind = 'drift';
    }
    this.emit('driftEnd');
  }

  update(dt: number, inpIn: InputState, active: boolean, itemMode: boolean): void {
    const T = TUNE;
    const tr = this.track;
    let inp = inpIn;
    if (!active) inp = NO_INPUT;
    const spinning = this.spin > 0;
    if (spinning) {
      this.spin -= dt;
      inp = NO_INPUT;
    }

    // 平滑转向
    const steerT = (inp.left ? 1 : 0) - (inp.right ? 1 : 0);
    this.steer = damp(this.steer, steerT, 12, dt);

    // 加速状态
    let vmax = T.vmax;
    let acc = T.accel;
    if (this.nitroTime > 0) {
      vmax = T.vmaxNitro;
      acc = T.nitroAccel;
      this.nitroTime -= dt;
    }
    if (this.smallBoost > 0) {
      vmax += this.smallBoostPower;
      acc += 14;
      this.smallBoost -= dt;
    }
    if (this.padTime > 0) {
      vmax += 12;
      acc += 20;
      this.padTime -= dt;
    }
    if (this.startBoost > 0) {
      vmax += 10;
      acc += 26;
      this.startBoost -= dt;
    }
    if (this.magnet > 0) {
      vmax += 10;
      acc += 12;
      this.magnet -= dt;
    }
    vmax = Math.min(vmax, 86);
    if (this.slowTime > 0) {
      vmax *= 0.55;
      this.slowTime -= dt;
    }
    if (this.shield > 0) this.shield -= dt;
    this.vmaxNow = vmax;

    // 小喷 / 落地喷窗口
    if (this.smallWindow > 0) {
      this.smallWindow -= dt;
      if (inp.upPressed || inp.wPressed) {
        const elapsed = (this.windowKind === 'drift' ? T.smallWindow : 0.45) - this.smallWindow;
        const perfect = elapsed < 0.2;
        const dbl = this.nitroTime > 0;
        this.smallBoost = perfect ? 1.0 : 0.75;
        this.smallBoostPower = (perfect ? 11 : 8) + (dbl ? 5 : 0);
        this.s += perfect ? 5.5 : 4;
        if (dbl) this.nitroTime += 0.3;
        const ev = new GameEvent();
        ev.type = this.windowKind === 'land' ? 'landBoost' : 'smallBoost';
        ev.perfect = perfect;
        ev.dbl = dbl;
        this.events.push(ev);
        if (dbl) this.emit('double');
        this.smallWindow = 0;
      }
    }
    if (inp.nitroPressed && !itemMode) this.triggerNitro(false);

    const onGround = !this.airborne;
    // 纵向
    this.throttle = inp.up ? 1 : inp.down ? -1 : 0;
    if (onGround) {
      if (inp.up) {
        if (this.s < 0) this.s += T.brake * dt;
        else if (this.s < vmax) this.s += acc * (1 - Math.pow(this.s / vmax, 2) * 0.85) * dt;
      } else if (inp.down) {
        if (this.s > 0.5) this.s -= T.brake * dt;
        else this.s = Math.max(-T.reverseMax, this.s - 14 * dt);
      } else {
        const dec = (T.roll + Math.abs(this.s) * 0.06) * dt;
        this.s = Math.abs(this.s) <= dec ? 0 : this.s - Math.sign(this.s) * dec;
      }
      if (this.s > vmax) this.s -= (this.s - vmax) * 1.1 * dt;
      // 坡度影响
      this.s -= tr.slope[this.hint] * Math.cos(this.h - tr.hd[this.hint]) * 6 * dt;
    }

    // 进入漂移：按住漂移 + 方向
    if (!this.drifting && inp.shift && steerT !== 0 && this.s > T.driftMinSpeed && onGround && !spinning) {
      this.drifting = true;
      this.driftDir = steerT;
      this.driftTime = 0;
      this.releaseTime = 0;
      this.smallWindow = 0;
      this.h += this.driftDir * 0.07;
      this.emit('driftStart');
    }

    if (this.drifting) {
      const align = steerT * this.driftDir;
      const held = inp.shift;
      if (held) this.releaseTime = 0;
      else this.releaseTime += dt;
      const yaw = held ? T.driftYaw + T.driftYawAlign * align : (0.45 + 0.9 * align) * Math.exp(-2.2 * this.releaseTime);
      this.h += this.driftDir * yaw * clamp(this.s / 26, 0.35, 1) * dt * (onGround ? 1 : 0.4);
      const k = held ? T.driftGrip : T.driftGripRelease;
      this.m += wrapAngle(this.h - this.m) * (1 - Math.exp(-k * dt));
      let a = wrapAngle(this.h - this.m);
      if (Math.abs(a) > T.maxDriftAngle) {
        this.m = this.h - Math.sign(a) * T.maxDriftAngle;
        a = Math.sign(a) * T.maxDriftAngle;
      }
      this.driftAngle = a;
      const sa = Math.abs(Math.sin(a));
      if (onGround) this.s -= (2.5 + 11 * sa) * dt;
      if (!itemMode && onGround) {
        this.gauge += dt * T.gaugeRate * (0.3 + sa * 1.7) * clamp(this.s / 35, 0.3, 1.1);
        while (this.gauge >= 1) {
          if (this.nitroCount < 2) {
            this.nitroCount++;
            this.gauge -= 1;
            this.emit('gaugeFull');
          } else {
            this.gauge = 1;
            break;
          }
        }
      }
      this.driftTime += dt;
      if ((!held && (Math.abs(a) < 0.1 || (align < 0 && Math.abs(a) < 0.26))) || this.s < 7) {
        this.endDrift(this.s >= 7);
      }
    } else {
      this.driftAngle = damp(this.driftAngle, 0, 10, dt);
      const dir = this.s >= 0 ? 1 : -1;
      const sp = Math.abs(this.s);
      const turn = T.turnRate * clamp(sp / 9, 0, 1) * (1 - 0.55 * clamp(sp / T.vmax, 0, 1.3));
      this.h += this.steer * turn * dt * dir * (onGround ? 1 : 0.35);
      if (this.s >= 0) this.m += wrapAngle(this.h - this.m) * (1 - Math.exp(-T.grip * dt));
      else this.m = this.h;
    }
    if (spinning) this.h += 9 * dt;

    // 位置积分
    const dirSign = this.s >= 0 ? 1 : -1;
    const mv = this.s >= 0 ? this.m : this.h;
    let vx = Math.sin(mv) * Math.abs(this.s) * dirSign;
    let vz = Math.cos(mv) * Math.abs(this.s) * dirSign;
    this.x += vx * dt;
    this.z += vz * dt;

    const p = tr.project(this.x, this.y, this.z, this.hint, this.proj);
    this.hint = p.i;
    this.d = p.d;

    // 护栏碰撞
    const lim = tr.halfW - 1.1;
    this.impact = 0;
    if (Math.abs(p.lat) > lim) {
      const sg = Math.sign(p.lat);
      const nx = p.rx * sg;
      const nz = p.rz * sg;
      const over = Math.abs(p.lat) - lim;
      this.x -= nx * over;
      this.z -= nz * over;
      const vn = vx * nx + vz * nz;
      if (vn > 0) {
        const sp = Math.max(1, Math.hypot(vx, vz));
        const impact = vn / sp;
        vx -= nx * vn * 1.25;
        vz -= nz * vn * 1.25;
        const keep = 1 - 0.45 * impact;
        vx *= keep;
        vz *= keep;
        const ns = Math.hypot(vx, vz);
        if (this.s >= 0) {
          this.s = ns;
          if (ns > 0.5) this.m = Math.atan2(vx, vz);
          const th = Math.abs(wrapAngle(this.h - p.hd)) < Math.PI / 2 ? p.hd : p.hd + Math.PI;
          this.h += wrapAngle(th - this.h) * Math.min(1, 0.6 * impact + 0.05);
        } else this.s = -ns;
        this.impact = impact * sp;
        if (impact > 0.3 && this.drifting) this.endDrift(false);
        if (impact * sp > 6) this.emitData('crash', impact * sp, 0, this.x - nx * 0.9, this.z - nz * 0.9);
        else if (sp > 8) this.emitData('scrape', 0, 0, this.x + nx * 1.0, this.z + nz * 1.0);
      }
      p.lat = sg * lim;
    }
    this.lat = p.lat;

    // 垂直：贴地 / 腾空 / 落地
    const groundY = p.y + p.lat * Math.sin(p.bank);
    if (this.airborne) {
      this.vy -= T.gravity * dt;
      this.y += this.vy * dt;
      this.airTime += dt;
      if (this.y <= groundY) {
        this.y = groundY;
        this.airborne = false;
        this.vy = 0;
        this.vyGround = 0;
        this.emitData('land', this.airTime, 0, 0, 0);
        if (this.airTime > 0.3) {
          this.smallWindow = 0.45;
          this.windowKind = 'land';
        }
        this.airTime = 0;
      }
    } else {
      const va = this.s * Math.cos(this.m - p.hd);
      if (va > 18 && va * va * -tr.vcurv[p.i] > T.gravity) {
        this.airborne = true;
        this.airTime = 0;
        this.vy = tr.sslope[p.i] * va;
        this.y = groundY + this.vy * dt;
        if (this.drifting) this.endDrift(false);
      } else this.y = groundY;
    }

    // 逆行检测
    const fwdDot = Math.cos(wrapAngle(this.h - p.hd));
    if (fwdDot < -0.35 && this.s > 4) this.wrongWay += dt;
    else this.wrongWay = Math.max(0, this.wrongWay - dt * 2);

    // 加速带
    for (const bp of tr.boostPads) {
      let dd = this.d - (bp.d - bp.len / 2);
      if (dd < 0) dd += tr.length;
      if (dd < bp.len && Math.abs(this.lat - bp.lat) < bp.halfW + 0.6 && !this.airborne) {
        if (this.padTime < 0.6) {
          this.emit('pad');
          this.s = Math.min(this.s + 6, 72);
        }
        this.padTime = 1.1;
      }
    }
  }
}
