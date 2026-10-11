// 主页面：3D 画布 + 原生 HUD / 菜单 / 触摸操控 / 结算
import { MAPS, MODES, DIFFS, QUALITY, LAPS, CAR_SKINS, ITEM_INFO, MapCfg, Skin } from '../common/Config';
import { GameApp, GameSettings, GameSink, HudData, ResultData, ResultRow, StandingRow } from '../game/GameApp';

import { Renderer } from '../render/Renderer';
import dataPreferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import display from '@ohos.display';

const STORE = 'feiche3d.v1';

// 偏好存取
class Prefs {
  static load(ctx: common.Context, done: (s: GameSettings) => void): void {
    dataPreferences.getPreferences(ctx, STORE).then((p: dataPreferences.Preferences) => {
      const s = new GameSettings();
      s.map = p.getSync('map', 'city') as string;
      s.mode = p.getSync('mode', 'speed') as string;
      s.skin = p.getSync('skin', 0) as number;
      s.laps = p.getSync('laps', 2) as number;
      s.diff = p.getSync('diff', 1) as number;
      s.quality = p.getSync('quality', 'mid') as string;
      s.song = p.getSync('song', 0) as number;
      if (!LAPS.includes(s.laps)) s.laps = 3;
      let ok = false;
      for (const m of MAPS) {
        if (m.id === s.map) ok = true;
      }
      if (!ok) s.map = 'city';
      done(s);
    }).catch(() => {
      done(new GameSettings());
    });
  }

  static save(ctx: common.Context, s: GameSettings): void {
    dataPreferences.getPreferences(ctx, STORE).then((p: dataPreferences.Preferences) => {
      p.putSync('map', s.map);
      p.putSync('mode', s.mode);
      p.putSync('skin', s.skin);
      p.putSync('laps', s.laps);
      p.putSync('diff', s.diff);
      p.putSync('quality', s.quality);
      p.putSync('song', s.song);
      p.flush();
    }).catch(() => {
    });
  }
}

class UiSink implements GameSink {
  onStateCb: (s: string) => void = (s: string) => {
  };
  onHudCb: (d: HudData) => void = (d: HudData) => {
  };
  onProgressCb: (p: number, t: string) => void = (p: number, t: string) => {
  };
  onResultCb: (r: ResultData) => void = (r: ResultData) => {
  };
  onSongCb: (n: string) => void = (n: string) => {
  };
  ctx: common.Context | null = null;
  settings: GameSettings = new GameSettings();

  onState(state: string): void {
    this.onStateCb(state);
  }

  onHud(data: HudData): void {
    this.onHudCb(data);
  }

  onProgress(p: number, text: string): void {
    this.onProgressCb(p, text);
  }

  onResult(res: ResultData): void {
    this.onResultCb(res);
  }

  onSong(name: string): void {
    this.onSongCb(name);
  }

  requestSettings(): GameSettings {
    return this.settings;
  }

  saveSettings(s: GameSettings): void {
    this.settings = s;
    if (this.ctx !== null) Prefs.save(this.ctx, s);
  }
}

// 触控按钮
@Component
struct TouchBtn {
  label: string = '';
  btnSize: number = 74;
  hue: string = 'rgba(255,255,255,0.14)';
  onDown: () => void = () => {
  };
  onUp: () => void = () => {
  };
  @State pressed: boolean = false;

  build() {
    Text(this.label)
      .width(this.btnSize)
      .height(this.btnSize)
      .borderRadius(this.btnSize / 2)
      .backgroundColor(this.pressed ? 'rgba(39,199,255,0.55)' : this.hue)
      .border({ width: 2, color: 'rgba(255,255,255,0.35)' })
      .fontColor(Color.White)
      .fontSize(this.btnSize > 60 ? 16 : 13)
      .fontWeight(900)
      .textAlign(TextAlign.Center)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.pressed = true;
          this.onDown();
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressed = false;
          this.onUp();
        }
      })
  }
}

