// 程序化音频：全部音效与 BGM 由 PCM 实时合成（WebAudio 合成器的 ArkTS 移植）
// 输出：AudioRenderer（单声道 S16LE，回调写入模式）
import audio from '@ohos.multimedia.audio';

const NOTE = (n: number): number => 440 * Math.pow(2, (n - 69) / 12);

export class Song {
  name: string = '';
  bpm: number = 128;
  root: number = 57;
  prog: number[][] = [];
  lead: number[] = [];
  bassPat: number[] = [];
  style: number = 0;
}

function mkSong(name: string, bpm: number, root: number, prog: number[][], lead: number[],
  bassPat: number[], style: number): Song {
  const s = new Song();
  s.name = name;
  s.bpm = bpm;
  s.root = root;
  s.prog = prog;
  s.lead = lead;
  s.bassPat = bassPat;
  s.style = style;
  return s;
}

export const SONGS: Song[] = [
  mkSong('极速都市', 128, 57, [[0, 3, 7], [-4, 0, 3], [3, 7, 10], [-2, 2, 5]],
    [0, 7, 12, 7, 10, 7, 3, 7], [1, 0, 1, 1, 0, 1, 1, 0], 0),
  mkSong('爱琴海之风', 118, 62, [[0, 4, 7], [-3, 0, 4], [5, 9, 12], [7, 11, 14]],
    [12, 11, 7, 4, 7, 11, 12, 14], [1, 0, 0, 1, 1, 0, 1, 0], 1),
  mkSong('法老的试炼', 132, 55, [[0, 3, 7], [1, 5, 8], [0, 3, 7], [-2, 1, 5]],
    [0, 1, 4, 5, 7, 8, 7, 4], [1, 1, 0, 1, 1, 0, 1, 1], 2),
  mkSong('冰雪狂飙', 140, 60, [[0, 4, 7], [7, 11, 14], [9, 12, 16], [5, 9, 12]],
    [7, 12, 16, 12, 14, 12, 11, 7], [1, 0, 1, 0, 1, 1, 1, 0], 3),
];

// 一次性发声（含简单双二阶滤波器）
class Voice {
  active: boolean = false;
  isNoise: boolean = false;
  osc: number = 0; // 0 sine 1 square 2 saw 3 triangle
  f0: number = 440;
  f1: number = 440;
  ph: number = 0;
  t: number = 0;
  dur: number = 0.2;
  vol: number = 0.2;
  attack: number = 0.01;
  startSample: number = 0;
  musicBus: boolean = false;
  env: number = 0.001;   // 当前包络（乘法衰减）
  envMul: number = 0.999; // 每样本衰减系数
  // biquad
  useBq: boolean = false;
  bqType: number = 0; // 0 lowpass 1 bandpass 2 highpass
  bqF: number = 1000;
  bqQ: number = 1;
  b0 = 0; b1 = 0; b2 = 0; a1 = 0; a2 = 0;
  x1 = 0; x2 = 0; y1 = 0; y2 = 0;
}

function setBiquad(v: Voice, sampleRate: number): void {
  const w0 = 2 * Math.PI * Math.min(v.bqF, sampleRate * 0.45) / sampleRate;
  const alpha = Math.sin(w0) / (2 * Math.max(0.1, v.bqQ));
  const cw = Math.cos(w0);
  let a0 = 1;
  let b0 = 0;
  let b1 = 0;
  let b2 = 0;
  let a1 = 0;
  let a2 = 0;
  if (v.bqType === 0) {
    // lowpass
    b0 = (1 - cw) / 2;
    b1 = 1 - cw;
    b2 = b0;
    a0 = 1 + alpha;
    a1 = -2 * cw;
    a2 = 1 - alpha;
  } else if (v.bqType === 1) {
    // bandpass (constant skirt)
    b0 = alpha;
    b1 = 0;
    b2 = -alpha;
    a0 = 1 + alpha;
    a1 = -2 * cw;
    a2 = 1 - alpha;
  } else {
    // highpass
    b0 = (1 + cw) / 2;
    b1 = -(1 + cw);
    b2 = b0;
    a0 = 1 + alpha;
    a1 = -2 * cw;
    a2 = 1 - alpha;
  }
  v.b0 = b0 / a0;
  v.b1 = b1 / a0;
  v.b2 = b2 / a0;
  v.a1 = a1 / a0;
  v.a2 = a2 / a0;
}

