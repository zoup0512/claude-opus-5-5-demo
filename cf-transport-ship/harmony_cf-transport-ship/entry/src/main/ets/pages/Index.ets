/**
 * 主页面：XComponent 渲染表面 + HUD + 触屏控制 + 各屏幕面板。
 */
import window from '@ohos.window';
import display from '@ohos.display';
import { common } from '@kit.AbilityKit';
import { Game, BoardRow } from '../game/game';
import { MenuPanel, PausePanel, EndPanel, LoadoutPanel } from './Menus';
import { weaponDef } from '../game/weapons';

const TOUCH_LOOK_K = 1.7;

@Component
struct TouchBtn {
  label: string = '';
  size: number = 56;
  right: number = 40;
  bottom: number = 60;
  onDown: () => void = () => {
  };
  onUp: () => void = () => {
  };
  @State pressed: boolean = false;

  build() {
    Text(this.label)
      .width(this.size)
      .height(this.size)
      .fontSize(this.size > 60 ? 15 : 13)
      .fontWeight(FontWeight.Bold)
      .textAlign(TextAlign.Center)
      .fontColor(this.pressed ? '#1c2530' : '#e8eef4')
      .backgroundColor(this.pressed ? '#f5b321' : 'rgba(26,38,54,0.72)')
      .borderRadius(this.size / 2)
      .border({ width: 1, color: 'rgba(255,255,255,0.25)' })
      .position({ right: this.right, bottom: this.bottom })
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down) {
          this.pressed = true;
          this.onDown();
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.pressed = false;
          this.onUp();
        }
      })
  }
}

@Entry
@Component
struct Index {
  @State screen: string = 'loading';
  @State loadP: number = 0;
  @State loadText: string = '初始化';
  game: Game = new Game();
  private tickTimer: number = -1;
  private pollTimer: number = -1;
  // HUD 镜像（低频刷新）
  @State hScoreBL: number = 0;
  @State hScoreGR: number = 0;
  @State hTime: string = '10:00';
  @State hHp: number = 100;
  @State hArmor: number = 100;
  @State hMag: number = 30;
  @State hReserve: number = 90;
  @State hWeaponName: string = '';
  @State hReloading: boolean = false;
  @State hSlots: string[] = [];
  @State hSlotCur: number = 0;
  @State hSlotsOp: number = 0;
  @State hCenterBig: string = '';
  @State hCenterSmall: string = '';
  @State hToast: string = '';
  @State hToastOp: number = 0;
  @State hBadge: string = '';
  @State hBadgeSub: string = '';
  @State hBadgeOp: number = 0;
  @State hAnnounce: string = '';
  @State hAnnounceOp: number = 0;
  @State hAimName: string = '';
  @State hProtect: string = '';
  @State hFeed: string[] = [];
  @State hScope: number = 0;
  @State hBoardOpen: boolean = false;
  @State hBoardRows: BoardRow[] = [];
  @State hFps: number = 0;
  @State hDmgFlash: number = 0;
  @State hLowHp: number = 0;
  @State hDeathK: number = 0;
  @State hProtectK: number = 0;
  // 摇杆
  @State padOn: boolean = false;
  @State padX: number = 0;
  @State padY: number = 0;
  private padCx: number = 0;
  private padCy: number = 0;
  private padTouchId: number = -1;
  private lookTouchId: number = -1;
  private lookX: number = 0;
  private lookY: number = 0;
  density: number = 3;
  // Canvas
  private crossCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private radarCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private radarW: number = 150;
  private radarH: number = 150;

  aboutToAppear(): void {
    try {
      const d = display.getDefaultDisplaySync();
      this.density = d.densityPixels;
    } catch (e) {
      this.density = 3;
    }
    // 沉浸式 + 常亮
    try {
      const ctx = this.getUIContext().getHostContext() as common.Context;
      window.getLastWindow(ctx).then((w) => {
        w.setWindowLayoutFullScreen(true);
        w.setWindowKeepScreenOn(true);
        w.setWindowSystemBarProperties({ statusBarContentColor: '#ffffff', navigationBarContentColor: '#ffffff' });
      });
    } catch (e) {
      // 忽略
    }
    this.game.init((p: number, t: string) => {
      this.loadP = p;
      this.loadText = t;
    }).then(() => {
      this.screen = 'menu';
    });
    // 主循环（游戏 tick + 渲染，loading 阶段也渲染菜单环绕镜头）
    this.tickTimer = setInterval(() => {
      this.game.tick();
    }, 1000 / 60);
    // HUD 轮询（10Hz）
    this.pollTimer = setInterval(() => {
      this.pollHud();
    }, 100);
  }

