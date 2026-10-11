// AI 对手（自 H5 版 ai.js 移植：赛车线、过弯极限、放氮气时机、橡皮筋）
import { clamp, damp, wrapAngle, Rng } from '../common/Util';
import { Track, TrackSample } from './Track';
import { TUNE } from './Vehicle';
import { RacerBase } from './RacerBase';

export class AICar extends RacerBase {
  track: Track;
  skill: number = 1; // 0.8 ~ 1.1
  rnd: Rng;
  personal: number = 0;
  s2: TrackSample = new TrackSample();
  startDelay: number = 0.1;
  yawOff: number = 0;
  driftDir: number = 0;
  nitroCd: number = 6;
  slope: number = 0;
  bank: number = 0;
  trackHd: number = 0;
  vyGround: number = 0;

  constructor(track: Track, name: string, skill: number, rnd: Rng) {
    super();
    this.track = track;
    this.isPlayer = false;
    this.name = name;
    this.skill = skill;
    this.rnd = rnd;
    this.personal = (rnd() - 0.5) * 0.6;
    this.reset(0, 0);
  }

  reset(d: number, lat: number): void {
    this.dist = d;
    this.lat = lat;
    this.latV = 0;
    this.s = 0;
    this.nitroTime = 0;
    this.nitroCd = 6 + this.rnd() * 6;
    this.yawOff = 0;
    this.drifting = false;
    this.driftDir = 0;
    this.vy = 0;
    this.airborne = false;
    this.spin = 0;
    this.slowTime = 0;
    this.shield = 0;
    this.magnet = 0;
    this.pushD = 0;
    this.spinAng = 0;
    this.startDelay = 0.05 + this.rnd() * 0.25;
    this.itemTimer = 2 + this.rnd() * 3;
    const s = this.track.sample(d, this.s2);
    this.y = s.y;
    this.d = s.d;
    this.hint = s.i;
    this.h = s.hd;
    this.m = s.hd;
  }

  update(dt: number, active: boolean, raceTime: number, rubber: number): void {
    const tr = this.track;
    let vmaxBase = TUNE.vmax * (0.8 + 0.2 * this.skill) * rubber;
    if (this.nitroTime > 0) {
      vmaxBase += 17;
      this.nitroTime -= dt;
    }
    if (this.magnet > 0) {
      vmaxBase += 10;
      this.magnet -= dt;
    }
    if (this.slowTime > 0) {
      vmaxBase *= 0.55;
      this.slowTime -= dt;
    }
    if (this.shield > 0) this.shield -= dt;
    const d = this.dist;
    const cNow = tr.curvAhead(d, 8);
    const look = 18 + this.s * 1.25;
    const cAhead = tr.curvAhead(d, look);
    // 过弯极限（含漂移）
    const A = 16 + 30 * this.skill;
    const vCorner = Math.sqrt(A / Math.max(Math.abs(cAhead), 1e-4));
    let vt = Math.min(vmaxBase, vCorner + (this.nitroTime > 0 ? 6 : 0));
    let spinning = false;
    if (this.spin > 0) {
      this.spin -= dt;
      vt = 5;
      spinning = true;
    }
    if (!active || raceTime < this.startDelay) vt = 0;
    if (this.s < vt) this.s += (this.nitroTime > 0 ? 34 : 20 + 4 * this.skill) * (1 - Math.pow(this.s / Math.max(vt, 1), 2) * 0.7) * dt;
    else this.s -= Math.min(this.s - vt, (spinning ? 50 : 30) * dt);
    this.s = Math.max(0, this.s);

    // 直道上找机会放氮气
    this.nitroCd -= dt;
    if (active && this.nitroCd <= 0 && Math.abs(tr.curvAhead(d, 140)) < 0.006 && this.s > 35) {
      this.nitroTime = 2.6;
      this.nitroCd = (6 + this.rnd() * 8) / this.skill;
    }

    // 赛车线：出入弯走内线
    const hw = tr.halfW - 2.2;
    const inside = -Math.sign(cAhead) * clamp(Math.abs(cAhead) * 45, 0, 1) * hw * 0.8;
    const target = clamp(inside + this.personal * hw * 0.8, -hw, hw);
    const accLat = clamp((target - this.lat) * 2.2 - this.latV * 2.4, -14, 14);
    this.latV += accLat * dt;
    this.lat += this.latV * dt;
    if (Math.abs(this.lat) > hw) {
      this.lat = Math.sign(this.lat) * hw;
      this.latV *= -0.3;
    }

    this.dist += this.s * dt + this.pushD;
    this.pushD = 0;
    const s = tr.sample(this.dist, this.s2);
    this.d = s.d;
    this.hint = s.i;
    this.x = s.x + s.rx * this.lat;
    this.z = s.z + s.rz * this.lat;
    const gy = s.y + this.lat * Math.sin(s.bank);
    // 腾空
    if (this.airborne) {
      this.vy -= TUNE.gravity * dt;
      this.y += this.vy * dt;
      if (this.y <= gy) {
        this.y = gy;
        this.airborne = false;
        this.vy = 0;
        this.vyGround = 0;
      }
    } else if (this.s > 18 && this.s * this.s * -tr.vcurv[s.i] > TUNE.gravity) {
      this.airborne = true;
      this.vy = tr.sslope[s.i] * this.s;
      this.y = gy + this.vy * dt;
    } else this.y = gy;

    // 视觉漂移：弯中甩尾
    const wantDrift = Math.abs(cNow) > 0.012 && this.s > 26;
    this.drifting = wantDrift;
    this.driftDir = Math.sign(cNow);
    const yawT = wantDrift ? Math.sign(cNow) * Math.min(0.62, Math.abs(cNow) * 22) : 0;
    this.yawOff = damp(this.yawOff, yawT, 5, dt);
    const latHead = Math.atan2(this.latV, Math.max(this.s, 3));
    this.h = s.hd + latHead + this.yawOff;
    this.m = this.h;
    if (spinning) this.spinAng += 10 * dt;
    else this.spinAng = 0;
    this.slope = tr.slope[s.i];
    this.bank = s.bank;
    this.trackHd = s.hd;
  }
}