export class AudioSys {
  private renderer: audio.AudioRenderer | null = null;
  private ready: boolean = false;
  private failed: boolean = false;
  sampleRate: number = 24000;
  private samplePos: number = 0;
  // 正弦查表（省每样本 Math.sin）
  private static SIN_N: number = 2048;
  private sinLut: Float32Array = new Float32Array(AudioSys.SIN_N);
  // 混音
  private voices: Voice[] = [];
  private maxVoices: number = 48;
  private mixBuf: Float32Array = new Float32Array(4096);
  // 引擎连续声
  private engOn: boolean = false;
  private engGain: number = 0;
  private engTarget: number = 0;
  private engBase: number = 55;
  private engBaseT: number = 55;
  private engCut: number = 900;
  private engCutT: number = 900;
  private engPh1: number = 0;
  private engPh2: number = 0;
  private engLp: number = 0;
  // 胎噪
  private skidGain: number = 0;
  private skidTarget: number = 0;
  private skidBq: Voice = new Voice();
  private skidN: number = 0;
  // 风噪
  private windGain: number = 0;
  private windTarget: number = 0;
  private windBq: Voice = new Voice();
  private windN: number = 0;
  // 设置
  musicOn: boolean = true;
  sfxOn: boolean = true;
  playing: boolean = false;
  song: number = 0;
  private step: number = 0;
  private nextNoteSample: number = 0;
  musicVolume: number = 0.30;
  sfxVolume: number = 0.9;

  async init(): Promise<void> {
    if (this.ready || this.failed) return;
    try {
      const opts: audio.AudioRendererOptions = {
        streamInfo: {
          samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_24000,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          channels: audio.AudioChannel.CHANNEL_1,
        },
        rendererInfo: {
          content: audio.ContentType.CONTENT_TYPE_MOVIE,
          usage: audio.StreamUsage.STREAM_USAGE_GAME,
          rendererFlags: 0,
        },
      };
      const r = await audio.createAudioRenderer(opts);
      this.renderer = r;
      r.on('writeData', (arrayBuffer: ArrayBuffer) => {
        this.renderBuffer(arrayBuffer);
      });
      await r.start();
      this.skidBq.bqType = 1;
      this.skidBq.bqF = 2300;
      this.skidBq.bqQ = 3;
      setBiquad(this.skidBq, this.sampleRate);
      this.windBq.bqType = 1;
      this.windBq.bqF = 700;
      this.windBq.bqQ = 0.7;
      setBiquad(this.windBq, this.sampleRate);
      for (let i = 0; i < AudioSys.SIN_N; i++) {
        this.sinLut[i] = Math.sin((i / AudioSys.SIN_N) * Math.PI * 2);
      }
      this.nextNoteSample = this.samplePos + Math.floor(this.sampleRate * 0.1);
      this.ready = true;
    } catch (e) {
      this.failed = true;
    }
  }

  get ok(): boolean {
    return this.ready;
  }

  songs(): Song[] {
    return SONGS;
  }

  // ---------- PCM 合成 ----------
  private renderBuffer(buf: ArrayBuffer): void {
    const n = buf.byteLength / 2;
    const out = new Int16Array(buf);
    const sr = this.sampleRate;
    if (this.mixBuf.length < n) {
      this.mixBuf = new Float32Array(n * 2);
    }
    const tmp = this.mixBuf;
    for (let i = 0; i < n; i++) {
      this.samplePos++;
      tmp[i] = this.nextSample(sr);
    }
    this.schedule();
    for (let i = 0; i < n; i++) {
      let v = tmp[i];
      if (v > 1) v = 1;
      if (v < -1) v = -1;
      out[i] = Math.round(v * 32767);
    }
  }

