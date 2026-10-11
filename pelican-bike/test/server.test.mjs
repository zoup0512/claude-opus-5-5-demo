// 服务器逻辑冒烟测试：两个假客户端完整跑一局（缩短时长）
// 用法：node test/server.test.mjs
import WebSocket from 'ws';

const PORT = 18092;
const URL = `ws://127.0.0.1:${PORT}`;
const { C2S, S2C } = await import('../shared/protocol.mjs');

// 缩短规则便于测试：直接 patch 模块常量不可行（const），改用环境控制：时长走 create 参数
process.env.PORT = String(PORT);
process.env.HOST = '127.0.0.1';
await import('../server/index.mjs');
await new Promise((r) => setTimeout(r, 300));

let failures = 0;
const ok = (cond, name) => {
  console.log(`${cond ? '  ✓' : '  ✗ FAIL'} ${name}`);
  if (!cond) failures++;
};

class Fake {
  constructor(name) {
    this.name = name;
    this.inbox = [];
    this.waiters = [];
    this.ws = new WebSocket(URL);
    this.ws.on('message', (d) => {
      const m = JSON.parse(String(d));
      this.inbox.push(m);
      this.waiters = this.waiters.filter((w) => !w(m));
    });
    this.pending = [];
    this.ws.on('open', () => { this.open = true; for (const d of this.pending.splice(0)) this.ws.send(d); });
  }
  send(type, extra = {}) { const d = JSON.stringify({ type, ...extra }); if (this.ws.readyState === 1) this.ws.send(d); else this.pending.push(d); }
  wait(pred, timeout = 5000) {
    const found = this.inbox.find(pred);
    if (found) return Promise.resolve(found);
    return new Promise((res, rej) => {
      const t = setTimeout(() => rej(new Error('timeout waiting')), timeout);
      this.waiters.push((m) => { if (pred(m)) { clearTimeout(t); res(m); return true; } return false; });
    });
  }
  count(pred) { return this.inbox.filter(pred).length; }
}

console.log('— 房间流程 —');
const A = new Fake('Alice');
const B = new Fake('Bob');
await new Promise((r) => setTimeout(r, 200));
A.send(C2S.HELLO, { name: 'Alice' });
B.send(C2S.HELLO, { name: 'Bob' });
await A.wait((m) => m.type === 'welcome');
await B.wait((m) => m.type === 'welcome');
A.send(C2S.CREATE, { dur: 12 }); // 12 秒超短局
const roomA = await A.wait((m) => m.type === S2C.ROOM);
const code = roomA.code;
ok(code?.length === 4, `建房成功 code=${code}`);

B.send(C2S.JOIN, { code });
const roomB = await B.wait((m) => m.type === S2C.ROOM && m.players?.length === 2);
ok(roomB.players.length === 2, '两人进房');
ok(roomB.players.some((p) => p.name === 'Alice'), '成员名单含 Alice');

B.send(C2S.READY, { on: true });
A.send(C2S.READY, { on: true });
A.send(C2S.START); // 房主开赛
const cd = await A.wait((m) => m.type === S2C.COUNTDOWN);
ok(cd.end > Date.now(), '倒计时下发');
const matchA = await A.wait((m) => m.type === S2C.MATCH);
ok(matchA.dur === 12, `对局参数 dur=${matchA.dur}`);
await B.wait((m) => m.type === S2C.MATCH);

console.log('— 波次与捕鱼 —');
const wave = await A.wait((m) => m.type === S2C.WAVE, 8000);
ok(wave.fs?.length === 5, `波次 5 条鱼 wave#${wave.id}`);
await B.wait((m) => m.type === S2C.WAVE && m.id === wave.id);
ok(wave.fs.every((f) => typeof f.z === 'number' && f.i >= 0 && f.i < 5), '波次鱼结构合法');

// 双方都报状态
const t0 = setInterval(() => {
  A.send(C2S.STATE, { d: 10, l: 0.5, v: 7, y: 0, fl: 0, cr: 1 });
  B.send(C2S.STATE, { d: 8, l: -0.5, v: 6, y: 0, fl: 0, cr: 1 });
}, 50);

await B.wait((m) => m.type === S2C.OPP); // B 收到 A 的状态转发
ok(true, '状态转发 opp');

// A 报捕鱼
A.send(C2S.CATCH, { w: wave.id, f: wave.fs[0].i });
const caught = await A.wait((m) => m.type === S2C.CAUGHT && m.w === wave.id);
ok(caught.ok && caught.by === 1, `A 捕鱼核销 +${caught.val}`);
// B 抢同一条 → 落空
B.send(C2S.CATCH, { w: wave.id, f: wave.fs[0].i });
const caught2 = await B.wait((m) => m.type === S2C.CAUGHT && m.w === wave.id && m.by === 2);
ok(caught2.ok === false, '同鱼二抢落空');
// 伪造不存在的鱼
A.send(C2S.CATCH, { w: wave.id, f: 99 });
const caught3 = await A.wait((m) => m.type === S2C.CAUGHT && m.f === 99);
ok(caught3.ok === false, '伪造鱼序号被拒');

// 特技计分（同波上限 1 次）
A.send(C2S.TRICK);
await A.wait((m) => m.type === S2C.CAUGHT && m.trick);
A.send(C2S.TRICK);
await new Promise((r) => setTimeout(r, 300));
ok(A.count((m) => m.type === S2C.CAUGHT && m.trick) === 1, '特技每波只计 1 次');

const scoreMsg = await A.wait((m) => m.type === S2C.SCORE && m.sc[1] >= 2);
ok(scoreMsg.sc[1] >= 2, `计分广播 A=${scoreMsg.sc[1]} B=${scoreMsg.sc[2]}`);

console.log('— 终局（3 秒短局）—');
const end = await A.wait((m) => m.type === S2C.END, 25000);
ok(end.win === 1, `3 秒局 A 胜（分差+里程）win=${end.win}`);
ok(end.stats?.[1]?.bonus === 3, '里程加成 +3');
const endB = await B.wait((m) => m.type === S2C.END);
ok(endB.win === 1, 'B 同步收到终局');

console.log('— 再来一局 —');
A.send(C2S.AGAIN);
B.send(C2S.AGAIN);
const roomAgain = await A.wait((m) => m.type === S2C.ROOM && m.state === 'countdown', 5000);
ok(roomAgain.state === 'countdown', '双方 again 后进入新倒计时');

await A.wait((m) => m.type === S2C.MATCH && m.seed !== matchA.seed, 8000); // 新一局已开
console.log('— 断线判负（对局中）—');
B.ws.close();
const end2 = await A.wait((m) => m.type === S2C.END && m !== end, 20000);
ok(end2.win === 1, 'B 断线超时后 A 判胜');
A.ws.close();

console.log('— 快速匹配 —');
const C = new Fake('C');
const D = new Fake('D');
C.send(C2S.HELLO, { name: 'C' });
D.send(C2S.HELLO, { name: 'D' });
await C.wait((m) => m.type === 'welcome');
await D.wait((m) => m.type === 'welcome');
C.send(C2S.QUICK);
const q = await C.wait((m) => m.type === S2C.ERR && m.queue);
ok(q.queue, 'C 排队中');
D.send(C2S.QUICK);
const roomC = await C.wait((m) => m.type === S2C.ROOM && m.players?.length === 2, 4000);
ok(roomC.players.length === 2, '快速匹配配对成功');
C.ws.close(); D.ws.close();

console.log(failures === 0 ? '\n全部通过 ✓' : `\n${failures} 项失败 ✗`);
process.exit(failures === 0 ? 0 : 1);