  aboutToDisappear(): void {
    if (this.tickTimer >= 0) {
      clearInterval(this.tickTimer);
    }
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
    }
    if (this.drawTimer >= 0) {
      clearInterval(this.drawTimer);
    }
  }

  onPageShow(): void {
  }

  onPageHide(): void {
    if (this.game.playing && !this.game.paused) {
      this.game.pause();
      this.screen = 'pause';
    }
  }

  private pollHud(): void {
    const g = this.game;
    const h = g.hud;
    this.screen = h.screen === 'game' ? 'game' : h.screen;
    this.hBoardOpen = h.boardOpen;
    this.hFps = h.fps;
    if (h.screen !== 'game' && h.screen !== 'pause' && h.screen !== 'loadout') {
      return;
    }
    this.hScoreBL = h.scoreBL;
    this.hScoreGR = h.scoreGR;
    const tl = Math.max(0, h.timeLeft);
    const mm = Math.floor(tl / 60);
    const ss = Math.floor(tl % 60);
    this.hTime = `${mm}:${ss < 10 ? '0' : ''}${ss}`;
    this.hHp = h.hp;
    this.hArmor = h.armor;
    this.hMag = h.mag;
    this.hReserve = h.reserve;
    this.hWeaponName = h.weaponName;
    this.hReloading = h.reloading;
    this.hSlots = h.slots;
    this.hSlotCur = h.slotCur;
    this.hSlotsOp = Math.min(1, h.slotsT * 2);
    this.hCenterBig = h.centerBig;
    this.hCenterSmall = h.centerSmall;
    this.hToast = h.toastText;
    this.hToastOp = h.toastT > 0 ? 1 : 0;
    this.hBadge = h.badgeText;
    this.hBadgeSub = h.badgeSub;
    this.hBadgeOp = h.badgeT > 0 ? 1 : 0;
    this.hAnnounce = h.announceText;
    this.hAnnounceOp = h.announceT > 0 ? 1 : 0;
    this.hAimName = h.aimName;
    this.hProtect = h.protectT > 0 ? `出生保护 ${h.protectT.toFixed(1)}s` : '';
    this.hScope = h.scopeLevel;
    this.hDmgFlash = h.dmgFlash;
    this.hLowHp = h.lowHp;
    this.hDeathK = h.deathK;
    this.hProtectK = h.protectK;
    // 击杀信息
    const feeds: string[] = [];
    for (const k of h.killFeed) {
      const w = weaponDef(k.wid) !== undefined ? weaponDef(k.wid).name : k.wid;
      const kn = k.killer.length > 0 ? `${k.killer} ` : '';
      feeds.push(`${kn}[${w}${k.hs ? '·爆头' : ''}${k.wall ? '·穿墙' : ''}] ${k.victim}`);
    }
    this.hFeed = feeds;
    // 计分板
    if (h.boardOpen) {
      this.hBoardRows = g.boardRows();
    }
  }

  // ================= 触屏 =================
  private touchStart(e: TouchEvent): void {
    for (const t of e.changedTouches) {
      if (t.screenX < this.winW() * 0.42 && this.padTouchId === -1 && this.screen === 'game') {
        this.padTouchId = t.id;
        this.padCx = t.screenX;
        this.padCy = t.screenY;
        this.padOn = true;
        this.padX = t.screenX;
        this.padY = t.screenY;
      } else if (this.lookTouchId === -1) {
        this.lookTouchId = t.id;
        this.lookX = t.screenX;
        this.lookY = t.screenY;
      }
    }
  }

  private touchMove(e: TouchEvent): void {
    const p = this.game.player;
    if (p === null) {
      return;
    }
    for (const t of e.changedTouches) {
      if (t.id === this.padTouchId) {
        let dx = t.screenX - this.padCx;
        let dy = t.screenY - this.padCy;
        const L = Math.hypot(dx, dy);
        const m = 42 * this.density; // 摇杆最大偏移（物理像素）
        if (L > m) {
          dx *= m / L;
          dy *= m / L;
        }
        this.padX = this.padCx + dx;
        this.padY = this.padCy + dy;
        p.touch.mx = dx / m;
        p.touch.mz = -dy / m;
      } else if (t.id === this.lookTouchId) {
        p.touch.lookDX += (t.screenX - this.lookX) / this.density * TOUCH_LOOK_K;
        p.touch.lookDY += (t.screenY - this.lookY) / this.density * TOUCH_LOOK_K;
        this.lookX = t.screenX;
        this.lookY = t.screenY;
      }
    }
  }

  private touchEnd(e: TouchEvent): void {
    const p = this.game.player;
    for (const t of e.changedTouches) {
      if (t.id === this.padTouchId) {
        this.padTouchId = -1;
        this.padOn = false;
        if (p !== null) {
          p.touch.mx = 0;
          p.touch.mz = 0;
        }
      }
      if (t.id === this.lookTouchId) {
        this.lookTouchId = -1;
      }
    }
  }

  private winW(): number {
    try {
      return display.getDefaultDisplaySync().width;
    } catch (e) {
      return 2340;
    }
  }

  // ================= HUD 绘制（Canvas，单位 vp） =================
  private drawCross(): void {
    const ctx = this.crossCtx;
    const g = this.game;
    const h = g.hud;
    ctx.clearRect(0, 0, 4096, 4096);
    if (this.screen !== 'game') {
      return;
    }
    const p = g.player;
    if (p === null) {
      return;
    }
    const W = 4096;
    const H = 4096;
    const cx = W / 2;
    const cy = H / 2;
    if (p.alive && h.scopeLevel === 0) {
      const gap = 4 + h.spreadPx / this.density;
      const len = 9;
      const wdt = 2;
      ctx.fillStyle = 'rgba(255,255,255,0.92)';
      ctx.fillRect(cx - wdt / 2, cy - gap - len, wdt, len);
      ctx.fillRect(cx - wdt / 2, cy + gap, wdt, len);
      ctx.fillRect(cx - gap - len, cy - wdt / 2, len, wdt);
      ctx.fillRect(cx + gap, cy - wdt / 2, len, wdt);
      // 命中标记
      if (h.hitT > 0) {
        const a = Math.min(1, h.hitT * 5);
        ctx.globalAlpha = a;
        ctx.strokeStyle = h.hitKind === 2 ? '#ff5040' : h.hitKind === 1 ? '#ff8060' : '#ffffff';
        ctx.lineWidth = 2.4;
        const r0 = 7;
        const r1 = 16;
        for (const s of [[1, 1], [1, -1], [-1, 1], [-1, -1]]) {
          ctx.beginPath();
          ctx.moveTo(cx + s[0] * r0, cy + s[1] * r0);
          ctx.lineTo(cx + s[0] * r1, cy + s[1] * r1);
          ctx.stroke();
        }
        ctx.globalAlpha = 1;
      }
    }
    // 受击方向指示
    for (const d of h.dmgDirs) {
      const rel = d.ang - p.yaw;
      ctx.save();
      ctx.translate(cx, cy);
      ctx.rotate(-rel);
      ctx.globalAlpha = Math.max(0, Math.min(1, d.t));
      ctx.fillStyle = '#ff4030';
      ctx.beginPath();
      ctx.moveTo(0, -150);
      ctx.lineTo(-14, -122);
      ctx.lineTo(14, -122);
      ctx.closePath();
      ctx.fill();
      ctx.globalAlpha = 1;
      ctx.restore();
    }
  }

  private drawRadar(): void {
    const ctx = this.radarCtx;
    const g = this.game;
    const p = g.player;
    const W = this.radarW * 2;
    const H = this.radarH * 2;
    ctx.clearRect(0, 0, W, H);
    if (this.screen !== 'game' || p === null) {
      return;
    }
    const S = 8;
    const zoom = 0.55 * 1.4;
    ctx.save();
    ctx.translate(W / 2, H / 2);
    ctx.rotate(p.yaw);
    ctx.scale(zoom, zoom);
    ctx.translate(-(p.pos.x + 37) * S, -(p.pos.z + 13) * S);
    ctx.globalAlpha = 0.95;
    ctx.fillStyle = 'rgba(70,80,84,0.95)';
    ctx.fillRect(-37 * S, -13 * S, 74 * S, 26 * S);
    for (const r of g.radarRects) {
      ctx.save();
      ctx.translate((r.x + 37) * S, (r.z + 13) * S);
      ctx.rotate(-r.yaw);
      const hgt = r.top;
      ctx.fillStyle = r.mesh ? 'rgba(200,200,190,0.5)'
        : hgt > 4 ? '#1d2327' : hgt > 2 ? '#2d353a' : hgt > 1.3 ? '#3b454b' : '#56616a';
      ctx.fillRect(-r.hx * S, -r.hz * S, r.hx * 2 * S, r.hz * 2 * S);
      ctx.strokeStyle = 'rgba(0,0,0,0.5)';
      ctx.lineWidth = 1;
      ctx.strokeRect(-r.hx * S, -r.hz * S, r.hx * 2 * S, r.hz * 2 * S);
      ctx.restore();
    }
    // 管道二楼虚线
    ctx.strokeStyle = 'rgba(245,179,33,0.35)';
    ctx.setLineDash([6, 4]);
    ctx.strokeRect((-29.5 + 37) * S, (9.4 + 13) * S, 36.6 * S, 2.44 * S);
    ctx.strokeRect((29.5 - 36.6 + 37) * S, (-11.84 + 13) * S, 36.6 * S, 2.44 * S);
    ctx.setLineDash([]);
    // 演员
    for (const a of g.actors) {
      if (a === p) {
        continue;
      }
      const seen = a.team === p.team || a.radarT > 0;
      if (!seen) {
        continue;
      }
      const px = (a.pos.x + 37) * S;
      const pz = (a.pos.z + 13) * S;
      if (!a.alive) {
        if (a.team !== p.team || a.deadT > 5) {
          continue;
        }
        ctx.strokeStyle = '#99a3ab';
        ctx.lineWidth = 3;
        ctx.beginPath();
        ctx.moveTo(px - 8, pz - 8);
        ctx.lineTo(px + 8, pz + 8);
        ctx.moveTo(px + 8, pz - 8);
        ctx.lineTo(px - 8, pz + 8);
        ctx.stroke();
        continue;
      }
      ctx.fillStyle = a.team === p.team ? '#4fb0ff' : '#ff4a3a';
      if (a.team === p.team) {
        ctx.save();
        ctx.translate(px, pz);
        ctx.rotate(-a.yaw);
        ctx.beginPath();
        ctx.moveTo(0, -12);
        ctx.lineTo(8, 9);
        ctx.lineTo(0, 4);
        ctx.lineTo(-8, 9);
        ctx.closePath();
        ctx.fill();
        ctx.restore();
      } else {
        ctx.globalAlpha = Math.min(1, a.radarT);
        ctx.beginPath();
        ctx.arc(px, pz, 9, 0, 7);
        ctx.fill();
        ctx.globalAlpha = 0.95;
      }
    }
    ctx.restore();
    // 自己
    ctx.fillStyle = '#ffd24a';
    ctx.beginPath();
    ctx.moveTo(W / 2, H / 2 - 10);
    ctx.lineTo(W / 2 + 7, H / 2 + 8);
    ctx.lineTo(W / 2, H / 2 + 4);
    ctx.lineTo(W / 2 - 7, H / 2 + 8);
    ctx.closePath();
    ctx.fill();
  }

  private drawTimer: number = -1;

  private startDrawLoop(): void {
    // Canvas 每帧绘制（准星 + 雷达）
    if (this.drawTimer >= 0) {
      return;
    }
    this.drawTimer = setInterval(() => {
      this.drawCross();
      this.drawRadar();
    }, 1000 / 30);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      XComponent({
        id: 'xc',
        type: XComponentType.SURFACE,
        libraryname: 'gameRenderer'
      })
        .width('100%')
        .height('100%')
        .onLoad(() => {
          this.startDrawLoop();
        })

      // ---- HUD 层 ----
      if (this.screen === 'game' || this.screen === 'pause' || this.screen === 'loadout') {
        // 屏幕特效叠加：受伤红 / 低血红 / 死亡灰 / 保护蓝
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.hDeathK > 0.03 ? `rgba(24,26,30,${Math.min(0.72, this.hDeathK * 0.75).toFixed(2)})`
            : this.hDmgFlash > 0.03 ? `rgba(190,16,0,${Math.min(0.5, this.hDmgFlash * 0.42).toFixed(2)})`
              : this.hLowHp > 0.03 ? `rgba(140,10,6,${(this.hLowHp * 0.26).toFixed(2)})`
                : this.hProtectK > 0.03 ? `rgba(56,104,214,${(this.hProtectK * 0.12).toFixed(2)})` : Color.Transparent)
          .hitTestBehavior(HitTestMode.None)

        // 准星画布
        Canvas(this.crossCtx)
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.None)

        // 顶部比分
        Row() {
          Column() {
            Text('潜伏者').fontSize(10).fontColor('#ff9b70')
            Text(`${this.hScoreBL}`).fontSize(22).fontColor('#ff9b70').fontWeight(FontWeight.Bold)
          }
          .margin({ left: 70 })
          Column({ space: 1 }) {
            Text(this.hTime).fontSize(17).fontColor('#f2f5f8').fontWeight(FontWeight.Bold)
            Text(`目标 ${this.game.goal}`).fontSize(9).fontColor('#8b98a6')
          }
          .margin({ left: 24 })
          Column() {
            Text('保卫者').fontSize(10).fontColor('#8cc8ff')
            Text(`${this.hScoreGR}`).fontSize(22).fontColor('#8cc8ff').fontWeight(FontWeight.Bold)
          }
          .margin({ left: 24 })
          Blank()
          if (this.hFps > 0) {
            Text(`${this.hFps} FPS`).fontSize(10).fontColor('#77879a').margin({ right: 88 })
          }
        }
        .width('100%')
        .padding({ top: 8 })
        .hitTestBehavior(HitTestMode.None)

        // 雷达
        Column({ space: 2 }) {
          Canvas(this.radarCtx)
            .width(this.radarW)
            .height(this.radarH)
            .borderRadius(10)
            .clip(true)
          Text('运输船')
            .fontSize(9)
            .fontColor('#8b98a6')
        }
        .position({ left: 12, top: 44 })
        .hitTestBehavior(HitTestMode.None)

        // 击杀信息（右上）
        Column({ space: 3 }) {
          ForEach(this.hFeed, (f: string, i: number) => {
            Text(f)
              .fontSize(11)
              .fontColor('#dfe6ee')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor('rgba(10,16,26,0.55)')
              .borderRadius(4)
          }, (f: string, i: number) => `${i}_${f}`)
        }
        .position({ right: 12, top: 40 })
        .hitTestBehavior(HitTestMode.None)

        // 生命 / 护甲 / 弹药（左下 & 右下之上）
        Row({ space: 8 }) {
          Column() {
            Text(`${this.hHp}`).fontSize(24).fontColor(this.hHp <= 30 ? '#ff5040' : '#f2f5f8').fontWeight(FontWeight.Bold)
            Text('生命').fontSize(9).fontColor('#8b98a6')
          }
          Column() {
            Text(`${this.hArmor}`).fontSize(24).fontColor('#8cc8e8').fontWeight(FontWeight.Bold)
            Text('护甲').fontSize(9).fontColor('#8b98a6')
          }
        }
        .position({ left: 24, bottom: 120 })
        .hitTestBehavior(HitTestMode.None)

        Column({ space: 2 }) {
          Text(this.hWeaponName).fontSize(12).fontColor('#dfe6ee')
          Row({ space: 6 }) {
            Text(this.hMag < 0 ? '∞' : `${this.hMag}`).fontSize(26)
              .fontColor(this.hMag >= 0 && this.hMag <= 6 ? '#ff5040' : '#f2f5f8')
              .fontWeight(FontWeight.Bold)
            Text(this.hMag < 0 || this.hReserve <= 0 ? '' : `/ ${this.hReserve}`).fontSize(13).fontColor('#8b98a6')
          }
          if (this.hReloading) {
            Text('换弹中…').fontSize(10).fontColor('#f5b321')
          } else if (this.hMag === 0 && this.hReserve === 0) {
            Text('弹药耗尽').fontSize(10).fontColor('#ff5040')
          }
        }
        .alignItems(HorizontalAlign.End)
        .position({ right: 170, bottom: 150 })
        .hitTestBehavior(HitTestMode.None)

        // 武器槽
        Row({ space: 6 }) {
          ForEach(this.hSlots, (s: string, i: number) => {
            Text(`${i + 1} ${s}`)
              .fontSize(10)
              .fontColor(i === this.hSlotCur ? '#f5b321' : '#98a6b4')
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor(i === this.hSlotCur ? 'rgba(245,179,33,0.16)' : 'rgba(10,16,26,0.5)')
              .borderRadius(4)
          }, (s: string, i: number) => `${i}${s}`)
        }
        .opacity(this.hSlotsOp)
        .position({ left: 24, bottom: 70 })
        .hitTestBehavior(HitTestMode.None)

        // 准星目标名
        if (this.hAimName.length > 0) {
          Text(this.hAimName)
            .fontSize(11)
            .fontColor('#ffd9a0')
            .position({ left: '44%', top: '56%' })
            .hitTestBehavior(HitTestMode.None)
        }

        // 出生保护
        if (this.hProtect.length > 0) {
          Text(this.hProtect)
            .fontSize(11)
            .fontColor('#8cb8ff')
            .position({ left: '40%', top: '64%' })
            .hitTestBehavior(HitTestMode.None)
        }

        // 中央提示（阵亡）
        if (this.hCenterBig.length > 0) {
          Column({ space: 6 }) {
            Text(this.hCenterBig).fontSize(19).fontColor('#ff8060').fontWeight(FontWeight.Bold)
            Text(this.hCenterSmall).fontSize(12).fontColor('#dfe6ee')
          }
          .position({ left: '50%', top: '38%' })
          .translate({ x: '-50%' })
          .hitTestBehavior(HitTestMode.None)
        }

        // 提示条
        if (this.hToastOp > 0 && this.hToast.length > 0) {
          Text(this.hToast)
            .fontSize(12)
            .fontColor('#ffe9c0')
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .backgroundColor('rgba(10,16,26,0.72)')
            .borderRadius(6)
            .position({ left: '50%', top: '20%' })
            .translate({ x: '-50%' })
            .hitTestBehavior(HitTestMode.None)
        }

        // 击杀徽章
        if (this.hBadgeOp > 0) {
          Column({ space: 3 }) {
            Text(this.hBadge).fontSize(26).fontColor('#f5b321').fontWeight(FontWeight.Bold)
            Text(this.hBadgeSub).fontSize(11).fontColor('#ffe9c0')
          }
          .position({ left: '50%', top: '27%' })
          .translate({ x: '-50%' })
          .hitTestBehavior(HitTestMode.None)
        }

        // 播报
        if (this.hAnnounceOp > 0 && this.hAnnounce.length > 0) {
          Text(this.hAnnounce)
            .fontSize(14)
            .fontColor('#f5f8fa')
            .letterSpacing(2)
            .position({ left: '50%', top: '13%' })
            .translate({ x: '-50%' })
            .hitTestBehavior(HitTestMode.None)
        }

        // 狙击镜
        if (this.hScope > 0 && this.game.player !== null && this.game.player.alive) {
          ScopeOverlay()
        }

        // 计分板
        if (this.hBoardOpen) {
          BoardPanel({ rows: this.hBoardRows })
        }
      }

      // ---- 触控层 ----
      if (this.screen === 'game') {
        Column()
          .width('100%')
          .height('100%')
          .onTouch((e: TouchEvent) => {
            if (e.type === TouchType.Down) {
              this.touchStart(e);
            } else if (e.type === TouchType.Move) {
              this.touchMove(e);
            } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
              this.touchEnd(e);
            }
          })
          .hitTestBehavior(HitTestMode.Transparent)

        // 摇杆
        if (this.padOn) {
          Circle()
            .width(120)
            .height(120)
            .fill('rgba(255,255,255,0.08)')
            .stroke('rgba(255,255,255,0.3)')
            .strokeWidth(1.5)
            .position({ x: this.padX - 60, y: this.padY - 60 })
            .hitTestBehavior(HitTestMode.None)
          Circle()
            .width(52)
            .height(52)
            .fill('rgba(255,255,255,0.28)')
            .position({ x: this.padX - 26, y: this.padY - 26 })
            .hitTestBehavior(HitTestMode.None)
        } else {
          Text('◉ 移动')
            .fontSize(11)
            .fontColor('rgba(255,255,255,0.28)')
            .position({ left: 40, bottom: 60 })
            .hitTestBehavior(HitTestMode.None)
        }

        // 按钮
        TouchBtn({
          label: '开火', size: 92, right: 34, bottom: 130,
          onDown: () => {
            const p = this.game.player;
            if (p !== null) {
              p.touch.fire = true;
              p.touch.firePressed = true;
            }
          },
          onUp: () => {
            const p = this.game.player;
            if (p !== null) {
              p.touch.fire = false;
            }
          }
        })
        TouchBtn({
          label: '跳', size: 60, right: 140, bottom: 60,
          onDown: () => {
            const p = this.game.player;
            if (p !== null) {
              p.touch.jump = true;
            }
          }, onUp: () => {
          }
        })
        TouchBtn({
          label: '蹲', size: 54, right: 215, bottom: 42,
          onDown: () => {
            const p = this.game.player;
            if (p !== null) {
              p.touch.crouch = !p.touch.crouch;
            }
          }, onUp: () => {
          }
        })
        TouchBtn({
          label: '换弹', size: 54, right: 36, bottom: 240,
          onDown: () => {
            const p = this.game.player;
            if (p !== null) {
              p.touch.reloadPressed = true;
            }
          }, onUp: () => {
          }
        })
        TouchBtn({
          label: '切枪', size: 54, right: 100, bottom: 306,
          onDown: () => {
            const p = this.game.player;
            if (p !== null) {
              p.touch.quickSwitchPressed = true;
            }
          }, onUp: () => {
          }
        })
        TouchBtn({
          label: '镜', size: 60, right: 36, bottom: 56,
          onDown: () => {
            const p = this.game.player;
            if (p !== null) {
              p.touch.scopeToggle = true;
            }
          }, onUp: () => {
          }
        })
        // 顶部小按钮
        Text('≡')
          .fontSize(18)
          .fontColor('#cfd8e2')
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .backgroundColor('rgba(26,38,54,0.72)')
          .borderRadius(18)
          .position({ left: 12, top: 8 })
          .onClick(() => {
            if (this.game.playing && !this.game.paused) {
              this.game.pause();
              this.screen = 'pause';
            } else if (this.game.paused) {
              this.game.resume();
              this.screen = 'game';
            }
          })
        Text('榜')
          .fontSize(14)
          .fontColor('#cfd8e2')
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .backgroundColor('rgba(26,38,54,0.72)')
          .borderRadius(6)
          .position({ left: 54, top: 8 })
          .onClick(() => {
            this.game.scoreboard();
            this.hBoardOpen = this.game.hud.boardOpen;
          })
        Text('换枪')
          .fontSize(13)
          .fontColor('#cfd8e2')
          .padding({ left: 10, right: 10 })
          .height(36)
          .textAlign(TextAlign.Center)
          .backgroundColor('rgba(26,38,54,0.72)')
          .borderRadius(6)
          .position({ left: 96, top: 8 })
          .onClick(() => {
            this.game.toggleLoadout();
            this.screen = this.game.hud.screen === 'game' ? 'game' : this.game.hud.screen;
          })
      }

      // ---- 全屏面板 ----
      if (this.screen === 'loading') {
        Column({ space: 14 }) {
          Text('运 输 船')
            .fontSize(40)
            .fontColor('#f2f5f8')
            .fontWeight(FontWeight.Bold)
            .letterSpacing(8)
          Text(this.loadText)
            .fontSize(13)
            .fontColor('#8b98a6')
          Row() {
            Row()
              .width(`${this.loadP * 100}%`)
              .height('100%')
              .backgroundColor('#f5b321')
          }
          .width(260)
          .height(6)
          .borderRadius(3)
          .backgroundColor('#1c2836')
          Text('小提示：蹲下再跳（蹲跳）可以跳得更高，踩木箱能爬上集装箱二楼。')
            .fontSize(10)
            .fontColor('#77879a')
            .padding({ left: 30, right: 30 })
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#14202c')
      }
      if (this.screen === 'menu') {
        MenuPanel({ game: this.game })
      }
      if (this.screen === 'pause') {
        PausePanel({ game: this.game })
      }
      if (this.screen === 'loadout') {
        LoadoutPanel({ game: this.game })
      }
      if (this.screen === 'end') {
        EndPanel({ game: this.game })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#14202c')
  }
}