  private nextSample(sr: number): number {
    let mix = 0;
    // 一次性 voice（包络用乘法衰减，振荡用查表，热路径无 pow/sin 调用）
    for (let k = 0; k < this.voices.length; k++) {
      const v = this.voices[k];
      if (!v.active) continue;
      const age = (this.samplePos - v.startSample) / sr;
      if (age < 0) continue;
      if (age > v.dur) {
        v.active = false;
        continue;
      }
      let s: number;
      if (v.isNoise) {
        s = Math.random() * 2 - 1;
      } else {
        const fT = age / v.dur;
        const f = v.f0 * Math.pow(v.f1 / v.f0, Math.min(1, fT));
        v.ph += f / sr;
        if (v.ph > 1) v.ph -= Math.floor(v.ph);
        const p = v.ph;
        if (v.osc === 0) {
          // 正弦查表（线性插值）
          const idx = p * AudioSys.SIN_N;
          const i0 = idx | 0;
          const fr = idx - i0;
          const a = this.sinLut[i0 & (AudioSys.SIN_N - 1)];
          const b = this.sinLut[(i0 + 1) & (AudioSys.SIN_N - 1)];
          s = a + (b - a) * fr;
        }
        else if (v.osc === 1) s = p < 0.5 ? 1 : -1;
        else if (v.osc === 2) s = 2 * p - 1;
        else s = p < 0.25 ? 4 * p : p < 0.75 ? 2 - 4 * p : 4 * p - 4;
      }
      if (v.useBq) {
        const x = s;
        const y = v.b0 * x + v.b1 * v.x1 + v.b2 * v.x2 - v.a1 * v.y1 - v.a2 * v.y2;
        v.x2 = v.x1;
        v.x1 = x;
        v.y2 = v.y1;
        v.y1 = y;
        s = y;
      }
      // 包络：起音线性，之后乘法衰减（等价指数，免 pow）
      if (age < v.attack) {
        v.env = age / v.attack * 0.9999 + 0.0001;
      } else {
        v.env *= v.envMul;
      }
      mix += s * v.vol * v.env * (v.musicBus ? (this.musicOn ? this.musicVolume : 0) : this.sfxVolume);
    }
    // 引擎
    if (this.engOn || Math.abs(this.engGain) > 1e-4) {
      this.engGain += (this.engTarget - this.engGain) * 0.0015;
      this.engBase += (this.engBaseT - this.engBase) * 0.002;
      this.engCut += (this.engCutT - this.engCut) * 0.003;
      this.engPh1 += this.engBase / sr;
      if (this.engPh1 > 1) this.engPh1 -= Math.floor(this.engPh1);
      this.engPh2 += this.engBase * 0.5 / sr;
      if (this.engPh2 > 1) this.engPh2 -= Math.floor(this.engPh2);
      const saw = 2 * this.engPh1 - 1;
      const sq = this.engPh2 < 0.5 ? 1 : -1;
      const raw = saw + sq * 0.35;
      const a = this.engCut / sr;
      this.engLp += a * (raw - this.engLp);
      mix += this.engLp * this.engGain;
    }
    // 胎噪
    if (Math.abs(this.skidGain) > 1e-4 || this.skidTarget > 0) {
      this.skidGain += (this.skidTarget - this.skidGain) * 0.002;
      const x = Math.random() * 2 - 1;
      const v = this.skidBq;
      const y = v.b0 * x + v.b1 * v.x1 + v.b2 * v.x2 - v.a1 * v.y1 - v.a2 * v.y2;
      v.x2 = v.x1;
      v.x1 = x;
      v.y2 = v.y1;
      v.y1 = y;
      mix += y * this.skidGain;
    }
    // 风噪
    if (Math.abs(this.windGain) > 1e-4 || this.windTarget > 0) {
      this.windGain += (this.windTarget - this.windGain) * 0.001;
      const x = Math.random() * 2 - 1;
      const v = this.windBq;
      const y = v.b0 * x + v.b1 * v.x1 + v.b2 * v.x2 - v.a1 * v.y1 - v.a2 * v.y2;
      v.x2 = v.x1;
      v.x1 = x;
      v.y2 = v.y1;
      v.y1 = y;
      mix += y * this.windGain;
    }
    return mix;
  }

