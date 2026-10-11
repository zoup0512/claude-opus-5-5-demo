// 双开浏览器 E2E：建房→加入→倒计时→骑行→波次→强制捕鱼→计分→终局
// 用法：node test/e2e.mjs                     （本地：自动起静态服务 + 游戏服务器）
//       E2E_TARGET=http://host:8091 node test/e2e.mjs   （线上：直接测部署环境）
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { chromium } from 'playwright-core';

const LIVE = process.env.E2E_TARGET;
const WEB = 18094, GAME = 18093;
let failures = 0;
const ok = (cond, name) => {
  console.log(`${cond ? '  ✓' : '  ✗ FAIL'} ${name}`);
  if (!cond) failures++;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let game = null, web = null;
const URL_ = LIVE
  ? `${LIVE}/?autostart=1&ws=${encodeURIComponent(LIVE.replace(/^http/, 'ws'))}/ws&q=low&fast=1`
  : `http://127.0.0.1:${WEB}/?autostart=1&ws=ws://127.0.0.1:${GAME}&q=low&fast=1`;
if (!LIVE) {
  // 游戏服务器
  game = spawn(process.execPath, ['server/index.mjs'], { env: { ...process.env, PORT: String(GAME), HOST: '127.0.0.1' }, stdio: 'pipe' });
  game.stdout.on('data', (d) => process.env.VERBOSE && console.log('[game]', String(d).trim()));
  game.stderr.on('data', (d) => console.log('[game-err]', String(d).trim()));

  // 静态服务
  const html = await readFile('dist/index.html', 'utf8');
  web = createServer(async (req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
  }).listen(WEB);
  await sleep(600);
}

const browser = await chromium.launch({ channel: 'msedge', headless: true, args: ['--enable-unsafe-swiftshader'] });
const mkPage = async () => {
  const ctx = await browser.newContext({ viewport: { width: 1100, height: 700 } });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('  [pageerror]', e.message.slice(0, 160)));
  await page.goto(URL_, { timeout: 60000, waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => document.body.classList.contains('ready'), null, { timeout: 60000 });
  return page;
};

try {
  console.log('— 打开两个客户端 —');
  const A = await mkPage();
  const B = await mkPage();
  ok(true, '两个页面加载完成（WebGL 正常）');

  // A 建房
  await A.click('[data-act="pk"]');
  await A.fill('#pkName', '鹈鹕A');
  await A.click('#pkCreate');
  await A.waitForSelector('#roomPanel:not([hidden])', { timeout: 8000 });
  const code = await A.textContent('#roomCode');
  ok(/^[A-Z0-9]{4}$/.test(code), `A 创建房间 ${code}`);

  // B 加入
  await B.click('[data-act="pk"]');
  await B.fill('#pkName', '鹈鹕B');
  await B.fill('#pkCode', code);
  await B.click('#pkJoin');
  await B.waitForSelector('#roomPanel:not([hidden])', { timeout: 8000 });
  const playersB = await B.textContent('#roomPlayers');
  ok(playersB.includes('鹈鹕A') && playersB.includes('鹈鹕B'), 'B 加入房间，双方在列');

  // 准备 + 开始（房主是 A 建房者）
  await A.click('#roomReady');
  await B.click('#roomReady');
  await A.waitForSelector('#roomStart:not([hidden])', { timeout: 5000 });
  await A.click('#roomStart');
  await A.waitForSelector('#pkHud:not([hidden])', { timeout: 8000 });
  await B.waitForSelector('#pkHud:not([hidden])', { timeout: 8000 });
  ok(true, '双方进入对局 HUD');

  // 等倒计时结束（GO 后解锁）
  await A.waitForFunction(() => window.__pelican && !window.__pelican.pk.locked(), null, { timeout: 10000 });
  ok(true, '倒计时结束，解锁骑行');

  // 双方加速骑行
  await A.keyboard.down('KeyW');
  await B.keyboard.down('KeyW');
  await sleep(2500);
  const dA = await A.evaluate(() => window.__pelican.S.distance);
  const dB = await B.evaluate(() => window.__pelican.S.distance);
  ok(dA > 5 && dB > 5, `双方骑行中 A=${dA.toFixed(1)}m B=${dB.toFixed(1)}m`);

  // A 能看到远端骑手（双方距离接近时）
  const sawRemote = await A.evaluate(async () => {
    for (let i = 0; i < 40; i++) {
      if (window.__pelican.pk.debug.remoteVisible) return true;
      await new Promise((r) => setTimeout(r, 100));
    }
    return false;
  });
  ok(sawRemote, 'A 画面中渲染远端鹈鹕');

  // 等第一波鱼 → A 传送到鱼嘴边强制捕鱼
  await A.evaluate(() => new Promise((res) => window.__pelican.pk.net.on('wave', res)));
  const caught = await A.evaluate(async () => {
    const { S, fishes, pk } = window.__pelican;
    for (let i = 0; i < 60; i++) {
      const f = fishes.find((x) => x.active && x.wave != null && x.caught < 0 && x.delay <= 0);
      if (f) {
        S.distance = f.x - 0.35;
        S.lane = f.z; S.laneTarget = f.z;
        S.speed = 2;
        await new Promise((r) => setTimeout(r, 120));
        if (f.caught >= 0) return true;
      }
      await new Promise((r) => setTimeout(r, 100));
    }
    return false;
  });
  ok(caught, 'A 触发捕鱼判定并上报');

  // 服务器计分广播到双方 HUD
  await A.waitForFunction(() => +document.querySelector('#pkMyScore').textContent >= 1, null, { timeout: 6000 });
  const sA = await A.evaluate(() => +document.querySelector('#pkMyScore').textContent);
  const sB = await B.evaluate(() => +document.querySelector('#pkOppScore').textContent);
  ok(sA >= 1 && sA === sB, `计分同步 A=${sA} B(对手分)=${sB}`);

  // 计时器在走
  const timerTxt = await A.textContent('#pkTimer');
  ok(/^\d+:\d{2}$/.test(timerTxt.trim()), `倒计时显示「${timerTxt.trim()}」`);

  // 12 秒局结束 → 结算页
  await A.waitForSelector('#result:not([hidden])', { timeout: 30000 });
  await B.waitForSelector('#result:not([hidden])', { timeout: 8000 });
  const titleA = await A.textContent('#resultTitle');
  const titleB = await B.textContent('#resultTitle');
  ok(titleA.includes('胜利'), `A 结算「${titleA}」`);
  ok(titleB.includes('惜败') || titleB.includes('平'), `B 结算「${titleB}」`);

  // 再来一局
  await A.click('#resultAgain');
  await B.click('#resultAgain');
  await A.waitForSelector('#pkHud:not([hidden])', { timeout: 8000 }).catch(() => {});
  const againOk = await A.evaluate(() => !document.querySelector('#pkHud').hidden);
  ok(againOk, '再来一局重新开局');
} catch (e) {
  failures++;
  console.log('  ✗ EXCEPTION', e.message);
} finally {
  await browser.close().catch(() => {});
  web?.close();
  game?.kill();
}

console.log(failures === 0 ? '\nE2E 全部通过 ✓' : `\n${failures} 项失败 ✗`);
process.exit(failures === 0 ? 0 : 1);