@Component
struct ScopeOverlay {
  build() {
    // 黑色遮罩（圆孔外围）+ 十字分划线
    Stack() {
      // 左右遮罩
      Column()
        .width('7%')
        .height('100%')
        .backgroundColor('#050505')
        .position({ left: 0, top: 0 })
      Column()
        .width('7%')
        .height('100%')
        .backgroundColor('#050505')
        .position({ right: 0, top: 0 })
      Column()
        .width('100%')
        .height('7%')
        .backgroundColor('#050505')
        .position({ top: 0 })
      Column()
        .width('100%')
        .height('7%')
        .backgroundColor('#050505')
        .position({ bottom: 0 })
      // 镜筒边框
      Circle()
        .width('86%')
        .height('86%')
        .fill(Color.Transparent)
        .stroke('#0a0a0a')
        .strokeWidth(8)
      // 十字线
      Column()
        .width(1.4)
        .height('86%')
        .backgroundColor('rgba(10,10,10,0.9)')
      Row()
        .width('86%')
        .height(1.4)
        .backgroundColor('rgba(10,10,10,0.9)')
      // 中心红点
      Circle()
        .width(4)
        .height(4)
        .fill('#d02020')
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}

@Component
struct BoardPanel {
  @Prop rows: BoardRow[] = [];

  build() {
    Column({ space: 4 }) {
      Text('运输船 · 团队竞技')
        .fontSize(15)
        .fontColor('#f2f5f8')
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 4 })
      Row() {
        Text('潜伏者').fontSize(12).fontColor('#ff9b70').layoutWeight(1)
        Text('杀').fontSize(11).fontColor('#8b98a6').width(34).textAlign(TextAlign.End)
        Text('死').fontSize(11).fontColor('#8b98a6').width(34).textAlign(TextAlign.End)
        Text('爆头').fontSize(11).fontColor('#8b98a6').width(44).textAlign(TextAlign.End)
      }
      .width('100%')
      Divider().color('#2a3646')
      Row() {
        Text('保卫者').fontSize(12).fontColor('#8cc8ff').layoutWeight(1)
        Text('杀').fontSize(11).fontColor('#8b98a6').width(34).textAlign(TextAlign.End)
        Text('死').fontSize(11).fontColor('#8b98a6').width(34).textAlign(TextAlign.End)
        Text('爆头').fontSize(11).fontColor('#8b98a6').width(44).textAlign(TextAlign.End)
      }
      .width('100%')
      Divider().color('#2a3646')
      Scroll() {
        Column({ space: 2 }) {
          ForEach(this.rows, (r: BoardRow) => {
            Row() {
              Text(r.name)
                .fontSize(11)
                .maxLines(1)
                .fontColor(r.me ? '#f5b321' : r.dead ? '#6b7886' : r.team === 'BL' ? '#ff9b70' : '#8cc8ff')
                .layoutWeight(1)
              Text(`${r.k}`).fontSize(11).fontColor('#dfe6ee').width(34).textAlign(TextAlign.End)
              Text(`${r.d}`).fontSize(11).fontColor('#98a6b4').width(34).textAlign(TextAlign.End)
              Text(`${r.hs}`).fontSize(11).fontColor('#98a6b4').width(44).textAlign(TextAlign.End)
            }
            .width('100%')
          }, (r: BoardRow) => r.name)
        }
      }
      .constraintSize({ maxHeight: 180 })
    }
    .width(300)
    .padding(14)
    .borderRadius(10)
    .backgroundColor('rgba(10,16,26,0.88)')
    .position({ left: '50%', top: '50%' })
    .translate({ x: '-50%', y: '-50%' })
    .hitTestBehavior(HitTestMode.None)
  }
}