  private spawn(): Voice | null {
    for (const v of this.voices) {
      if (!v.active) return v;
    }
    if (this.voices.length < this.maxVoices) {
      const v = new Voice();
      this.voices.push(v);
      return v;
    }
    return null;
  }

  private tone(freq: number, dur: number, osc: number, vol: number, slide: number, delay: number, musicBus: boolean,
    cutoff: number, pad: boolean): void {
    if (!this.ready) return;
    if (!musicBus && !this.sfxOn) return;
    const v = this.spawn();
    if (!v) return;
    v.active = true;
    v.isNoise = false;
    v.osc = osc;
    v.f0 = Math.max(20, freq);
    v.f1 = Math.max(20, freq * (slide !== 0 ? slide : 1));
    v.dur = Math.max(0.03, dur);
    v.vol = vol;
    v.attack = pad ? 0.2 : 0.01;
    v.startSample = this.samplePos + Math.floor(delay * this.sampleRate);
    v.musicBus = musicBus;
    v.env = 0.001;
    v.envMul = Math.exp(-9.2103 / Math.max(0.005, v.dur - v.attack) / this.sampleRate);
    if (cutoff > 0) {
      v.useBq = true;
      v.bqType = 0;
      v.bqF = cutoff;
      v.bqQ = 0.8;
      setBiquad(v, this.sampleRate);
    } else v.useBq = false;
  }

  private noiseBurst(dur: number, freq: number, q: number, vol: number, type: number, sweep: number, delay: number,
    musicBus: boolean): void {
    if (!this.ready) return;
    if (!musicBus && !this.sfxOn) return;
    const v = this.spawn();
    if (!v) return;
    v.active = true;
    v.isNoise = true;
    v.dur = Math.max(0.02, dur);
    v.vol = vol;
    v.attack = 0.005;
    v.startSample = this.samplePos + Math.floor(delay * this.sampleRate);
    v.musicBus = musicBus;
    v.env = 0.001;
    v.envMul = Math.exp(-9.2103 / Math.max(0.005, v.dur - v.attack) / this.sampleRate);
    v.useBq = true;
    v.bqType = type;
    // 扫频用起止几何中点近似（重算 biquad 系数代价高）
    const fEnd = freq * (sweep !== 0 ? sweep : 1);
    v.bqF = Math.sqrt(Math.max(30, freq * Math.max(30, fEnd)));
    v.bqQ = q;
    setBiquad(v, this.sampleRate);
  }

  // ---------- 引擎参数 ----------
  setEngine(speedRatio: number, throttle: number, boosting: boolean, drifting: boolean, active: boolean): void {
    if (!this.ready) return;
    const gears = 6;
    const g = Math.min(gears - 1, Math.floor(speedRatio * gears * 0.999));
    const inGear = speedRatio * gears - g;
    const rpm = 0.3 + inGear * 0.7 * (0.75 + g * 0.05);
    this.engOn = active;
    this.engBaseT = 55 + rpm * 130 + (boosting ? 35 : 0);
    this.engCutT = 500 + rpm * 1600 + (throttle > 0 ? 500 : 0);
    this.engTarget = active ? 0.085 + (throttle > 0 ? 0.05 : 0) : 0;
    this.skidTarget = drifting && active ? 0.13 : 0;
    this.windTarget = active ? speedRatio * 0.05 + (boosting ? 0.18 : 0) : 0;
  }

