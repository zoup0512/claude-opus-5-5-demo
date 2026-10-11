// 房间：成员 / 生命周期 / 消息校验与转发
import { Match } from './match.mjs';
import { RULES } from '../shared/protocol.mjs';

const CODE_AB = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const newCode = () => Array.from({ length: 4 }, () => CODE_AB[Math.floor(Math.random() * CODE_AB.length)]).join('');
const newToken = () => Math.random().toString(36).slice(2, 12);

let nextPid = 1;

export class Room {
  constructor(manager, code) {
    this.manager = manager;
    this.code = code;
    this.players = new Map();   // pid -> {ws, name, ready, connected, resume, goneTimer, violations}
    this.state = 'waiting';     // waiting | countdown | playing | ended
    this.duration = 180;
    this.host = null;
    this.match = null;
    this.score = {};
    this.stats = {};
    this.countdownEnd = 0;
    this.countdownTimer = null;
    this.idleSince = Date.now();
  }

  get playerIds() { return [...this.players.keys()]; }
  get full() { return this.players.size >= 2; }
  opponentOf(pid) { return this.playerIds.find((id) => id !== pid) ?? null; }

  join(ws, name, resume) {
    if (this.full) {
      // 满员时只有持有效 resume 令牌的掉线者能回座
      for (const [pid, p] of this.players) {
        if (!p.connected && resume && p.resume === resume) return this.reattach(pid, ws);
      }
      return null;
    }
    const pid = nextPid++;
    this.players.set(pid, { ws, name, ready: false, connected: true, resume: newToken(), violations: 0 });
    this.score[pid] = 0;
    this.stats[pid] = { fish: 0, gold: 0, maxV: 0, d: 0 };
    if (this.host == null) this.host = pid;
    return pid;
  }

  reattach(pid, ws) {
    const p = this.players.get(pid);
    clearTimeout(p.goneTimer);
    p.ws = ws;
    p.connected = true;
    this.broadcast({ type: 'oppBack' }, pid);
    this.roomState(pid);
    // 对局中补发当前信息
    if (this.match && !this.match.ended) {
      const m = this.match;
      this.send(pid, { type: 'match', seed: m.seed, hour: 17.5, dur: m.duration });
      this.send(pid, { type: 'countdown', end: m.startedAt });
      if (m.overtime) this.send(pid, { type: 'ot', end: m.otEndAt });
      this.pushScore();
    }
    return pid;
  }

  leave(pid, silent = false) {
    const p = this.players.get(pid);
    if (!p) return;
    const inMatch = this.state === 'playing' && this.match && !this.match.ended;
    if (inMatch && p.connected) {
      // 主动离开 = 认输
      const opp = this.opponentOf(pid);
      this.players.delete(pid);
      if (opp != null) this.match.finish(opp);
    } else {
      this.players.delete(pid);
      // 倒计时阶段缺人：取消开局回到等待
      if (this.state === 'countdown' && this.players.size < 2) {
        clearTimeout(this.countdownTimer);
        this.state = 'waiting';
        for (const q of this.players.values()) q.ready = false;
      }
    }
    if (this.host === pid || !this.players.has(this.host)) this.host = this.playerIds[0] ?? null;
    if (this.players.size === 0) this.manager.drop(this.code);
    else this.broadcast(this.roomMsg());
  }

  onDisconnect(pid) {
    const p = this.players.get(pid);
    if (!p) return;
    p.connected = false;
    this.broadcast({ type: 'oppGone' }, pid);
    const inMatch = this.state === 'playing' && this.match && !this.match.ended;
    if (inMatch) {
      const opp = this.opponentOf(pid);
      p.goneTimer = setTimeout(() => {
        if (!p.connected && this.players.has(pid)) {
          this.players.delete(pid);
          if (opp != null && this.players.has(opp)) this.match.finish(opp);
        }
      }, RULES.RECONNECT_MS);
    } else {
      p.goneTimer = setTimeout(() => {
        if (!p.connected && this.players.has(pid)) this.leave(pid, true);
      }, RULES.RECONNECT_MS);
    }
  }

