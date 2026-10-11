// 双人在线 PK：大厅 / 房间 / 远端骑手渲染 / 波次消费 / 技能 / 对局 HUD / 结算
// 通过 initPK(ctx) 注入主循环所需的一切，main.js 保持单机逻辑完整。
import * as THREE from 'three';
import { createPelican } from '../pelican.js';
import { createBicycle, BIKE_POINTS, GEARS, WHEEL_R } from '../bicycle.js';
import { NetClient } from './client.js';
import { C2S, S2C, SKILL_INFO, FL_AIR, FL_TRICK, FL_COAST } from '../../shared/protocol.mjs';

const $ = (s) => document.querySelector(s);
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

const scarfBlue = '#3f8cff';

export function initPK(ctx) {
  const { scene, S, settings, audio } = ctx;
  const net = new NetClient();
  const pk = {
    active: false,     // 对局进行中
    locked: () => lock,
    speedCap: () => (fxUntil.headwind > netNow() ? 15.5 * 0.7 : 15.5),
    accelBonus: () => (fxUntil.boost > netNow() ? 1.4 : 0),
    net,
  };

  // ---------- 本地状态 ----------
  let lock = false;                // 倒计时/结算期间锁操作
  let myId = 0, oppId = 0;
  let myName = '', oppName = '';
  let roomCode = '';
  let isHost = false, myReady = false;
  let matchEndAt = 0, overtime = false;
  let pendingSkill = null;
  let countdownEnd = 0;
  const fxUntil = { headwind: 0, boost: 0, fog: 0 };
  const state = {
    oppD: 0, oppL: 0, oppV: 0, oppY: 0, oppFl: 0, connected: false,
  };
  const buf = [];                  // 对手快照缓冲
  let sendAcc = 0;

  const netNow = () => net.now();

  // ---------- DOM ----------
  const el = {
    lobby: $('#lobby'), roomPanel: $('#roomPanel'), result: $('#result'),
    pkHud: $('#pkHud'), skillHud: $('#skillHud'), countdown: $('#pkCountdown'),
    fog: $('#fogFx'), name: $('#pkName'), code: $('#pkCode'), dur: $('#pkDur'),
    lobbyStatus: $('#pkLobbyStatus'), roomStatus: $('#roomStatus'), roomCode: $('#roomCode'),
    roomPlayers: $('#roomPlayers'), roomReady: $('#roomReady'), roomStart: $('#roomStart'),
    myName: $('#pkMyName'), myScore: $('#pkMyScore'), oppName: $('#pkOppName'), oppScore: $('#pkOppScore'),
    timer: $('#pkTimer'), ot: $('#pkOvertime'), oppDist: $('#pkOppDist'),
    skillIcon: $('#skillIcon'), skillBtn: $('#skillBtn'),
    rTitle: $('#resultTitle'), rSub: $('#resultSub'), rStats: $('#resultStats'), rStatus: $('#resultStatus'),
  };

  const setStatus = (msg, isErr = false) => {
    for (const [node, text] of [[el.lobbyStatus, msg], [el.roomStatus, msg]]) {
      if (!node || !text) continue;
      node.textContent = text;
      node.classList.toggle('err', isErr);
    }
  };
  const status = (msg, isErr) => { if (el.lobbyStatus) { el.lobbyStatus.textContent = msg || ''; el.lobbyStatus.classList.toggle('err', isErr); } };
  const roomStatus = (msg, isErr) => { if (el.roomStatus) { el.roomStatus.textContent = msg || ''; el.roomStatus.classList.toggle('err', isErr); } };

  // ---------- 远端骑手 ----------
  const rr = new THREE.Group();
  rr.rotation.order = 'YXZ';
  rr.visible = false;
  scene.add(rr);
  const rWheelie = new THREE.Group();
  rWheelie.position.set(BIKE_POINTS.rearHub.x, 0, 0);
  rr.add(rWheelie);
  const rContent = new THREE.Group();
  rContent.position.set(-BIKE_POINTS.rearHub.x, 0, 0);
  rWheelie.add(rContent);
  const rBike = createBicycle();
  const rPelican = createPelican();
  rContent.add(rBike.group, rPelican.root);
  // 蓝围巾结：区分敌我
  rPelican.knot.material = rPelican.knot.material.clone();
  rPelican.knot.material.color.set(scarfBlue);

  // 名牌 Sprite
  const tagCanvas = document.createElement('canvas');
  tagCanvas.width = 256; tagCanvas.height = 72;
  const tagCtx = tagCanvas.getContext('2d');
  const tagTex = new THREE.CanvasTexture(tagCanvas);
  tagTex.colorSpace = THREE.SRGBColorSpace;
  const tag = new THREE.Sprite(new THREE.SpriteMaterial({ map: tagTex, transparent: true, depthWrite: false }));
  tag.scale.set(1.5, 0.42, 1);
  tag.position.set(0, 2.45, 0);
  rr.add(tag);
  let tagScoreShown = -1;
  function drawTag() {
    const c = tagCtx;
    c.clearRect(0, 0, 256, 72);
    c.font = '700 26px system-ui, sans-serif';
    c.textAlign = 'center';
    c.lineWidth = 6;
    c.strokeStyle = 'rgba(8,12,24,0.85)';
    c.strokeText(oppName || '对手', 128, 30);
    c.fillStyle = '#bcd6ff';
    c.fillText(oppName || '对手', 128, 30);
    c.font = '800 30px system-ui, sans-serif';
    c.strokeText(String(el.oppScore?.textContent || '0'), 128, 64);
    c.fillStyle = '#ffd257';
    c.fillText(String(el.oppScore?.textContent || '0'), 128, 64);
    tagTex.needsUpdate = true;
  }

  // 远端插值渲染
  const rTmp = {
    d: 0, l: 0, v: 0, y: 0, fl: 0,
    crank: 0, wheel: 0, lean: 0, prevL: 0,
    gripL: new THREE.Vector3(), gripR: new THREE.Vector3(),
    lookW: new THREE.Vector3(),
  };
  function updateRemote(dt) {
    if (!buf.length) return;
    const target = performance.now() - 110;
    let a = buf[0], b = buf[buf.length - 1];
    for (let i = 0; i < buf.length - 1; i++) {
      if (buf[i].rt <= target && buf[i + 1].rt >= target) { a = buf[i]; b = buf[i + 1]; break; }
    }
    const span = Math.max(1, b.rt - a.rt);
    const u = clamp((target - a.rt) / span, 0, 1);
    rTmp.d = a.d + (b.d - a.d) * u;
    rTmp.l = a.l + (b.l - a.l) * u;
    rTmp.v = a.v + (b.v - a.v) * u;
    rTmp.y = a.y + (b.y - a.y) * u;
    rTmp.fl = b.fl;
    while (buf.length > 30) buf.shift();

    const rel = rTmp.d - S.distance;
    rr.visible = state.connected && Math.abs(rel) < 110;
    if (!rr.visible) return;

    // 车身姿态
    const laneV = (rTmp.l - rTmp.prevL) / Math.max(dt, 1e-3);
    rTmp.prevL = rTmp.l;
    rTmp.lean += (clamp(Math.atan((laneV * 0.55) / 9.8) * 1.4, -0.4, 0.4) - rTmp.lean) * Math.min(1, dt * 6);
    rr.position.set(rel, rTmp.y, rTmp.l);
    rr.rotation.set(rTmp.lean, -Math.atan2(laneV, Math.max(rTmp.v, 1.5)), 0);
    rWheelie.rotation.z = (rTmp.fl & FL_TRICK ? 0.3 : 0) + (rTmp.fl & FL_AIR ? 0.06 : 0);

    // 踏频 / 车轮 / 档位
    let gear = 2;
    if (rTmp.v > 0.3) {
      const wheelRpm = (rTmp.v / WHEEL_R) * 60 / (2 * Math.PI);
      let bestErr = 1e9;
      GEARS.forEach(([r, c], i) => {
        const err = Math.abs(wheelRpm / (r / c) - 86);
        if (err < bestErr) { bestErr = err; gear = i; }
      });
    }
    const ratio = GEARS[gear][0] / GEARS[gear][1];
    const coast = (rTmp.fl & FL_COAST) !== 0;
    rTmp.crank += (coast ? 0 : rTmp.v / WHEEL_R / ratio) * dt;
    rTmp.wheel += (rTmp.v / WHEEL_R) * dt;
    rBike.update({ wheelAngle: rTmp.wheel, crankAngle: rTmp.crank, steerAngle: 0, speed: rTmp.v, night: ctx.envNight() });

    rBike.group.updateMatrixWorld(true);
    const steerM = rBike.steerMatrix();
    rTmp.gripL.copy(rBike.anchors.gripL.position).applyMatrix4(steerM);
    rTmp.gripR.copy(rBike.anchors.gripR.position).applyMatrix4(steerM);
    rTmp.lookW.set(rr.position.x + 6, 1.15, rr.position.z);
    rPelican.update(dt, {
      t: performance.now() / 1000,
      crankAngle: rTmp.crank,
      pedal: coast || rTmp.v < 0.25 ? 0.3 : 1,
      airborne: rTmp.fl & FL_AIR ? 1 : 0,
      trick: rTmp.fl & FL_TRICK ? 1 : 0,
      accel: 0,
      look: rPelican.root.worldToLocal(rTmp.lookW),
      grips: { L: rTmp.gripL, R: rTmp.gripR },
      pedals: { L: rBike.anchors.pedalL.position, R: rBike.anchors.pedalR.position },
      helmet: true,
      glasses: false,
    });
    rPelican.root.updateMatrixWorld(true);
    rPelican.knot.visible = true;

    if (el.oppScore && +el.oppScore.textContent !== tagScoreShown) {
      tagScoreShown = +el.oppScore.textContent;
      drawTag();
    }
  }

  // ---------- 连接 ----------
  async function ensureNet() {
    if (net.connected) return true;
    net.onStatus((st, info) => {
      if (st === 'retry' && roomCode) {
        status(`连接中断，${Math.round(info / 1000)}s 后重连…`, true);
      }
      if (st === 'open' && roomCode) {
        // 重连后重新入座
        net.send(C2S.HELLO, { name: myName });
        const saved = loadResume();
        net.send(C2S.JOIN, { code: roomCode, resume: saved?.resume });
      }
    });
    try {
      await net.connect();
      return true;
    } catch {
      status('无法连接服务器，请检查网络', true);
      return false;
    }
  }

  const loadResume = () => {
    try { return JSON.parse(localStorage.getItem(`pk:${roomCode}`) || 'null'); } catch { return null; }
  };
  const saveResume = (resume) => {
    try { localStorage.setItem(`pk:${roomCode}`, JSON.stringify({ resume, id: myId })); } catch {}
  };

  // ---------- 大厅 / 房间 UI ----------
  function openLobby() {
    el.lobby.hidden = false;
    el.name.value = localStorage.getItem('pk:name') || '';
  }
  function closeLobby() { el.lobby.hidden = true; }

  $('#pkEntry')?.addEventListener('click', openLobby);
  $('#pkLobbyBack')?.addEventListener('click', () => { closeLobby(); status(''); });
  $('#pkQuick')?.addEventListener('click', () => act('quick'));
  $('#pkCreate')?.addEventListener('click', () => act('create'));
  $('#pkJoin')?.addEventListener('click', () => act('join'));
  el.code?.addEventListener('input', () => { el.code.value = el.code.value.toUpperCase().replace(/[^A-Z0-9]/g, ''); });
  el.code?.addEventListener('keydown', (e) => { if (e.key === 'Enter') act('join'); });

  async function act(kind) {
    myName = (el.name.value || '').trim().slice(0, 12) || `鹈鹕${Math.floor(Math.random() * 900 + 100)}`;
    localStorage.setItem('pk:name', myName);
    if (!(await ensureNet())) return;
    status('连接中…');
    net.send(C2S.HELLO, { name: myName });
    if (kind === 'create') {
      const fast = new URLSearchParams(location.search).get('fast') === '1';
      net.send(C2S.CREATE, { dur: fast ? 12 : +el.dur.value || 180 });
    } else if (kind === 'join') {
      const code = (el.code.value || '').trim().toUpperCase();
      if (code.length !== 4) return status('请输入 4 位房间码', true);
      net.send(C2S.JOIN, { code, resume: loadResume()?.resume });
    } else {
      net.send(C2S.QUICK);
      status('排队中…等待另一位玩家 ⏳');
    }
  }

  el.roomReady?.addEventListener('click', () => {
    myReady = !myReady;
    net.send(C2S.READY, { on: myReady });
  });
  el.roomStart?.addEventListener('click', () => net.send(C2S.START));
  el.roomLeave?.addEventListener('click', leaveRoom);
  el.roomCopy?.addEventListener('click', () => {
    const u = new URL(location.href);
    u.search = `?room=${roomCode}`;
    navigator.clipboard?.writeText(u.toString()).then(
      () => roomStatus('邀请链接已复制 ✓'),
      () => roomStatus(u.toString()),
    );
  });

  function renderRoom(m) {
    el.roomCode.textContent = m.code;
    el.roomPlayers.innerHTML = '';
    for (const p of m.players) {
      const div = document.createElement('div');
      div.className = 'room-p' + (p.connected ? ' online' : '');
      div.innerHTML = `<span class="dot"></span><b>${escapeHtml(p.name)}</b>
        <span class="tag">${p.id === m.host ? '房主' : ''}</span>
        <span class="rd${p.ready ? ' on' : ''}">${p.connected ? (p.ready ? '已准备' : '未准备') : '重连中…'}</span>`;
      el.roomPlayers.appendChild(div);
    }
    const meReady = m.players.find((p) => p.id === myId);
    if (meReady) {
      myReady = meReady.ready;
      el.roomReady.textContent = myReady ? '取消准备' : '准备 ✓';
      el.roomReady.classList.toggle('on', myReady);
    }
    const opp = m.players.find((p) => p.id !== myId);
    if (opp) { oppId = opp.id; oppName = opp.name; }
    el.roomStart.hidden = !(myId === m.host && m.players.length === 2);
    if (m.state === 'waiting') roomStatus(m.players.length < 2 ? '等待好友加入…把房间码发给 TA 吧' : myId === m.host ? '都准备后即可开战' : '等待房主开始…');
  }

  function escapeHtml(s) { return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }

  function leaveRoom() {
    net.send(C2S.LEAVE);
    roomCode = '';
    pk.active = false;
    el.roomPanel.hidden = true;
    el.pkHud.hidden = true;
    el.skillHud.hidden = true;
    el.result.hidden = true;
    restoreSettings();
    ctx.toast('🏠', '已离开房间', '回到单人骑行');
  }

  function restoreSettings() {
    settings.autopilot = true;
    settings.timeFlow = true;
    lock = false;
  }

  // ---------- 服务器消息 ----------
  net.on(S2C.WELCOME, (m) => { if (m.id) myId = m.id; });
  net.on(S2C.ERR, (m) => { status(m.msg, !m.queue); });
  net.on(S2C.ROOM, (m) => {
    if (!roomCode && m.code) {
      roomCode = m.code;
      closeLobby();
      el.roomPanel.hidden = false;
    }
    if (m.code !== roomCode) return;
    if (m.resume) saveResume(m.resume);
    isHost = m.host === myId;
    renderRoom(m);
    if (m.state === 'countdown' || m.state === 'playing') {
      el.roomPanel.hidden = true;
    } else if (m.state === 'waiting' && el.result.hidden) {
      el.roomPanel.hidden = false;
    }
  });
  net.on(S2C.COUNTDOWN, (m) => {
    countdownEnd = m.end;
    el.roomPanel.hidden = true;
    el.result.hidden = true;
    el.pkHud.hidden = false;
    lock = true;
    // 重置本局
    S.distance = 0;
    S.speed = settings.cruise * 0.6;
    S.lane = 0.9; S.laneTarget = 0.9; S.laneV = 0;
    S.fish = 0; S.golden = 0;
    S.y = 0; S.vy = 0; S.airborne = false; S.trickT = 0;
    settings.autopilot = false;
    settings.timeFlow = false;
    settings.hour = 17.5;
    buf.length = 0;
    if (!S.started) ctx.start(true);
    ctx.setCamMode('chase');
    ctx.flashCut();
    roomStatus('');
  });
  net.on(S2C.MATCH, (m) => {
    pk.active = true;
    matchEndAt = countdownEnd + m.dur * 1000;
    overtime = false;
    el.ot.hidden = true;
    el.myName.textContent = myName || '我';
    el.oppName.textContent = oppName || '对手';
    drawTag();
  });
  net.on(S2C.OT, (m) => {
    overtime = true;
    matchEndAt = m.end;
    el.ot.hidden = false;
    ctx.toast('🥇', '金鱼决胜！', '先吃到金鱼的一方获胜');
    audio.bell();
  });
  net.on(S2C.WAVE, (m) => {
    if (pk.active) ctx.spawnWaveFish(m);
  });
  net.on(S2C.OPP, (m) => {
    buf.push({ rt: performance.now(), d: m.d, l: m.l, v: m.v, y: m.y, fl: m.fl });
    state.oppD = m.d;
    state.connected = true;
  });
  net.on(S2C.CAUGHT, (m) => {
    if (!m.ok) {
      if (m.by === myId) ctx.toast('💨', '被抢先了！', '这条鱼已被对手拿下');
      return;
    }
    if (m.by !== myId) {
      // 对手吃到：远端吞咽动画 + 音效
      rPelican.gulp();
      audio.gulp(m.val >= 5);
    }
  });
  net.on(S2C.SCORE, (m) => {
    el.myScore.textContent = m.sc[myId] ?? 0;
    el.oppScore.textContent = m.sc[oppId] ?? 0;
    if (m.fish) {
      S.fish = m.fish[myId] ?? S.fish;
      S.golden = m.gold?.[myId] ?? S.golden;
    }
  });
  net.on(S2C.SKILL, (m) => {
    pendingSkill = m.k;
    const info = SKILL_INFO[m.k];
    el.skillIcon.textContent = info.icon;
    el.skillHud.hidden = false;
    ctx.toast(info.icon, `获得技能：${info.name}`, info.self ? '按 G 给自己加速' : '按 G 释放，干扰对手');
  });
  net.on(S2C.SKILLFX, (m) => {
    const info = SKILL_INFO[m.k];
    if (m.by === myId) {
      ctx.toast(info.icon, `${info.name} 已释放！`, '');
    } else {
      ctx.toast(info.icon, `对手使用了${info.name}！`, '');
    }
    if (m.tgt === myId) {
      if (m.k === 'headwind') fxUntil.headwind = m.until;
      else if (m.k === 'fog') {
        fxUntil.fog = m.until;
        el.fog.classList.add('on');
        setTimeout(() => el.fog.classList.remove('on'), 2600);
      } else if (m.k === 'seagull') {
        audio.gull?.(audio.ctx?.currentTime ?? 0);
      }
    }
    if (m.k === 'boost' && m.by === myId) fxUntil.boost = m.until;
  });
  net.on(S2C.EMOTE, (m) => {
    if (m.by === myId) return;
    if (m.k === 'bell') audio.bell();
    else if (m.k === 'honk') { rPelican.honk(); audio.honk(); }
  });
  net.on(S2C.OPP_GONE, () => {
    state.connected = false;
    rr.visible = false;
    ctx.toast('⚠️', '对手掉线', '15 秒内重连可继续对局');
  });
  net.on(S2C.OPP_BACK, () => {
    state.connected = true;
    ctx.toast('✅', '对手回来了', '比赛继续');
  });
  net.on(S2C.KICK, (m) => {
    ctx.toast('🚫', '已被请出房间', m.reason || '');
    leaveRoom();
  });
  net.on(S2C.END, (m) => {
    pk.active = false;
    lock = true;
    el.skillHud.hidden = true;
    pendingSkill = null;
    el.fog.classList.remove('on');
    showResult(m);
  });

  function showResult(m) {
    const win = m.win;
    el.rTitle.textContent = win === 0 ? '🤝 平局' : win === myId ? '🏆 胜利！' : '🥈 惜败';
    el.rTitle.className = win === 0 ? 'draw' : win === myId ? 'win' : 'lose';
    const my = m.stats?.[myId] || {};
    const op = m.stats?.[oppId] || {};
    const rows = [
      ['总分', m.sc?.[myId] ?? 0, m.sc?.[oppId] ?? 0],
      ['吃鱼', my.fish ?? 0, op.fish ?? 0],
      ['金鱼', my.gold ?? 0, op.gold ?? 0],
      ['最高速度', ((my.maxV ?? 0) * 3.6).toFixed(0) + ' km/h', ((op.maxV ?? 0) * 3.6).toFixed(0) + ' km/h'],
      ['里程', ((my.d ?? 0) / 1000).toFixed(2) + ' km', ((op.d ?? 0) / 1000).toFixed(2) + ' km'],
    ];
    if (my.bonus || op.bonus) rows.push(['里程加成', `+${my.bonus ?? 0}`, `+${op.bonus ?? 0}`]);
    el.rStats.innerHTML = `<span class="v me">${escapeHtml(myName)}</span><span class="h"> VS </span><span class="v opp">${escapeHtml(oppName)}</span>` +
      rows.map(([k, a, b]) => `<span class="v me">${a}</span><span class="h">${k}</span><span class="v opp">${b}</span>`).join('');
    el.rSub.textContent = win === 0 ? '势均力敌，改日再战' : win === myId ? '海岸线最快的鹈鹕就是你' : '差一点点，复仇一局？';
    el.rStatus.textContent = '';
    el.result.hidden = false;
    if (win === myId) {
      ctx.confetti();
      audio.bell();
    }
  }
  $('#resultAgain')?.addEventListener('click', () => {
    net.send(C2S.AGAIN);
    el.rStatus.textContent = '等待对手同意再来一局… ⏳';
  });
  $('#resultLobby')?.addEventListener('click', () => {
    el.result.hidden = true;
    el.roomPanel.hidden = false;
    el.pkHud.hidden = true;
  });

  // ---------- 对局内交互 ----------
  function useSkill() {
    if (!pendingSkill || !pk.active) return;
    net.send(C2S.SKILL);
    pendingSkill = null;
    el.skillHud.hidden = true;
  }
  el.skillBtn?.addEventListener('click', useSkill);
  pk.useSkill = useSkill;

  // main.js 调用：捕到鱼（客户端检测）→ 上报服务器
  pk.tryCatch = (f) => {
    if (f.wave == null) return;
    net.send(C2S.CATCH, { w: f.wave, f: f.fish });
  };
  pk.onTrick = () => { if (pk.active) net.send(C2S.TRICK); };
  pk.emote = (k) => { if (pk.active || roomCode) net.send(C2S.EMOTE, { k }); };

  // ---------- 每帧 ----------
  let lastCd = -1;
  pk.update = (dt) => {
    if (!roomCode) return;
    // 倒计时展示
    if (countdownEnd) {
      const remain = (countdownEnd - netNow()) / 1000;
      const n = Math.ceil(remain);
      if (n !== lastCd && n >= 0) {
        lastCd = n;
        el.countdown.hidden = false;
        el.countdown.innerHTML = `<span>${n > 0 ? n : 'GO!'}</span>`;
        if (audio.ctx) audio.bell();
      }
      if (remain <= -0.9) {
        countdownEnd = 0;
        lastCd = -1;
        el.countdown.hidden = true;
        lock = false;
      }
    }
    // 计时 HUD
    if (pk.active || !el.pkHud.hidden) {
      const remain = Math.max(0, (matchEndAt - netNow()) / 1000);
      const mm = Math.floor(remain / 60);
      const ss = Math.floor(remain % 60);
      el.timer.textContent = `${mm}:${String(ss).padStart(2, '0')}`;
      el.timer.classList.toggle('hot', remain < 30 && !overtime);
      const gap = Math.round((state.oppD || 0) - S.distance);
      el.oppDist.textContent = oppName ? `${gap >= 0 ? '落后' : '领先'} ${Math.abs(gap)} m` : '';
    }
    // 状态上报 20Hz
    sendAcc += dt;
    if (sendAcc >= 0.05 && pk.active) {
      sendAcc = 0;
      const fl = (S.airborne ? FL_AIR : 0) | (S.trickT > 0 ? FL_TRICK : 0) | (!S.pedaling ? FL_COAST : 0);
      net.send(C2S.STATE, { d: +S.distance.toFixed(2), l: +S.lane.toFixed(2), v: +S.speed.toFixed(2), y: +S.y.toFixed(2), fl });
    }
    updateRemote(dt);
  };

  // ---------- 房间链接直进 ----------
  const qp = new URLSearchParams(location.search);
  const roomParam = (qp.get('room') || '').toUpperCase();
  if (roomParam) {
    el.code.value = roomParam;
    // 首次任意点击后可直接开大厅
    openLobby();
    status(`将加入房间 ${roomParam}，输入昵称后点「加入」`);
  }

  // 暴露给自动化测试
  pk.debug = {
    get myId() { return myId; },
    get roomCode() { return roomCode; },
    get remoteVisible() { return rr.visible; },
    get pendingSkill() { return pendingSkill; },
    net,
    get active() { return pk.active; },
  };
  return pk;
}