  silence(): void {
    this.setEngine(0, 0, false, false, false);
  }

  // ---------- 音效 ----------
  play(name: string, arg: number): void {
    if (!this.ready) return;
    switch (name) {
      case 'count':
        this.tone(660, 0.25, 1, 0.18, 0, 0, false, 0, false);
        break;
      case 'go':
        this.tone(1320, 0.6, 1, 0.2, 0, 0, false, 0, false);
        this.tone(990, 0.6, 1, 0.1, 0, 0, false, 0, false);
        break;
      case 'nitro':
        this.noiseBurst(0.9, 300, 0.8, 0.9, 0, 8, 0, false);
        this.tone(90, 0.5, 2, 0.25, 2.5, 0, false, 0, false);
        break;
      case 'small':
        this.noiseBurst(0.35, 900, 1, 0.6, 1, 3, 0, false);
        this.tone(420, 0.18, 3, 0.18, 2, 0, false, 0, false);
        break;
      case 'double':
        this.tone(880, 0.12, 1, 0.12, 0, 0, false, 0, false);
        this.tone(1320, 0.2, 1, 0.12, 1, 0.08, false, 0, false);
        break;
      case 'gauge':
        this.tone(1047, 0.18, 3, 0.2, 1, 0, false, 0, false);
        this.tone(1319, 0.18, 3, 0.2, 1, 0.06, false, 0, false);
        this.tone(1568, 0.18, 3, 0.2, 1, 0.12, false, 0, false);
        break;
      case 'crash':
        this.noiseBurst(0.35, 400, 0.8, Math.min(1, 0.3 + arg * 0.03), 0, 0.3, 0, false);
        this.tone(70, 0.25, 0, 0.4, 0.5, 0, false, 0, false);
        break;
      case 'scrape':
        this.noiseBurst(0.12, 3000, 2, 0.12, 1, 0, 0, false);
        break;
      case 'lap':
        this.tone(784, 0.22, 1, 0.12, 1, 0, false, 0, false);
        this.tone(988, 0.22, 1, 0.12, 1, 0.1, false, 0, false);
        this.tone(1175, 0.22, 1, 0.12, 1, 0.2, false, 0, false);
        break;
      case 'finish':
        for (let i = 0; i < 6; i++) {
          const f = [523, 659, 784, 1047, 784, 1047][i];
          this.tone(f, 0.3, 1, 0.13, 1, i * 0.13, false, 0, false);
        }
        break;
      case 'pad':
        this.noiseBurst(0.4, 1500, 1, 0.5, 1, 3, 0, false);
        this.tone(600, 0.25, 2, 0.1, 2, 0, false, 0, false);
        break;
      case 'land':
        this.tone(80, 0.2, 0, 0.4, 0.6, 0, false, 0, false);
        this.noiseBurst(0.15, 300, 1, 0.3, 0, 0, 0, false);
        break;
      case 'item':
        this.tone(880, 0.08, 1, 0.12, 0, 0, false, 0, false);
        this.tone(1175, 0.12, 1, 0.12, 1, 0.07, false, 0, false);
        break;
      case 'missile':
        this.noiseBurst(1.0, 500, 1, 0.5, 1, 4, 0, false);
        break;
      case 'boom':
        this.noiseBurst(0.8, 200, 0.7, 1, 0, 0.2, 0, false);
        this.tone(55, 0.6, 0, 0.5, 0.4, 0, false, 0, false);
        break;
      case 'banana':
        this.tone(300, 0.3, 3, 0.25, 0.4, 0, false, 0, false);
        break;
      case 'shield':
        this.tone(660, 0.25, 0, 0.15, 1, 0, false, 0, false);
        this.tone(880, 0.25, 0, 0.15, 1, 0.05, false, 0, false);
        this.tone(1100, 0.25, 0, 0.15, 1, 0.1, false, 0, false);
        break;
      case 'click':
        this.tone(1200, 0.05, 1, 0.08, 0, 0, false, 0, false);
        break;
      case 'wrong':
        this.tone(220, 0.3, 1, 0.1, 0, 0, false, 0, false);
        break;
      default:
        break;
    }
  }