  send(pid, msg) {
    const p = this.players.get(pid);
    if (!p || !p.connected) return;
    try { p.ws.send(JSON.stringify(msg)); } catch { /* 忽略：断线由 close 事件处理 */ }
  }
  broadcast(msg, except = null) {
    for (const pid of this.players.keys()) if (pid !== except) this.send(pid, msg);
  }
  roomMsg() {
    return {
      type: 'room',
      code: this.code,
      state: this.state,
      duration: this.duration,
      host: this.host,
      players: this.playerIds.map((id) => {
        const p = this.players.get(id);
        return { id, name: p.name, ready: p.ready, connected: p.connected };
      }),
    };
  }
  roomState(pid) { this.send(pid, { ...this.roomMsg(), resume: this.players.get(pid)?.resume }); }

  pushScore() {
    const sc = {}, fish = {}, gold = {};
    for (const pid of this.players.keys()) {
      sc[pid] = this.score[pid] || 0;
      fish[pid] = this.stats[pid]?.fish || 0;
      gold[pid] = this.stats[pid]?.gold || 0;
    }
    this.broadcast({ type: 'score', sc, fish, gold });
  }
  addScore(pid, v) { this.score[pid] = (this.score[pid] || 0) + v; this.pushScore(); }
  addFish(pid, golden) {
    const st = this.stats[pid] || (this.stats[pid] = { fish: 0, gold: 0, maxV: 0, d: 0 });
    st.fish++;
    if (golden) st.gold++;
  }

  setReady(pid, on) {
    const p = this.players.get(pid);
    if (p) p.ready = !!on;
    this.broadcast(this.roomMsg());
  }

  startCountdown() {
    if (this.state !== 'waiting' || !this.full) return false;
    let allReady = true;
    for (const p of this.players.values()) if (!p.ready) allReady = false;
    if (!allReady) return false;
    this.state = 'countdown';
    this.countdownEnd = Date.now() + 3200;
    this.broadcast({ type: 'countdown', end: this.countdownEnd });
    this.broadcast(this.roomMsg());
    this.countdownTimer = setTimeout(() => this.beginMatch(), 3200);
    return true;
  }

  beginMatch() {
    if (!this.full || this.state !== 'countdown') return;
    this.state = 'playing';
    this.score = {};
    this.stats = {};
    for (const pid of this.playerIds) {
      this.score[pid] = 0;
      this.stats[pid] = { fish: 0, gold: 0, maxV: 0, d: 0 };
      const p = this.players.get(pid);
      p.ready = false;
      p.resume = newToken();
    }
    const seed = Math.floor(Math.random() * 1e9);
    this.match = new Match(this, { duration: this.duration, seed });
    this.broadcast({ type: 'match', seed, hour: 17.5, dur: this.duration });
    this.broadcast(this.roomMsg());
    for (const pid of this.playerIds) this.roomState(pid); // 下发新 resume 令牌
    this.pushScore();
  }

  onMatchEnd(win, stats) {
    this.state = 'ended';
    this.idleSince = Date.now();
    this.broadcast({ type: 'end', win, sc: this.score, stats });
    this.broadcast(this.roomMsg());
  }

  again(pid) {
    if (this.state !== 'ended') return;
    const p = this.players.get(pid);
    if (!p) return;
    p.ready = true;
    this.broadcast(this.roomMsg());
    if (this.full && [...this.players.values()].every((x) => x.ready)) {
      this.state = 'waiting';
      this.startCountdown();
    }
  }

  tick() {
    if (this.match && this.state === 'playing') this.match.tick();
  }

