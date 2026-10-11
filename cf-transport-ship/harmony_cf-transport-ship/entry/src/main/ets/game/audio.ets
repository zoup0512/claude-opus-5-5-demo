/**
 * 程序化音频：PCM 合成 + AudioRenderer 混音（移植并简化自原版 audio.js）。
 * 所有音效在加载期合成为单声道采样，运行时按距离衰减/声像混合输出。
 */
import audio from '@ohos.multimedia.audio';
import { Vec3 } from './math3d';

const SR = 44100;

function mulberry32(a: number): () => number {
  let s = a | 0;
  return function (): number {
    s |= 0;
    s = (s + 0x6D2B79F5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** 低通白噪声脉冲 */
function noiseBurst(dur: number, attack: number, decay: number, lpStart: number, lpEnd: number, gain: number,
  seed: number): Float32Array {
  const n = Math.max(1, Math.floor(dur * SR));
  const out = new Float32Array(n);
  const rnd = mulberry32(seed);
  let lp = 0;
  for (let i = 0; i < n; i++) {
    const t = i / n;
    const alpha = lpStart + (lpEnd - lpStart) * t;
    lp += alpha * (rnd() * 2 - 1 - lp);
    let env = 1;
    if (t < attack) {
      env = t / attack;
    } else {
      const d = (t - attack) / (1 - attack);
      env = Math.exp(-decay * d);
    }
    out[i] = lp * env * gain;
  }
  return out;
}

/** 扫频音 */
function tone(f0: number, f1: number, dur: number, decay: number, gain: number, wave: number,
  seed: number = 1): Float32Array {
  const n = Math.max(1, Math.floor(dur * SR));
  const out = new Float32Array(n);
  let phase = 0;
  const rnd = mulberry32(seed);
  for (let i = 0; i < n; i++) {
    const t = i / n;
    const f = f0 + (f1 - f0) * t;
    phase += f / SR;
    if (phase > 1) {
      phase -= 1;
    }
    let v: number;
    if (wave === 0) {
      v = Math.sin(phase * Math.PI * 2);
    } else if (wave === 1) {
      v = phase * 2 - 1;
    } else {
      v = rnd() * 2 - 1;
    }
    out[i] = v * Math.exp(-decay * t) * gain;
  }
  return out;
}

/** 金属敲击（多个衰减正弦） */
function metalRing(freqs: number[], dur: number, decay: number, gain: number): Float32Array {
  const n = Math.max(1, Math.floor(dur * SR));
  const out = new Float32Array(n);
  const phases = new Float32Array(freqs.length);
  for (let i = 0; i < n; i++) {
    const t = i / n;
    let v = 0;
    for (let k = 0; k < freqs.length; k++) {
      phases[k] += freqs[k] / SR;
      if (phases[k] > 1) {
        phases[k] -= 1;
      }
      v += Math.sin(phases[k] * Math.PI * 2) * Math.exp(-decay * (1 + k * 0.7) * t) / freqs.length;
    }
    out[i] = v * gain;
  }
  return out;
}

function mixInto(dst: Float32Array, src: Float32Array, atSec: number, gain: number): void {
  const start = Math.floor(atSec * SR);
  for (let i = 0; i < src.length; i++) {
    const j = start + i;
    if (j >= 0 && j < dst.length) {
      dst[j] += src[i] * gain;
    }
  }
}

function concat(parts: Float32Array[]): Float32Array {
  let n = 0;
  for (const p of parts) {
    n = Math.max(n, p.length);
  }
  const out = new Float32Array(n);
  for (const p of parts) {
    for (let i = 0; i < p.length; i++) {
      out[i] += p[i];
    }
  }
  return out;
}

class Voice {
  prog: Float32Array;
  pos: number = 0;
  rate: number = 1;
  gl: number = 1;
  gr: number = 1;
  lp: number = 0;
  alpha: number = 1;

  constructor(prog: Float32Array, gl: number, gr: number, rate: number, alpha: number) {
    this.prog = prog;
    this.gl = gl;
    this.gr = gr;
    this.rate = rate;
    this.alpha = alpha;
  }
}

export class AudioSys {
  private renderer: audio.AudioRenderer | null = null;
  private ready: boolean = false;
  private master: number = 0.8;
  private sounds: Map<string, Float32Array> = new Map<string, Float32Array>();
  private voices: Voice[] = [];
  private ambientVoice: Voice | null = null;
  private lowHpOn: boolean = false;
  private lowHpPos: number = 0;
  private mixBuf: Float32Array = new Float32Array(882 * 2);
  private outBuf: Int16Array = new Int16Array(882 * 2);
  private timer: number = -1;
  private listenPos: Vec3 = new Vec3();
  private listenFwd: Vec3 = new Vec3(0, 0, -1);
  private listenRight: Vec3 = new Vec3(1, 0, 0);

  async init(): Promise<void> {
    if (this.ready) {
      return;
    }
    this.buildSounds();
    try {
      const streamInfo: audio.StreamInfo = {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_44100,
        channels: audio.AudioChannel.CHANNEL_2,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      };
      const rendererInfo: audio.RendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_GAME,
        rendererFlags: 0
      };
      this.renderer = await audio.createAudioRenderer({ streamInfo: streamInfo, rendererInfo: rendererInfo });
      await this.renderer.start();
      this.ready = true;
      this.timer = setInterval(() => {
        this.mixTick();
      }, 20);
    } catch (e) {
      this.ready = false;
    }
  }

  setVolume(v: number): void {
    this.master = v;
  }

  setListener(pos: Vec3, fwd: Vec3): void {
    this.listenPos.copy(pos);
    this.listenFwd.copy(fwd);
    this.listenRight.set(fwd.z, 0, -fwd.x).normalize();
  }

  private buildSounds(): void {
    const S = this.sounds;
    // 枪声：枪体低频 + 高频爆响 + 甩尾
    S.set('shot_ak47', concat([
      noiseBurst(0.22, 0.004, 7, 0.28, 0.06, 0.9, 101),
      tone(160, 55, 0.18, 18, 0.55, 0, 1),
      noiseBurst(0.05, 0.001, 10, 0.9, 0.6, 0.5, 102)
    ]));
    S.set('shot_m4a1', concat([
      noiseBurst(0.18, 0.004, 8, 0.32, 0.08, 0.8, 103),
      tone(190, 70, 0.14, 20, 0.45, 0, 1),
      noiseBurst(0.04, 0.001, 10, 0.9, 0.6, 0.45, 104)
    ]));
    S.set('shot_awm', concat([
      noiseBurst(0.5, 0.003, 6, 0.22, 0.03, 1.0, 105),
      tone(120, 38, 0.45, 12, 0.7, 0, 1),
      noiseBurst(0.07, 0.001, 8, 0.95, 0.5, 0.7, 106)
    ]));
    S.set('shot_mp5', concat([
      noiseBurst(0.13, 0.004, 9, 0.35, 0.12, 0.7, 107),
      tone(210, 90, 0.1, 22, 0.35, 0, 1)
    ]));
    S.set('shot_deagle', concat([
      noiseBurst(0.3, 0.003, 7, 0.25, 0.05, 0.95, 108),
      tone(140, 45, 0.25, 14, 0.6, 0, 1),
      noiseBurst(0.05, 0.001, 9, 0.92, 0.55, 0.6, 109)
    ]));
    S.set('shot_knife', noiseBurst(0.1, 0.005, 9, 0.5, 0.2, 0.4, 110));
    S.set('shot_grenade', noiseBurst(0.08, 0.01, 8, 0.4, 0.2, 0.4, 111));
    // 近战
    S.set('knife_light', concat([noiseBurst(0.12, 0.01, 8, 0.55, 0.2, 0.5, 112), tone(900, 300, 0.1, 15, 0.2, 0, 1)]));
    S.set('knife_heavy', concat([noiseBurst(0.2, 0.01, 7, 0.5, 0.15, 0.6, 113), tone(600, 150, 0.18, 12, 0.3, 0, 1)]));
    // 换弹机械
    S.set('magout', metalRing([420, 780, 1300], 0.12, 26, 0.5));
    S.set('magin', metalRing([300, 620, 980], 0.14, 22, 0.6));
    S.set('bolt', metalRing([520, 1100, 1750], 0.1, 34, 0.4));
    S.set('boltback', metalRing([380, 800], 0.09, 30, 0.35));
    S.set('boltforward', metalRing([460, 950, 1500], 0.12, 26, 0.5));
    S.set('dryfire', metalRing([900, 1800], 0.06, 50, 0.35));
    S.set('switch', concat([metalRing([350, 700], 0.09, 28, 0.4), noiseBurst(0.05, 0.005, 10, 0.6, 0.3, 0.25, 114)]));
    S.set('scope', tone(1400, 900, 0.07, 30, 0.18, 0, 1));
    S.set('shell', metalRing([2400, 3600, 5200], 0.14, 18, 0.22));
    // 脚步/起落
    S.set('foot_metal', noiseBurst(0.09, 0.012, 9, 0.45, 0.2, 0.32, 115));
    S.set('foot_wood', noiseBurst(0.1, 0.012, 8, 0.3, 0.12, 0.34, 116));
    S.set('foot_grate', metalRing([300, 610, 900], 0.1, 30, 0.22));
    S.set('land', concat([noiseBurst(0.16, 0.006, 8, 0.4, 0.1, 0.5, 117), tone(120, 60, 0.12, 18, 0.3, 0, 1)]));
    S.set('jump', noiseBurst(0.08, 0.01, 9, 0.35, 0.15, 0.22, 118));
    // 命中反馈
    S.set('impact_metal', metalRing([800, 1700, 2600], 0.12, 32, 0.45));
    S.set('impact_wood', noiseBurst(0.12, 0.005, 9, 0.4, 0.18, 0.45, 119));
    S.set('ricochet', concat([tone(2600, 700, 0.28, 12, 0.3, 0, 1), noiseBurst(0.05, 0.002, 10, 0.8, 0.4, 0.3, 120)]));
    S.set('whiz', noiseBurst(0.12, 0.15, 10, 0.85, 0.3, 0.4, 121));
    S.set('hit', tone(1200, 900, 0.06, 25, 0.3, 0, 1));
    S.set('hit_hs', concat([tone(1600, 1100, 0.07, 22, 0.32, 0, 1), metalRing([1900], 0.09, 20, 0.2)]));
    S.set('kill', concat([tone(600, 900, 0.09, 12, 0.3, 0, 1), tone(900, 1350, 0.12, 10, 0.25, 0, 1)]));
    S.set('hurt', concat([tone(180, 120, 0.16, 10, 0.4, 1, 1), noiseBurst(0.12, 0.02, 8, 0.4, 0.2, 0.3, 122)]));
    S.set('death', tone(160, 70, 0.5, 7, 0.45, 1, 1));
    // 手雷
    S.set('pin', metalRing([1500, 2300], 0.08, 30, 0.3));
    S.set('throw', noiseBurst(0.18, 0.1, 9, 0.5, 0.25, 0.35, 123));
    S.set('bounce', metalRing([500, 950], 0.08, 35, 0.35));
    S.set('explosion', concat([
      noiseBurst(1.4, 0.004, 5.5, 0.16, 0.02, 1.0, 124),
      tone(90, 28, 1.2, 6, 0.9, 0, 1),
      noiseBurst(0.15, 0.002, 8, 0.9, 0.3, 0.6, 125)
    ]));
    // UI
    S.set('ui_click', tone(900, 700, 0.05, 30, 0.25, 0, 1));
    S.set('ui_buy', concat([tone(700, 1050, 0.08, 15, 0.25, 0, 1), tone(1050, 1400, 0.1, 12, 0.2, 0, 1)]));
    S.set('ui_start', concat([tone(500, 500, 0.12, 8, 0.3, 0, 1), tone(750, 750, 0.14, 8, 0.3, 0, 1),
      tone(1000, 1000, 0.3, 6, 0.3, 0, 1)]));
    S.set('ui_end', concat([tone(600, 600, 0.25, 6, 0.3, 0, 1), tone(450, 450, 0.5, 5, 0.3, 0, 1)]));
    S.set('announce', tone(880, 660, 0.15, 10, 0.2, 0, 1));
    // 环境循环（4 秒：船体轰鸣 + 海浪）
    {
      const n = SR * 4;
      const amb = new Float32Array(n);
      const rnd = mulberry32(777);
      let lp1 = 0, lp2 = 0;
      for (let i = 0; i < n; i++) {
        const t = i / SR;
        lp1 += 0.02 * ((rnd() * 2 - 1) - lp1);          // 低频隆隆
        lp2 += 0.15 * ((rnd() * 2 - 1) - lp2);          // 中频沙沙
        const wave = Math.sin(t * 0.9) * 0.5 + 0.5;     // 海浪起伏
        amb[i] = lp1 * 1.6 + lp2 * 0.22 * (0.5 + wave * 0.5);
      }
      S.set('ambient', amb);
    }
    // 低血量心跳
    S.set('heartbeat', concat([tone(70, 50, 0.1, 10, 0.5, 0, 1), tone(65, 45, 0.1, 10, 0.35, 0, 1)]));
  }

  private play3D(name: string, pos: Vec3 | null, baseGain: number = 1, maxDist: number = 60,
    rate: number = 1): void {
    if (!this.ready) {
      return;
    }
    const prog = this.sounds.get(name);
    if (prog === undefined) {
      return;
    }
    let gain = baseGain;
    let pan = 0;
    let alpha = 1;
    if (pos !== null) {
      const dx = pos.x - this.listenPos.x, dy = pos.y - this.listenPos.y, dz = pos.z - this.listenPos.z;
      const d = Math.sqrt(dx * dx + dy * dy + dz * dz);
      if (d > maxDist) {
        return;
      }
      const dd = Math.max(1, d);
      gain *= Math.max(0, 1 - d / maxDist) * Math.min(1, 8 / dd);
      pan = Math.max(-0.8, Math.min(0.8, (dx * this.listenRight.x + dz * this.listenRight.z) / dd));
      alpha = Math.max(0.12, 1 - d / maxDist * 0.85);
    }
    if (gain <= 0.003) {
      return;
    }
    const gl = gain * (pan < 0 ? 1 + pan : 1);
    const gr = gain * (pan > 0 ? 1 - pan : 1);
    if (this.voices.length > 24) {
      this.voices.shift();
    }
    this.voices.push(new Voice(prog, gl, gr, rate, alpha));
  }

  private playUI2(name: string): void {
    this.play3D(name, null, 1, 60, 1);
  }

  // ---------- 对外接口（与原版 audio 系统对应） ----------
  playShot(weaponId: string, pos: Vec3 | null): void {
    this.play3D(`shot_${weaponId}`, pos, 1, 75);
  }

  playReload(weaponId: string, stage: string): void {
    this.play3D(stage, null, 0.8);
  }

  playDryFire(): void {
    this.play3D('dryfire', null, 0.8);
  }

  playFootstep(pos: Vec3 | null, surface: string): void {
    const name = surface === 'wood' ? 'foot_wood' : surface === 'grate' ? 'foot_grate' : 'foot_metal';
    this.play3D(name, pos, 0.9, 34, 0.92 + Math.random() * 0.16);
  }

  playLand(pos: Vec3 | null, surface: string, strength: number): void {
    void surface;
    this.play3D('land', pos, Math.min(1, 0.4 + strength * 0.4), 45);
  }

  playJump(pos: Vec3 | null): void {
    this.play3D('jump', pos, 0.8, 30);
  }

  playImpact(pos: Vec3, mat: string): void {
    this.play3D(mat === 'wood' ? 'impact_wood' : 'impact_metal', pos, 0.8, 42);
  }

  playRicochet(pos: Vec3): void {
    this.play3D('ricochet', pos, 0.7, 45);
  }

  playBulletWhiz(pos: Vec3): void {
    this.play3D('whiz', pos, 0.9, 10);
  }

  playHitmarker(hs: boolean): void {
    this.play3D(hs ? 'hit_hs' : 'hit', null, 0.9);
  }

  playKillConfirm(hs: boolean): void {
    this.play3D('kill', null, 0.9);
    if (hs) {
      this.play3D('hit_hs', null, 0.5);
    }
  }

  playHurt(amount: number): void {
    this.play3D('hurt', null, Math.min(1, 0.3 + amount / 80));
  }

  playDeath(pos: Vec3 | null): void {
    this.play3D('death', pos, 0.9, 50);
  }

  playKnife(kind: string, result: string, pos: Vec3 | null): void {
    if (result === 'flesh') {
      this.play3D(kind === 'heavy' ? 'knife_heavy' : 'knife_light', pos, 0.9, 45);
    } else if (result === 'wall') {
      this.play3D('impact_metal', pos, 0.5, 40);
    } else {
      this.play3D(kind === 'heavy' ? 'knife_heavy' : 'knife_light', pos, 0.4, 30);
    }
  }

  playGrenadePin(): void {
    this.play3D('pin', null, 0.8);
  }

  playGrenadeThrow(): void {
    this.play3D('throw', null, 0.8);
  }

  playGrenadeBounce(pos: Vec3): void {
    this.play3D('bounce', pos, 0.8, 40);
  }

  playExplosion(pos: Vec3): void {
    this.play3D('explosion', pos, 1.1, 95);
  }

  playWeaponSwitch(weaponId: string): void {
    void weaponId;
    this.play3D('switch', null, 0.7);
  }

  playScope(zoomIn: boolean): void {
    this.play3D('scope', null, zoomIn ? 0.7 : 0.5);
  }

  playShellDrop(pos: Vec3 | null): void {
    this.play3D('shell', pos, 0.6, 12, 0.9 + Math.random() * 0.2);
  }

  playUI(kind: string): void {
    if (kind === 'start') {
      this.playUI2('ui_start');
    } else if (kind === 'roundEnd') {
      this.playUI2('ui_end');
    } else if (kind === 'buy') {
      this.playUI2('ui_buy');
    } else {
      this.playUI2('ui_click');
    }
  }

  announce(text: string): void {
    // 语音播报以提示音代替
    void text;
    this.playUI2('announce');
  }

  startAmbient(): void {
    if (!this.ready) {
      return;
    }
    const prog = this.sounds.get('ambient');
    if (prog === undefined) {
      return;
    }
    this.ambientVoice = new Voice(prog, 0.16, 0.16, 1, 0.5);
    this.ambientVoice.pos = 0;
  }

  stopAmbient(): void {
    this.ambientVoice = null;
  }

  setLowHealth(on: boolean): void {
    this.lowHpOn = on;
    this.lowHpPos = 0;
  }

  release(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    if (this.renderer !== null) {
      try {
        this.renderer.stop();
        this.renderer.release();
      } catch (e) {
        // 忽略
      }
      this.renderer = null;
    }
    this.ready = false;
  }

  /** 混音输出（每 tick 20ms 数据，与定时器周期一致） */
  private mixTick(): void {
    if (!this.ready || this.renderer === null) {
      return;
    }
    const N = 882; // 44100 * 0.02
    const mix = this.mixBuf;
    mix.fill(0);
    const mv = this.master;
    // 环境音
    const amb = this.ambientVoice;
    if (amb !== null) {
      const p = amb.prog;
      for (let i = 0; i < N; i++) {
        const v = p[amb.pos | 0] * mv;
        mix[i * 2] += v;
        mix[i * 2 + 1] += v;
        amb.pos++;
        if (amb.pos >= p.length) {
          amb.pos = 0;
        }
      }
    }
    // 低血量心跳（约 1.1s 一次）
    if (this.lowHpOn) {
      const hb = this.sounds.get('heartbeat') as Float32Array;
      const period = Math.floor(SR * 1.1);
      for (let i = 0; i < N; i++) {
        const idx = this.lowHpPos % period;
        if (idx < hb.length) {
          const v = hb[idx] * 0.5 * mv;
          mix[i * 2] += v;
          mix[i * 2 + 1] += v;
        }
        this.lowHpPos++;
      }
    } else {
      this.lowHpPos = 0;
    }
    // 音效
    for (let vi = this.voices.length - 1; vi >= 0; vi--) {
      const v = this.voices[vi];
      const p = v.prog;
      const a = v.alpha;
      for (let i = 0; i < N; i++) {
        const pi = v.pos | 0;
        if (pi >= p.length) {
          break;
        }
        const frac = v.pos - pi;
        const s0 = p[pi];
        const s1 = pi + 1 < p.length ? p[pi + 1] : 0;
        v.lp += a * ((s0 + (s1 - s0) * frac) - v.lp);
        const v2 = v.lp * mv;
        mix[i * 2] += v2 * v.gl;
        mix[i * 2 + 1] += v2 * v.gr;
        v.pos += v.rate;
      }
      if ((v.pos | 0) >= p.length) {
        this.voices.splice(vi, 1);
      }
    }
    // 转 S16 写入
    const out = this.outBuf;
    for (let i = 0; i < N * 2; i++) {
      let s = mix[i];
      s = s > 1 ? 1 : s < -1 ? -1 : s;
      out[i] = (s * 32767) | 0;
    }
    const buffer = out.buffer;
    this.renderer.write(buffer).catch(() => {
    });
  }
}

export const audioSys: AudioSys = new AudioSys();