  // ---------- BGM 音序器 ----------
  setSong(i: number): string {
    this.song = ((i % SONGS.length) + SONGS.length) % SONGS.length;
    this.step = 0;
    this.nextNoteSample = this.samplePos + Math.floor(this.sampleRate * 0.1);
    return SONGS[this.song].name;
  }

  startMusic(): void {
    if (!this.ready) return;
    this.playing = true;
    this.nextNoteSample = this.samplePos + Math.floor(this.sampleRate * 0.1);
  }

  toggleMusic(): boolean {
    this.musicOn = !this.musicOn;
    return this.musicOn;
  }

  private schedule(): void {
    if (!this.playing || !this.musicOn) return;
    const song = SONGS[this.song];
    const spb = 60 / song.bpm / 4; // 16 分音符（秒）
    const lookahead = this.samplePos + Math.floor(this.sampleRate * 0.15);
    let guard = 0;
    while (this.nextNoteSample < lookahead && guard++ < 64) {
      this.playStep(song, this.step, this.nextNoteSample, spb);
      this.nextNoteSample += Math.floor(spb * this.sampleRate);
      this.step++;
    }
  }

  private playStep(song: Song, step: number, startSample: number, spb: number): void {
    const delay = (startSample - this.samplePos) / this.sampleRate;
    const bar = Math.floor(step / 16) % 4;
    const s16 = step % 16;
    const chord = song.prog[bar];
    const root = song.root;
    // 底鼓：sine 150→40
    if (s16 % 4 === 0) {
      const v = this.spawn();
      if (v) {
        v.active = true;
        v.isNoise = false;
        v.osc = 0;
        v.f0 = 150;
        v.f1 = 40;
        v.dur = 0.18;
        v.vol = 0.9;
        v.attack = 0.002;
        v.startSample = startSample;
        v.musicBus = true;
        v.useBq = false;
      }
    }
    // 军鼓 / 拍手
    if (s16 === 4 || s16 === 12) {
      this.noiseBurst(0.12, 1800, 1, 0.35, 1, 0, delay, true);
    }
    // 踩镲
    if (s16 % 2 === 1 || song.style === 3) {
      this.noiseBurst(0.03, 8000, 1, s16 % 4 === 2 ? 0.18 : 0.1, 2, 0, delay, true);
    }
    // 贝斯
    const bi = Math.floor(s16 / 2);
    if (s16 % 2 === 0 && song.bassPat[bi % 8] === 1) {
      const n = root - 24 + chord[0] + (bi % 4 === 3 ? 12 : 0);
      this.tone(NOTE(n), spb * 1.8, 2, 0.22, 0, delay, true, 600, false);
    }
    // 和弦垫（每小节）
    if (s16 === 0) {
      for (const c of chord) {
        this.tone(NOTE(root + c), spb * 15, song.style === 1 ? 3 : 2, 0.045, 0, delay, true, 1400, true);
      }
    }
    // 琶音主旋律
    if (s16 % 2 === 0) {
      const li = (s16 / 2 + bar * 2) % song.lead.length;
      const n = root + 12 + chord[0] + song.lead[li];
      this.tone(NOTE(n), spb * 1.6, song.style === 2 ? 3 : 1, 0.06, 0, delay, true, 3000, false);
    }
  }

  release(): void {
    if (this.renderer) {
      try {
        this.renderer.stop();
        this.renderer.release();
      } catch (e) {
        // 忽略
      }
      this.renderer = null;
      this.ready = false;
    }
  }
}
