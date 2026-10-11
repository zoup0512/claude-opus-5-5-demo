// WebSocket 客户端：连接 / 心跳与时钟偏移 / 自动重连 / 消息分发
import { C2S } from '../../shared/protocol.mjs';

export class NetClient {
  constructor() {
    this.ws = null;
    this.handlers = new Map();
    this.clockOffset = 0; // 服务器时间 - 本地时间
    this.connected = false;
    this.session = null; // {id, code, resume}
    this._pingTimer = null;
    this._retries = 0;
    this._closedByUs = false;
    this._onStatus = null; // (state:'open'|'closed'|'retry', info?) => void
    this.rtt = 0;
  }

  get url() {
    const override = new URLSearchParams(location.search).get('ws');
    if (override) return override;
    const proto = location.protocol === 'https:' ? 'wss' : 'ws';
    return `${proto}://${location.host}/ws`;
  }

  connect() {
    return new Promise((resolve, reject) => {
      let settled = false;
      try {
        this.ws = new WebSocket(this.url);
      } catch (e) {
        return reject(e);
      }
      this._closedByUs = false;
      this.ws.onopen = () => {
        this.connected = true;
        this._retries = 0;
        this._startPing();
        this._onStatus?.('open');
        settled = true;
        resolve();
      };
      this.ws.onmessage = (ev) => {
        let m;
        try { m = JSON.parse(ev.data); } catch { return; }
        if (m.type === 'pong') {
          // 时钟偏移：假设单向延迟 = RTT/2
          const rtt = performance.now() - m.t;
          this.rtt = rtt;
          this.clockOffset = m.now + rtt / 2 - Date.now();
          return;
        }
        const list = this.handlers.get(m.type);
        if (list) for (const fn of list) fn(m);
      };
      this.ws.onclose = () => {
        this.connected = false;
        this._stopPing();
        if (!settled) { settled = true; reject(new Error('连接失败')); }
        if (!this._closedByUs && this._retries < 6) {
          const delay = Math.min(4000, 500 * ++this._retries);
          this._onStatus?.('retry', delay);
          setTimeout(() => this.connect().catch(() => {}), delay);
        } else {
          this._onStatus?.('closed');
        }
      };
      this.ws.onerror = () => {};
    });
  }

  _startPing() {
    this._stopPing();
    this._pingTimer = setInterval(() => {
      this.send(C2S.PING, { t: performance.now() });
    }, 2000);
    this.send(C2S.PING, { t: performance.now() });
  }
  _stopPing() {
    if (this._pingTimer) clearInterval(this._pingTimer);
    this._pingTimer = null;
  }

  /** 服务器时间（ms） */
  now() { return Date.now() + this.clockOffset; }

  onStatus(fn) { this._onStatus = fn; }
  on(type, fn) {
    if (!this.handlers.has(type)) this.handlers.set(type, []);
    this.handlers.get(type).push(fn);
  }

  send(type, data = {}) {
    if (this.ws?.readyState !== WebSocket.OPEN) return false;
    try { this.ws.send(JSON.stringify({ type, ...data })); return true; } catch { return false; }
  }

  close() {
    this._closedByUs = true;
    this._stopPing();
    this.ws?.close();
    this.connected = false;
  }
}