  // ---------- 客户端消息处理 ----------
  onMessage(pid, raw) {
    let msg;
    try { msg = JSON.parse(raw); } catch { return; }
    if (typeof msg?.type !== 'string' || msg.type.length > 16) return;
    const p = this.players.get(pid);
    if (!p) return;

    switch (msg.type) {
      case 'ready': this.setReady(pid, msg.on !== false); break;
      case 'start': if (pid === this.host) this.startCountdown(); break;
      case 'state': {
        if (this.state !== 'playing' || !this.match || this.match.ended) break;
        const s = msg;
        const v = +s.v || 0, d = +s.d || 0, l = +s.l || 0;
        // 作弊钳制：速度/横向越界
        if (v > RULES.MAX_SPEED * RULES.SPEED_TOL || Math.abs(l) > 3.2 || d < -1) {
          if (++p.violations > 10) return this.kick(pid, '非法状态数据');
          break;
        }
        const st = this.stats[pid];
        if (st) {
          if (v > st.maxV) st.maxV = v;
          st.d = Math.max(st.d, d);
        }
        const opp = this.opponentOf(pid);
        if (opp != null) this.send(opp, { type: 'opp', d, l, v, y: +s.y || 0, fl: (s.fl | 0) || 0, cr: +s.cr || 0 });
        break;
      }
      case 'catch': {
        if (this.state !== 'playing' || !this.match || this.match.ended) break;
        const r = this.match.waveScore(pid, +msg.w, +msg.f);
        this.broadcast({ type: 'caught', by: pid, w: +msg.w, f: +msg.f, val: r.val || 0, ok: r.ok });
        break;
      }
      case 'trick': {
        if (this.state !== 'playing' || !this.match || this.match.ended) break;
        if (this.match.trick(pid)) this.broadcast({ type: 'caught', by: pid, w: -1, f: -1, val: RULES.TRICK_VAL, ok: true, trick: true });
        break;
      }
      case 'skill': {
        if (this.state !== 'playing' || !this.match || this.match.ended) break;
        const fx = this.match.useSkill(pid);
        if (fx) this.broadcast({ type: 'skillFx', by: pid, ...fx });
        break;
      }
      case 'emote': {
        if (msg.k !== 'bell' && msg.k !== 'honk') break;
        const opp = this.opponentOf(pid);
        if (opp != null) this.send(opp, { type: 'emote', by: pid, k: msg.k });
        break;
      }
      case 'again': this.again(pid); break;
      case 'leave': this.leave(pid); break;
      default: break;
    }
  }

  kick(pid, reason) {
    this.send(pid, { type: 'kick', reason });
    const p = this.players.get(pid);
    if (p) { try { p.ws.close(); } catch {} }
    this.leave(pid, true);
  }
}

export class RoomManager {
  constructor() {
    this.rooms = new Map();      // code -> Room
    this.quickQueue = [];        // {ws, name}
    setInterval(() => this.sweep(), 5000);
    setInterval(() => { for (const r of this.rooms.values()) r.tick(); }, 250);
  }

  sweep() {
    const now = Date.now();
    for (const [code, r] of this.rooms) {
      if (r.players.size === 0) { this.rooms.delete(code); continue; }
      // 等待/结算页闲置回收
      const idleLimit = r.state === 'ended' ? 5 * 60e3 : 10 * 60e3;
      const allGone = [...r.players.values()].every((p) => !p.connected);
      if (allGone && now - r.idleSince > 60e3) { this.rooms.delete(code); continue; }
      if (r.state === 'ended' && now - r.idleSince > idleLimit) { this.rooms.delete(code); continue; }
    }
    // 快速匹配队列掉线清理
    this.quickQueue = this.quickQueue.filter((q) => q.ws.readyState === 1);
  }

  createRoom(ws, name, duration) {
    let code, tries = 0;
    do { code = newCode(); } while (this.rooms.has(code) && ++tries < 50);
    const room = new Room(this, code);
    room.duration = Math.min(600, Math.max(10, +duration || 180));
    this.rooms.set(code, room);
    const pid = room.join(ws, name);
    return { room, pid };
  }

  joinRoom(ws, name, code, resume) {
    const room = this.rooms.get(String(code || '').toUpperCase());
    if (!room) return { err: '房间不存在' };
    const pid = room.join(ws, name, resume);
    if (!pid) return { err: '房间已满' };
    return { room, pid };
  }

  drop(code) { this.rooms.delete(code); }
}
