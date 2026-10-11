// 对局逻辑：波次调度 / 捕鱼核销 / 计分 / 技能 / 终局与加时
import { RULES, SKILLS } from '../shared/protocol.mjs';

const rnd = Math.random;
const range = ([a, b]) => a + rnd() * (b - a);

export class Match {
  constructor(room, { duration, seed }) {
    this.room = room;
    this.duration = duration;         // 秒
    this.seed = seed;
    this.startedAt = Date.now();      // 对局真正开始（倒计时结束）
    this.endAt = this.startedAt + duration * 1000;
    this.overtime = false;
    this.ended = false;
    this.waves = new Map();           // waveId -> { fs, caught:Set, born }
    this.waveSeq = 0;
    this.nextWaveAt = this.startedAt + 1200;
    this.trickWave = new Map();       // pid -> 已计特技的 waveId
    this.pending = new Map();         // pid -> 待释放技能
    this.timers = [];
  }

  get elapsed() { return (Date.now() - this.startedAt) / 1000; }
  get remainMs() { return (this.overtime ? this.otEndAt : this.endAt) - Date.now(); }

  // 由房间主循环驱动（room tick 250ms）
  tick() {
    if (this.ended) return;
    const now = Date.now();
    if (!this.overtime && now >= this.endAt) {
      const [a, b] = this.room.playerIds;
      const sa = this.room.score[a] || 0, sb = this.room.score[b] || 0;
      if (sa === sb) {
        this.overtime = true;
        this.otEndAt = now + RULES.OT_SECONDS * 1000;
        this.room.broadcast({ type: 'ot', end: this.otEndAt });
        return;
      }
      this.finish();
      return;
    }
    if (this.overtime && now >= this.otEndAt) return this.finish();
    if (now >= this.nextWaveAt) {
      this.spawnWave();
      this.nextWaveAt = now + range(RULES.WAVE_INTERVAL) * 1000;
    }
    // 波次过期回收
    for (const [id, w] of this.waves) {
      if (now - w.born > RULES.WAVE_LIVE * 1000) this.waves.delete(id);
    }
  }

  spawnWave() {
    const id = ++this.waveSeq;
    const fs = [];
    for (let i = 0; i < RULES.WAVE_FISH; i++) {
      fs.push({
        i,
        z: +(-2.1 + rnd() * 4.2).toFixed(2),          // 横向位置（连续车道）
        dl: +(rnd() * 1.6).toFixed(2),                // 出场延迟
        go: rnd() < RULES.GOLDEN_P,                   // 金鱼
      });
    }
    this.waves.set(id, { fs, caught: new Set(), born: Date.now() });
    this.room.broadcast({ type: 'wave', id, fs });
  }

  waveScore(pid, w, f) {
    // 返回 {ok, val}；核销失败返回 {ok:false}
    const wave = this.waves.get(w);
    if (!wave || Date.now() - wave.born > RULES.WAVE_LIVE * 1000) return { ok: false };
    if (wave.caught.has(f)) return { ok: false };
    const fish = wave.fs.find((x) => x.i === f);
    if (!fish) return { ok: false };
    wave.caught.add(f);
    const val = fish.go ? RULES.GOLDEN_VAL : RULES.FISH_VAL;
    this.room.addScore(pid, val);
    this.room.addFish(pid, fish.go);
    if (fish.go) {
      // 加时赛：金鱼一锤定音
      if (this.overtime) { this.finish(pid); return { ok: true, val, sudden: true }; }
      const pool = Object.values(SKILLS);
      const k = pool[Math.floor(rnd() * pool.length)];
      this.pending.set(pid, k);
      this.room.send(pid, { type: 'skillGot', k });
    }
    return { ok: true, val };
  }

  trick(pid) {
    const cur = this.waveSeq; // 当前最新波次
    if (this.trickWave.get(pid) === cur) return false;
    this.trickWave.set(pid, cur);
    this.room.addScore(pid, RULES.TRICK_VAL);
    return true;
  }

  useSkill(pid) {
    const k = this.pending.get(pid);
    if (!k) return null;
    this.pending.delete(pid);
    const opp = this.room.opponentOf(pid);
    const until = k === SKILLS.SEAGULL ? 0 : Date.now() + (k === SKILLS.FOG ? 2.5 : 3) * 1000;
    if (k === SKILLS.SEAGULL && opp != null) {
      const s = Math.max(0, (this.room.score[opp] || 0) - 2);
      this.room.score[opp] = s;
    }
    this.room.pushScore();
    return { k, tgt: k === SKILLS.BOOST ? pid : opp, until };
  }

  // 终局结算：winPid 为 null 时按分/里程判定
  finish(winPid = null) {
    if (this.ended) return;
    this.ended = true;
    for (const t of this.timers) clearTimeout(t);
    const ids = this.room.playerIds;
    const stats = {};
    for (const pid of ids) {
      const st = this.room.stats[pid] || { fish: 0, gold: 0, maxV: 0, d: 0 };
      stats[pid] = { ...st, bonus: 0 };
    }
    // 里程加成
    const [a, b] = ids;
    const da = stats[a]?.d || 0, db = stats[b]?.d || 0;
    if (da !== db) {
      const lead = da > db ? a : b;
      stats[lead].bonus = RULES.DIST_BONUS;
      this.room.score[lead] = (this.room.score[lead] || 0) + RULES.DIST_BONUS;
    }
    let win = 0;
    if (winPid != null) win = winPid;
    else {
      const sa = this.room.score[a] || 0, sb = this.room.score[b] || 0;
      win = sa > sb ? a : sb > sa ? b : da !== db ? (da > db ? a : b) : 0;
    }
    this.room.onMatchEnd(win, stats);
  }
}