@Entry
@Component
struct Index {
  private renderSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private glCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderSettings);
  private mmCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderSettings);
  private spCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderSettings);
  private sink: UiSink = new UiSink();
  private game: GameApp | null = null;
  private audioUnlocked: boolean = false;
  @State state: string = 'boot';
  @State hud: HudData | null = null;
  @State prog: number = 0;
  @State progText: string = '';
  @State result: ResultData | null = null;
  @State selMap: string = 'city';
  @State selMode: string = 'speed';
  @State selSkin: number = 0;
  @State selLaps: number = 2;
  @State selDiff: number = 1;
  @State selQuality: string = 'mid';
  @State canvasPct: number = 0.8;
  @State songName: string = '';

  aboutToAppear(): void {
    const ctx = getContext(this) as common.Context;
    this.sink.ctx = ctx;
    Prefs.load(ctx, (s: GameSettings) => {
      this.sink.settings = s;
      this.selMap = s.map;
      this.selMode = s.mode;
      this.selSkin = s.skin;
      this.selLaps = s.laps;
      this.selDiff = s.diff;
      this.selQuality = s.quality;
      this.canvasPct = this.pctOf(s.quality);
      // Canvas 缓冲区由组件尺寸（vp）决定，ctx.width/height 只读不可赋值
      const that = this;
      this.sink.onStateCb = (st: string) => {
        that.state = st;
        if (st === 'race' || st === 'countdown' || st === 'finish') {
          that.result = null;
          if (that.hud === null) {
            that.hud = new HudData();
          }
        }
      };
      this.sink.onHudCb = (d: HudData) => {
        that.hud = d;
      };
      this.sink.onProgressCb = (p: number, t: string) => {
        that.prog = p;
        that.progText = t;
      };
      this.sink.onResultCb = (r: ResultData) => {
        that.result = r;
      };
      this.sink.onSongCb = (n: string) => {
        that.songName = n;
      };
      const renderer = new Renderer(this.glCtx);
      this.game = new GameApp(renderer, this.sink);
      this.game.mmCtx = this.mmCtx;
      this.game.spCtx = this.spCtx;
      this.game.onQualityChange = (p: number) => {
        that.canvasPct = p;
      };
      this.game.start();
      this.game.loadMap(s.map);
    });
  }

  aboutToDisappear(): void {
    if (this.game !== null) {
      this.game.stop();
      this.game.audio.release();
    }
  }

  private unlockAudio(): void {
    if (this.audioUnlocked || this.game === null) return;
    this.audioUnlocked = true;
    this.game.audio.init();
  }

  private setMap(id: string): void {
    if (this.game === null || id === this.selMap) return;
    this.selMap = id;
    this.game.settings.map = id;
    this.sink.saveSettings(this.game.settings);
    this.game.audio.play('click', 0);
    this.game.loadMap(id);
  }

  private startRace(): void {
    if (this.game === null) return;
    this.unlockAudio();
    const g = this.game;
    g.settings.map = this.selMap;
    g.settings.mode = this.selMode;
    g.settings.skin = this.selSkin;
    g.settings.laps = this.selLaps;
    g.settings.diff = this.selDiff;
    g.settings.quality = this.selQuality;
    g.applyQuality();
    g.sink.saveSettings(g.settings);
    this.result = null;
    g.startRace();
  }

  private inRace(): boolean {
    return this.state === 'race' || this.state === 'countdown' || this.state === 'finish' || this.state === 'paused';
  }

  private pctOf(q: string): number {
    if (q === 'low') return 0.62;
    if (q === 'high') return 1.0;
    return 0.8;
  }

  private resizeCanvas(w: number, h: number): void {
    if (this.game === null || w <= 0 || h <= 0) return;
    // ArkUI Canvas 绘制坐标系为 vp，缓冲区由组件尺寸×设备密度决定，不可手动设 ctx 尺寸
    this.game.renderer.resize(Math.round(w), Math.round(h));
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 3D 主画布（低画质：组件缩小渲染 + scale 放大显示，降低像素填充量）
      Stack({ alignContent: Alignment.Center }) {
        Canvas(this.glCtx)
          .width(this.canvasPct * 100 + '%')
          .height(this.canvasPct * 100 + '%')
          .scale({ x: 1 / this.canvasPct, y: 1 / this.canvasPct })
          .onAreaChange((oldArea: Area, newArea: Area) => {
            this.resizeCanvas(Number(newArea.width), Number(newArea.height));
          })
      }
      .width('100%')
      .height('100%')

      // ---------- HUD ----------
      if (this.inRace() && this.hud !== null) {
        this.HudLayer()
      }

      // ---------- 触摸操控 ----------
      if (this.inRace() && this.state !== 'paused' && (this.state !== 'finish' || this.result === null)) {
        this.TouchLayer()
      }

      // ---------- 加载 ----------
      if (this.state === 'loading' || this.state === 'boot') {
        Column({ space: 14 }) {
          Text(this.state === 'boot' ? '正在启动…' : this.progText)
            .fontColor(Color.White)
            .fontSize(18)
            .fontWeight(700)
          Progress({ value: this.prog * 100, total: 100, type: ProgressType.Linear })
            .width(280)
            .color('#27c7ff')
            .backgroundColor('rgba(255,255,255,0.12)')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(6,14,36,0.85)')
      }

      // ---------- 菜单 ----------
      if (this.state === 'menu') {
        this.MenuLayer()
      }

      // ---------- 暂停 ----------
      if (this.state === 'paused') {
        Column({ space: 16 }) {
          Text('暂停').fontSize(30).fontWeight(900).fontColor(Color.White)
          Button('继续比赛')
            .width(220).height(48).borderRadius(24)
            .backgroundColor('#ff8a00').fontColor(Color.White).fontSize(18).fontWeight(900)
            .onClick(() => {
              this.game?.togglePause();
            })
          Button('重新开始')
            .width(220).height(48).borderRadius(24)
            .backgroundColor('#1d5fe0').fontColor(Color.White).fontSize(16)
            .onClick(() => {
              if (this.game !== null) {
                this.game.togglePause();
                this.startRace();
              }
            })
          Button('返回大厅')
            .width(220).height(48).borderRadius(24)
            .backgroundColor('#1d5fe0').fontColor(Color.White).fontSize(16)
            .onClick(() => {
              this.game?.toMenu();
            })
        }
        .padding(26)
        .borderRadius(16)
        .backgroundColor('rgba(10,20,48,0.9)')
        .border({ width: 1, color: 'rgba(120,190,255,0.35)' })
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }

      // ---------- 结算 ----------
      if (this.result !== null && this.state === 'finish') {
        this.ResultLayer()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0a1430')
    .onTouch(() => {
      this.unlockAudio();
    })
  }

  // ---------- HUD 布局 ----------
  @Builder
  HudLayer() {
    // 排名
    Column({ space: 2 }) {
      ForEach(this.hud!.standings, (row: StandingRow, idx: number) => {
        Row({ space: 6 }) {
          Text(String(idx + 1))
            .fontSize(13).fontWeight(900).fontStyle(FontStyle.Italic)
            .fontColor('#ffd23a').width(18).textAlign(TextAlign.Center)
          Circle({ width: 9, height: 9 }).fill(row.color)
          Text(row.name + (row.fin ? ' ✔' : ''))
            .fontSize(12)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 3, bottom: 3 })
        .borderRadius(6)
        .backgroundColor(row.me ? 'rgba(255,138,0,0.45)' : Color.Transparent)
      }, (row: StandingRow, idx: number) => String(idx) + row.name)
    }
    .width(158)
    .padding({ top: 6, bottom: 6 })
    .borderRadius(12)
    .backgroundColor('rgba(10,20,48,0.72)')
    .border({ width: 1, color: 'rgba(120,190,255,0.35)' })
    .position({ x: 14, y: 14 })

    // 圈数 / 计时
    Row({ space: 10 }) {
      Column() {
        Text(this.hud!.lap).fontSize(24).fontWeight(900).fontStyle(FontStyle.Italic).fontColor('#ffd23a')
        Text('圈数 LAP').fontSize(10).fontColor('#a9bddb')
      }
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .borderRadius(12)
      .backgroundColor('rgba(10,20,48,0.72)')
      .border({ width: 1, color: 'rgba(120,190,255,0.35)' })
      Column() {
        Text(this.hud!.time).fontSize(24).fontWeight(900).fontStyle(FontStyle.Italic).fontColor(Color.White)
        Text('最佳 ' + this.hud!.best).fontSize(10).fontColor('#a9bddb')
      }
      .padding({ left: 14, right: 14, top: 4, bottom: 4 })
      .borderRadius(12)
      .backgroundColor('rgba(10,20,48,0.72)')
      .border({ width: 1, color: 'rgba(120,190,255,0.35)' })
    }
    .position({ x: '50%', y: 12 })
    .translate({ x: '-50%' })

    // 道具槽
    if (this.hud!.itemMode) {
      Row({ space: 8 }) {
        ForEach([0, 1], (k: number) => {
          Column() {
            Text(this.hud!.items.length > k ? this.itemIcon(this.hud!.items[k]) : '')
              .fontSize(26)
            Text(this.hud!.items.length > k ? this.itemName(this.hud!.items[k]) : '')
              .fontSize(9)
              .fontColor(Color.White)
          }
          .width(52)
          .height(52)
          .borderRadius(10)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('rgba(255,255,255,0.08)')
          .border({
            width: 2,
            color: k === 0 ? '#ffd23a' : 'rgba(255,255,255,0.35)'
          })
        }, (k: number) => String(k))
      }
      .position({ x: '50%', y: 70 })
      .translate({ x: '50%' })
    }

    // 小地图（右上）
    Canvas(this.mmCtx)
      .width(128)
      .height(128)
      .position({ x: '100%', y: 12 })
      .translate({ x: '-106%' })

    // 码表 + 大名次（右下）
    Column({ space: 2 }) {
      Text(String(Math.round(this.hud!.kmh)))
        .fontSize(38).fontWeight(900).fontStyle(FontStyle.Italic).fontColor(Color.White)
      Text('KM/H').fontSize(11).fontColor('#a9bddb')
    }
    .alignItems(HorizontalAlign.End)
    .position({ x: '100%', y: '66%' })
    .translate({ x: '-14%' })

    Canvas(this.spCtx)
      .width(104)
      .height(104)
      .position({ x: '100%', y: '72%' })
      .translate({ x: '-112%' })

    Text(String(this.hud!.rank) + ' / ' + String(this.hud!.total))
      .fontSize(22).fontWeight(900).fontStyle(FontStyle.Italic).fontColor('#ffd23a')
      .position({ x: 182, y: 16 })

    // 集气条 / 氮气（底部居中）
    Column({ space: 6 }) {
      if (!this.hud!.itemMode) {
        Row({ space: 8 }) {
          Text('集气').fontSize(11).fontColor('#a9bddb')
          Stack({ alignContent: Alignment.Start }) {
            Column()
              .width((this.hud!.gauge * 100) + '%')
              .height('100%')
              .borderRadius(8)
              .backgroundColor(this.hud!.gauge >= 0.999 ? '#ffd23a' : '#27c7ff')
          }
          .width(170)
          .height(14)
          .borderRadius(8)
          .backgroundColor('rgba(255,255,255,0.12)')
          .border({ width: 1, color: 'rgba(255,255,255,0.25)' })
        }
        Row({ space: 8 }) {
          ForEach([0, 1], (k: number) => {
            Text('N₂O')
              .fontSize(11).fontWeight(900).fontStyle(FontStyle.Italic)
              .fontColor(this.hud!.nitro > k ? Color.White : 'rgba(255,255,255,0.35)')
              .width(38).height(38)
              .borderRadius(19)
              .textAlign(TextAlign.Center)
              .backgroundColor(this.hud!.nitro > k ? '#1d6ff2' : 'rgba(255,255,255,0.06)')
              .border({
                width: 2,
                color: this.hud!.nitro > k ? '#7af0ff' : 'rgba(255,255,255,0.3)'
              })
          }, (k: number) => String(k) + (this.hud!.nitro > k ? 'a' : 'b'))
        }
      }
    }
    .position({ x: '50%', y: '94%' })
    .translate({ x: '-50%', y: '-100%' })
  }

  private itemIcon(id: string): string {
    const info = ITEM_INFO[id];
    return info !== undefined ? info.icon : '';
  }

  private itemName(id: string): string {
    const info = ITEM_INFO[id];
    return info !== undefined ? info.name : '';
  }

  // ---------- 触摸操控 ----------
  @Builder
  TouchLayer() {
    // 左下：转向 + 刹车
    Row({ space: 12 }) {
      TouchBtn({
        label: '◀', btnSize: 74,
        onDown: () => {
          this.game!.input.left = true;
        },
        onUp: () => {
          this.game!.input.left = false;
        }
      })
      TouchBtn({
        label: '▶', btnSize: 74,
        onDown: () => {
          this.game!.input.right = true;
        },
        onUp: () => {
          this.game!.input.right = false;
        }
      })
      TouchBtn({
        label: '刹', btnSize: 56, hue: 'rgba(255,120,90,0.25)',
        onDown: () => {
          this.game!.input.down = true;
        },
        onUp: () => {
          this.game!.input.down = false;
        }
      })
    }
    .position({ x: 20, y: '100%' })
    .translate({ y: '-92%' })

    // 右中：小喷 / 换位
    Column({ space: 12 }) {
      if (this.hud !== null && this.hud.itemMode) {
        TouchBtn({
          label: '换位', btnSize: 54,
          onDown: () => {
            this.game!.input.swapEdge = true;
          },
          onUp: () => {
          }
        })
      }
      TouchBtn({
        label: '小喷', btnSize: 62, hue: 'rgba(255,180,60,0.22)',
        onDown: () => {
          this.game!.input.boostEdge = true;
        },
        onUp: () => {
        }
      })
    }
    .position({ x: '100%', y: '56%' })
    .translate({ x: '-106%' })

    // 右下：漂移 / 氮气(道具) / 复位 / 视角
    Column({ space: 12 }) {
      TouchBtn({
        label: '漂移', btnSize: 88, hue: 'rgba(120,140,255,0.28)',
        onDown: () => {
          this.game!.input.shift = true;
        },
        onUp: () => {
          this.game!.input.shift = false;
        }
      })
      Row({ space: 12 }) {
        TouchBtn({
          label: '复位', btnSize: 48,
          onDown: () => {
            this.game!.input.resetEdge = true;
          },
          onUp: () => {
          }
        })
        TouchBtn({
          label: '视角', btnSize: 48,
          onDown: () => {
            this.game!.cycleCamera();
          },
          onUp: () => {
          }
        })
        TouchBtn({
          label: this.hud !== null && this.hud.itemMode ? '道具' : '氮气', btnSize: 74,
          hue: 'rgba(39,199,255,0.3)',
          onDown: () => {
            this.game!.input.nitroEdge = true;
          },
          onUp: () => {
          }
        })
      }
    }
    .alignItems(HorizontalAlign.End)
    .position({ x: '100%', y: '100%' })
    .translate({ x: '-104%', y: '-96%' })

    // 暂停按钮（右上，小地图下方）
    Text('⏸')
      .width(40).height(40).borderRadius(10)
      .backgroundColor('rgba(10,16,34,0.45)')
      .border({ width: 1, color: 'rgba(255,255,255,0.25)' })
      .fontColor(Color.White).fontSize(18)
      .textAlign(TextAlign.Center)
      .position({ x: '100%', y: 148 })
      .translate({ x: '-112%' })
      .onClick(() => {
        this.game?.togglePause();
      })
  }

  // ---------- 菜单 ----------
  @Builder
  MenuLayer() {
    Scroll() {
      Column({ space: 12 }) {
        Text('飞车 3D')
          .fontSize(54)
          .fontWeight(900)
          .fontStyle(FontStyle.Italic)
          .fontColor('#ffcc33')
          .padding({ top: 16 })
        Text('QQ飞车 同人还原 · 漂移 · 集气 · 小喷 · 双喷 · 氮气')
          .fontSize(13)
          .fontColor('#cfe3ff')

        // 赛道选择
        Column({ space: 8 }) {
          this.SectionTitle('选择赛道')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(MAPS, (m: MapCfg) => {
              Column({ space: 4 }) {
                Text(m.name).fontSize(18).fontWeight(900).fontColor(this.mapText(m))
                Text(m.en).fontSize(9).fontStyle(FontStyle.Italic).fontColor(this.mapText(m)).opacity(0.85)
                Text(m.tag).fontSize(10).fontColor(this.mapText(m))
              }
              .width('48.5%')
              .margin(3)
              .padding(10)
              .borderRadius(12)
              .alignItems(HorizontalAlign.Start)
              .border({
                width: this.selMap === m.id ? 2 : 1,
                color: this.selMap === m.id ? '#ffd23a' : 'rgba(255,255,255,0.2)'
              })
              .linearGradient({
                angle: 135,
                colors: this.mapGradient(m)
              })
              .onClick(() => {
                this.setMap(m.id);
              })
            }, (m: MapCfg) => m.id)
          }
        }
        .width('94%')
        .padding(12)
        .borderRadius(14)
        .backgroundColor('rgba(10,20,48,0.72)')
        .border({ width: 1, color: 'rgba(120,190,255,0.35)' })

        // 模式 / 圈数 / 难度 / 画质 / 赛车
        Column({ space: 12 }) {
          this.SectionTitle('比赛模式')
          this.OptRow(this.modeNames(), this.modeKeys(), this.selMode, 'mode', true)
          this.SectionTitle('圈数')
          this.OptRow(this.lapNames(), this.lapKeys(), this.selLaps, 'laps', false)
          this.SectionTitle('对手水平')
          this.OptRow(this.diffNames(), this.diffKeys(), this.selDiff, 'diff', false)
          this.SectionTitle('画质')
          this.OptRow(this.qualNames(), this.qualKeys(), this.selQuality, 'quality', true)
          this.SectionTitle('选择赛车')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(CAR_SKINS, (s: Skin, idx: number) => {
              Column() {
                Text('🏎')
                  .fontSize(24)
                  .fontColor(this.skinColor(idx))
                Text(s.name)
                  .fontSize(8)
                  .fontColor(this.selSkin === idx ? '#ffd23a' : '#a9bddb')
              }
              .width(64)
              .height(58)
              .margin(3)
              .borderRadius(10)
              .backgroundColor(this.skinColor(idx) + '33')
              .border({
                width: this.selSkin === idx ? 2 : 1,
                color: this.selSkin === idx ? '#ffd23a' : 'rgba(255,255,255,0.2)'
              })
              .onClick(() => {
                this.selSkin = idx;
                if (this.game !== null) {
                  this.game.settings.skin = idx;
                  this.sink.saveSettings(this.game.settings);
                }
              })
            }, (s: Skin, idx: number) => String(idx))
          }
        }
        .width('94%')
        .padding(12)
        .borderRadius(14)
        .backgroundColor('rgba(10,20,48,0.72)')
        .border({ width: 1, color: 'rgba(120,190,255,0.35)' })

        Button('开始比赛')
          .width(260)
          .height(56)
          .borderRadius(28)
          .backgroundColor('#ff8a00')
          .fontColor(Color.White)
          .fontSize(22)
          .fontWeight(900)
          .shadow({ radius: 14, color: 'rgba(255,138,0,0.55)', offsetY: 4 })
          .onClick(() => {
            this.startRace();
          })

        Text('非官方同人作品，致敬 QQ飞车。所有模型、贴图、音乐均为程序实时生成。')
          .fontSize(10)
          .fontColor('rgba(200,220,255,0.6)')
          .padding({ bottom: 24 })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(8,20,55,0.72)')
    .scrollBar(BarState.Off)
  }

  @Builder
  SectionTitle(t: string) {
    Text(t)
      .fontSize(13)
      .fontWeight(800)
      .fontColor('#27c7ff')
      .alignSelf(ItemAlign.Start)
  }

  @Builder
  OptRow(names: string[], keys: string[], sel: string | number, group: string, isStr: boolean) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(names, (name: string, idx: number) => {
        Text(name)
          .fontSize(13)
          .fontColor(Color.White)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .margin(3)
          .borderRadius(10)
          .backgroundColor(this.optSel(keys, idx, sel, isStr) ? '#ff8a00' : 'rgba(255,255,255,0.07)')
          .border({
            width: 1,
            color: this.optSel(keys, idx, sel, isStr) ? '#ffd48a' : 'rgba(255,255,255,0.2)'
          })
          .fontWeight(this.optSel(keys, idx, sel, isStr) ? 800 : 400)
          .onClick(() => {
            const g = this.game;
            if (g === null) return;
            const key = keys[idx];
            const val: string | number = isStr ? key : Number(key);
            if (group === 'mode') g.settings.mode = val as string;
            else if (group === 'laps') g.settings.laps = val as number;
            else if (group === 'diff') g.settings.diff = val as number;
            else if (group === 'quality') g.settings.quality = val as string;
            this.selMode = g.settings.mode;
            this.selLaps = g.settings.laps;
            this.selDiff = g.settings.diff;
            this.selQuality = g.settings.quality;
            this.canvasPct = this.pctOf(this.selQuality);
            g.applyQuality();
            g.audio.play('click', 0);
            g.sink.saveSettings(g.settings);
          })
      }, (name: string) => name)
    }
  }

  private optSel(keys: string[], idx: number, sel: string | number, isStr: boolean): boolean {
    const key = keys[idx];
    if (isStr) return key === (sel as string);
    return Number(key) === (sel as number);
  }

  private modeNames(): string[] {
    const arr: string[] = [];
    for (const m of MODES) arr.push(m.name);
    return arr;
  }

  private modeKeys(): string[] {
    const arr: string[] = [];
    for (const m of MODES) arr.push(m.id);
    return arr;
  }

  private lapNames(): string[] {
    const arr: string[] = [];
    for (const l of LAPS) arr.push(String(l) + ' 圈');
    return arr;
  }

  private lapKeys(): string[] {
    const arr: string[] = [];
    for (const l of LAPS) arr.push(String(l));
    return arr;
  }

  private diffNames(): string[] {
    const arr: string[] = [];
    for (const d of DIFFS) arr.push(d.name);
    return arr;
  }

  private diffKeys(): string[] {
    const arr: string[] = [];
    for (const d of DIFFS) arr.push(String(d.id));
    return arr;
  }

  private qualNames(): string[] {
    const arr: string[] = [];
    for (const q of QUALITY) arr.push(q.name);
    return arr;
  }

  private qualKeys(): string[] {
    const arr: string[] = [];
    for (const q of QUALITY) arr.push(q.id);
    return arr;
  }

  private mapGradient(m: MapCfg): [ResourceColor, number][] {
    const g: Record<string, [ResourceColor, number][]> = {
      'city': [['#2f7fe0', 0], ['#6fc3ff', 0.6], ['#a6e1ff', 1]],
      'aegean': [['#1d63c9', 0], ['#5ab0ff', 0.55], ['#f4f1ea', 1]],
      'egypt': [['#5b3f9e', 0], ['#d99b3f', 0.55], ['#f3d58f', 1]],
      'snow': [['#3f86d6', 0], ['#bfe1ff', 0.55], ['#ffffff', 1]],
    };
    const hit = g[m.id];
    return hit !== undefined ? hit : g['city'];
  }

  private mapText(m: MapCfg): ResourceColor {
    return m.id === 'snow' ? '#0b2750' : '#ffffff';
  }

  private skinColor(idx: number): string {
    const body = CAR_SKINS[idx % CAR_SKINS.length].body;
    const hex = body.toString(16);
    return '#' + '000000'.substring(0, 6 - hex.length) + hex;
  }

  // ---------- 结算 ----------
  @Builder
  ResultLayer() {
    Scroll() {
      Column({ space: 12 }) {
        Text(this.result!.title)
          .fontSize(30)
          .fontWeight(900)
          .fontColor(this.result!.win ? '#ffd23a' : Color.White)
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(this.result!.stats, (s: string) => {
            Text(s)
              .fontSize(11)
              .fontColor('#a9bddb')
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .margin(3)
              .borderRadius(8)
              .backgroundColor('rgba(255,255,255,0.08)')
          }, (s: string) => s)
        }
        Column({ space: 0 }) {
          Row() {
            Text('名次').fontSize(11).fontColor('#a9bddb').width(44).textAlign(TextAlign.Center)
            Text('车手').fontSize(11).fontColor('#a9bddb').layoutWeight(1)
            Text('总时间').fontSize(11).fontColor('#a9bddb').layoutWeight(1).textAlign(TextAlign.End)
            Text('最佳单圈').fontSize(11).fontColor('#a9bddb').layoutWeight(1).textAlign(TextAlign.End)
          }
          .padding({ top: 6, bottom: 6 })
          ForEach(this.result!.rows, (row: ResultRow) => {
            Row() {
              Text(String(row.pos)).fontSize(16).fontWeight(900).fontStyle(FontStyle.Italic).fontColor('#ffd23a')
                .width(44).textAlign(TextAlign.Center)
              Text(row.name).fontSize(13).fontColor(Color.White).layoutWeight(1)
              Text(row.total).fontSize(12).fontColor(Color.White).layoutWeight(1).textAlign(TextAlign.End)
              Text(row.best).fontSize(12).fontColor(Color.White).layoutWeight(1).textAlign(TextAlign.End)
            }
            .padding({ top: 7, bottom: 7 })
            .borderRadius(6)
            .backgroundColor(row.me ? 'rgba(255,138,0,0.3)' : Color.Transparent)
          }, (row: ResultRow) => String(row.pos) + row.name)
        }
        .width('92%')
        .padding(10)
        .borderRadius(12)
        .backgroundColor('rgba(10,20,48,0.72)')
        .border({ width: 1, color: 'rgba(120,190,255,0.35)' })
        Row({ space: 14 }) {
          Button('再来一局')
            .width(150).height(46).borderRadius(23)
            .backgroundColor('#ff8a00').fontColor(Color.White).fontSize(16).fontWeight(900)
            .onClick(() => {
              this.result = null;
              this.startRace();
            })
          Button('返回大厅')
            .width(150).height(46).borderRadius(23)
            .backgroundColor('#1d5fe0').fontColor(Color.White).fontSize(16)
            .onClick(() => {
              this.result = null;
              this.game?.toMenu();
            })
        }
      }
      .width('100%')
      .padding({ top: 30, bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(6,14,36,0.78)')
  }
}
