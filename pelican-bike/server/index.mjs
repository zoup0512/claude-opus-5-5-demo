// 鹈鹕骑单车 · 在线 PK 服务器
// 用法：node server/index.mjs   （默认 127.0.0.1:8092，经 nginx /ws 反代对外）
import http from 'node:http';
import { WebSocketServer } from 'ws';
import { RoomManager } from './room.mjs';
import { PROTO } from '../shared/protocol.mjs';

const PORT = +(process.env.PORT || 8092);
const HOST = process.env.HOST || '127.0.0.1';

const manager = new RoomManager();
const httpServer = http.createServer((req, res) => {
  if (req.url === '/healthz') {
    const rooms = manager.rooms.size;
    const players = [...manager.rooms.values()].reduce((n, r) => n + r.players.size, 0);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, proto: PROTO, rooms, players, uptime: process.uptime() | 0 }));
    return;
  }
  res.writeHead(404).end();
});

const wss = new WebSocketServer({ server: httpServer, maxPayload: 4096 });

// 每连接限速：令牌桶 40 msg/s
const buckets = new WeakMap();
function rateOk(ws) {
  const now = Date.now();
  let b = buckets.get(ws);
  if (!b) buckets.set(ws, (b = { tokens: 20, last: now }));
  b.tokens = Math.min(60, b.tokens + ((now - b.last) / 1000) * 40);
  b.last = now;
  if (b.tokens < 1) return false;
  b.tokens -= 1;
  return true;
}

const sessions = new WeakMap(); // ws -> {room, pid, named}

wss.on('connection', (ws, req) => {
  ws.on('message', (data, isBinary) => {
    if (isBinary) return;
    if (!rateOk(ws)) return;
    let msg;
    try { msg = JSON.parse(String(data)); } catch { return; }
    if (typeof msg?.type !== 'string') return;
    const s = sessions.get(ws);

    // ---- 未注册会话：只接受 hello ----
    if (!s) {
      if (msg.type !== 'hello') return;
      const name = String(msg.name || '').trim().slice(0, 12) || '鹈鹕';
      sessions.set(ws, { name, room: null, pid: 0, queued: false });
      ws.send(JSON.stringify({ type: 'welcome', id: 0, proto: PROTO }));
      return;
    }

    try {
      switch (msg.type) {
        case 'create': {
          if (s.room) return;
          const { room, pid } = manager.createRoom(ws, s.name, msg.dur);
          s.room = room; s.pid = pid;
          room.send(pid, { type: 'welcome', id: pid, proto: PROTO });
          room.roomState(pid);
          break;
        }
        case 'join': {
          if (s.room) return;
          const r = manager.joinRoom(ws, s.name, msg.code, msg.resume);
          if (r.err) return ws.send(JSON.stringify({ type: 'err', msg: r.err }));
          s.room = r.room; s.pid = r.pid;
          r.room.send(r.pid, { type: 'welcome', id: r.pid, proto: PROTO });
          r.room.broadcast(r.room.roomMsg());
          break;
        }
        case 'quick': {
          if (s.room) return;
          manager.quickQueue = manager.quickQueue.filter((q) => q.ws.readyState === 1 && q.ws !== ws);
          if (manager.quickQueue.length === 0) {
            manager.quickQueue.push({ ws, session: s });
            return ws.send(JSON.stringify({ type: 'err', msg: '排队中…等待另一位玩家', queue: true }));
          }
          const other = manager.quickQueue.shift();
          const { room, pid: pidA } = manager.createRoom(other.ws, other.session.name, 180);
          const pidB = room.join(ws, s.name);
          other.session.room = room; other.session.pid = pidA;
          s.room = room; s.pid = pidB;
          for (const pid of room.playerIds) room.send(pid, { type: 'welcome', id: pid, proto: PROTO });
          room.broadcast(room.roomMsg());
          break;
        }
        case 'ping': ws.send(JSON.stringify({ type: 'pong', t: msg.t, now: Date.now() })); break;
        case 'leave': {
          if (s.room) { s.room.leave(s.pid); s.room = null; }
          break;
        }
        default: {
          if (s.room) s.room.onMessage(s.pid, String(data));
          break;
        }
      }
    } catch (e) {
      console.error('[ws handler]', e?.message);
    }
  });

  ws.on('close', () => {
    const s = sessions.get(ws);
    if (!s) return;
    manager.quickQueue = manager.quickQueue.filter((q) => q.ws !== ws);
    if (s.room) s.room.onDisconnect(s.pid);
  });

  ws.on('error', () => {});
});

httpServer.listen(PORT, HOST, () => {
  console.log(`[pelican-pk] listening on ws://${HOST}:${PORT} (proto v${PROTO})`);
});
