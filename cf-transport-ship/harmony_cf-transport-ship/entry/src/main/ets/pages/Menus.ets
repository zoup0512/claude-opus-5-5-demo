/**
 * 全屏面板：主菜单 / 暂停 / 结算 / 换枪。由 Index.ets 按当前屏幕状态显示。
 */
import { Game, GameOptions } from '../game/game';
import { PRIMARIES, weaponDef } from '../game/weapons';

interface SegOpt {
  label: string;
  value: string;
}

interface NumOpt {
  label: string;
  value: number;
}

@Component
export struct SegRow {
  @Prop label: string = '';
  opts: SegOpt[] = [];
  @Prop cur: string = '';
  onPick: (v: string) => void = () => {
  };

  build() {
    Column() {
      Text(this.label)
        .fontSize(12)
        .fontColor('#9aa7b4')
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 4 })
      Row({ space: 6 }) {
        ForEach(this.opts, (o: SegOpt) => {
          Button(o.label)
            .fontSize(o.label.length > 3 ? 12 : 13)
            .height(32)
            .padding({ left: 10, right: 10 })
            .backgroundColor(this.cur === o.value ? '#f5b321' : '#2a3646')
            .fontColor(this.cur === o.value ? '#1c2530' : '#cfd8e2')
            .onClick(() => {
              this.onPick(o.value);
            })
        }, (o: SegOpt) => o.value)
      }
    }
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct SliderRow {
  @Prop label: string = '';
  @Prop cur: number = 0;
  min: number = 0;
  max: number = 1;
  step: number = 0.05;
  onPick: (v: number) => void = () => {
  };

  build() {
    Column() {
      Row {
        Text(this.label)
          .fontSize(12)
          .fontColor('#9aa7b4')
        Blank()
        Text(this.cur.toFixed(this.step >= 1 ? 0 : 2))
          .fontSize(13)
          .fontColor('#f5b321')
      }
      .width('100%')
      Slider({
        value: this.cur,
        min: this.min,
        max: this.max,
        step: this.step,
        style: SliderStyle.OutSet
      })
        .selectedColor('#f5b321')
        .trackColor('#2a3646')
        .blockColor('#f5b321')
        .onChange((v: number) => {
          this.onPick(v);
        })
    }
  }
}

@Component
export struct MenuPanel {
  game: Game = new Game();
  @State o: GameOptions = new GameOptions();

  aboutToAppear(): void {
    this.o = this.game.opts;
  }

  build() {
    Scroll() {
      Column() {
        // 标题
        Column() {
          Text('CROSSFIRE · 团队竞技')
            .fontSize(12)
            .fontColor('#f5b321')
            .letterSpacing(2)
          Text('运 输 船')
            .fontSize(42)
            .fontColor('#f2f5f8')
            .fontWeight(FontWeight.Bold)
            .margin({ top: 2, bottom: 2 })
          Text('TRANSPORT SHIP')
            .fontSize(12)
            .fontColor('#7f8ea0')
            .letterSpacing(6)
          Text('保卫者登船检查军火，遭遇潜伏者伏击。船头船尾出生，中路 V 形集装箱、两侧管道二楼架枪。')
            .fontSize(11)
            .fontColor('#8b98a6')
            .textAlign(TextAlign.Center)
            .margin({ top: 8 })
        }
        .alignItems(HorizontalAlign.Center)

        // 选项
        Column({ space: 10 }) {
          SegRow({
            label: '阵营', cur: this.o.team,
            opts: [{ label: '潜伏者', value: 'BL' }, { label: '保卫者', value: 'GR' }],
            onPick: (v: string) => {
              this.o.team = v;
            }
          })
          SegRow({
            label: '主武器', cur: this.o.primary,
            opts: [
              { label: 'AK-47', value: 'ak47' }, { label: 'M4A1', value: 'm4a1' },
              { label: 'AWM', value: 'awm' }, { label: 'MP5', value: 'mp5' }
            ],
            onPick: (v: string) => {
              this.o.primary = v;
            }
          })
          Row({ space: 20 }) {
            SegRow({
              label: '对战规模', cur: `${this.o.size}`,
              opts: [{ label: '4v4', value: '4' }, { label: '6v6', value: '6' }, { label: '8v8', value: '8' }],
              onPick: (v: string) => {
                this.o.size = Number(v);
              }
            })
            SegRow({
              label: '目标击杀', cur: `${this.o.goal}`,
              opts: [{ label: '30', value: '30' }, { label: '50', value: '50' }, { label: '100', value: '100' }],
              onPick: (v: string) => {
                this.o.goal = Number(v);
              }
            })
          }
          SegRow({
            label: '电脑难度', cur: this.o.diff,
            opts: [{ label: '简单', value: 'easy' }, { label: '普通', value: 'normal' },
              { label: '困难', value: 'hard' }, { label: '地狱', value: 'hell' }],
            onPick: (v: string) => {
              this.o.diff = v;
            }
          })
          Row({ space: 20 }) {
            SegRow({
              label: '时间', cur: this.o.tod,
              opts: [{ label: '白天', value: 'day' }, { label: '黄昏', value: 'dusk' }],
              onPick: (v: string) => {
                this.o.tod = v;
                this.game.onOption('tod', v);
              }
            })
          }
          Row({ space: 14 }) {
            SliderRow({
              label: '灵敏度', cur: this.o.sens, min: 0.2, max: 3, step: 0.05,
              onPick: (v: number) => {
                this.o.sens = v;
              }
            })
            SliderRow({
              label: '视野 FOV', cur: this.o.fov, min: 65, max: 100, step: 1,
              onPick: (v: number) => {
                this.o.fov = v;
              }
            })
            SliderRow({
              label: '音量', cur: this.o.vol, min: 0, max: 1, step: 0.05,
              onPick: (v: number) => {
                this.o.vol = v;
                this.game.onOption('vol', v);
              }
            })
          }
        }
        .padding(14)
        .borderRadius(10)
        .backgroundColor('rgba(16,24,36,0.82)')
        .margin({ top: 14 })

        Button('开 始 游 戏')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .width(260)
          .height(48)
          .backgroundColor('#f5b321')
          .fontColor('#1c2530')
          .margin({ top: 16 })
          .onClick(() => {
            this.game.startMatch();
          })
        Text('左侧摇杆移动 · 右侧滑动转视角 · 开火按钮射击')
          .fontSize(11)
          .fontColor('#77879a')
          .margin({ top: 8 })
      }
      .constraintSize({ minHeight: '100%' })
      .justifyContent(FlexAlign.Center)
      .padding(20)
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(10,16,26,0.62)')
  }
}

@Component
export struct PausePanel {
  game: Game = new Game();

  build() {
    Column({ space: 12 }) {
      Text('暂 停')
        .fontSize(30)
        .fontColor('#f2f5f8')
        .fontWeight(FontWeight.Bold)
      Column({ space: 10 }) {
        SliderRow({
          label: '灵敏度', cur: this.game.opts.sens, min: 0.2, max: 3, step: 0.05,
          onPick: (v: number) => {
            this.game.opts.sens = v;
          }
        })
        SliderRow({
          label: '视野 FOV', cur: this.game.opts.fov, min: 65, max: 100, step: 1,
          onPick: (v: number) => {
            this.game.opts.fov = v;
          }
        })
        SliderRow({
          label: '音量', cur: this.game.opts.vol, min: 0, max: 1, step: 0.05,
          onPick: (v: number) => {
            this.game.opts.vol = v;
            this.game.onOption('vol', v);
          }
        })
        SegRow({
          label: '时间', cur: this.game.opts.tod,
          opts: [{ label: '白天', value: 'day' }, { label: '黄昏', value: 'dusk' }],
          onPick: (v: string) => {
            this.game.opts.tod = v;
            this.game.onOption('tod', v);
          }
        })
      }
      .padding(14)
      .borderRadius(10)
      .backgroundColor('rgba(16,24,36,0.82)')
      Button('继 续')
        .width(220)
        .height(44)
        .backgroundColor('#f5b321')
        .fontColor('#1c2530')
        .fontSize(17)
        .onClick(() => {
          this.game.resume();
        })
      Button('退出到主菜单')
        .width(220)
        .height(40)
        .backgroundColor('#2a3646')
        .fontColor('#cfd8e2')
        .fontSize(14)
        .onClick(() => {
          this.game.quitToMenu();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(8,12,20,0.66)')
  }
}

@Component
export struct LoadoutPanel {
  game: Game = new Game();
  @State cur: string = '';

  aboutToAppear(): void {
    this.cur = this.game.player !== null ? (this.game.player.nextPrimary.length > 0
      ? this.game.player.nextPrimary : this.game.player.primary) : this.game.opts.primary;
  }

  build() {
    Column({ space: 14 }) {
      Text('更换主武器')
        .fontSize(24)
        .fontColor('#f2f5f8')
        .fontWeight(FontWeight.Bold)
      Text('复活时生效；在出生点内立即生效。副武器沙漠之鹰、军刀、手雷自动配备。')
        .fontSize(11)
        .fontColor('#8b98a6')
      Row({ space: 10 }) {
        ForEach(PRIMARIES, (id: string) => {
          Column({ space: 5 }) {
            Text(weaponDef(id).name)
              .fontSize(17)
              .fontColor(this.cur === id ? '#f5b321' : '#dfe6ee')
              .fontWeight(FontWeight.Bold)
            Text(['伤害高 · 潜伏者经典', '稳定 · 保卫者经典', '一枪致命 · 需开镜', '射速快 · 灵活'][PRIMARIES.indexOf(id)])
              .fontSize(10)
              .fontColor('#8b98a6')
          }
          .padding(12)
          .borderRadius(8)
          .backgroundColor(this.cur === id ? 'rgba(245,179,33,0.18)' : 'rgba(22,32,46,0.9)')
          .border({
            width: 1,
            color: this.cur === id ? '#f5b321' : '#2a3646'
          })
          .onClick(() => {
            this.cur = id;
            this.game.chooseLoadout(id);
          })
        }, (id: string) => id)
      }
      Button('确 定')
        .width(200)
        .height(42)
        .backgroundColor('#2a3646')
        .fontColor('#e8eef4')
        .fontSize(16)
        .margin({ top: 8 })
        .onClick(() => {
          this.game.closeLoadout();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(8,12,20,0.66)')
  }
}

@Component
export struct EndPanel {
  game: Game = new Game();
  @State win: number = -1;
  @State sBL: number = 0;
  @State sGR: number = 0;
  @State mvp: string = '';
  @State mine: string = '';
  private rows: string[][] = [];

  aboutToAppear(): void {
    this.win = this.game.hud.endInfo.win;
    this.sBL = this.game.hud.endInfo.sBL;
    this.sGR = this.game.hud.endInfo.sGR;
    this.mvp = this.game.hud.endInfo.mvp;
    this.mine = this.game.hud.endInfo.mine;
    const br = this.game.boardRows();
    for (const r of br) {
      this.rows.push([r.name, r.team, `${r.k}`, `${r.d}`, `${r.hs}`, r.me ? '1' : '']);
    }
  }

  build() {
    Column({ space: 10 }) {
      Text(this.win === 1 ? '胜 利' : this.win === -1 ? '平 局' : '失 败')
        .fontSize(38)
        .fontColor(this.win === 1 ? '#f5b321' : '#e0522e')
        .fontWeight(FontWeight.Bold)
      Text(`潜伏者 ${this.sBL} : ${this.sGR} 保卫者`)
        .fontSize(15)
        .fontColor('#dfe6ee')
      if (this.mvp.length > 0) {
        Text(`MVP：${this.mvp}`)
          .fontSize(12)
          .fontColor('#f5b321')
      }
      Text(`你的战绩：${this.mine}`)
        .fontSize(12)
        .fontColor('#c3ceda')
      // 战绩表
      Column({ space: 2 }) {
        ForEach(this.rows, (r: string[], idx: number) => {
          Row() {
            Text(r[0])
              .fontSize(11)
              .fontColor(r[1] === 'BL' ? '#ff9b70' : '#8cc8ff')
              .layoutWeight(2)
              .maxLines(1)
            Text(r[2]).fontSize(11).fontColor(r[5] === '1' ? '#f5b321' : '#c3ceda').layoutWeight(1).textAlign(TextAlign.End)
            Text('/').fontSize(11).fontColor('#5c6b7c').layoutWeight(0.4).textAlign(TextAlign.Center)
            Text(r[3]).fontSize(11).fontColor('#c3ceda').layoutWeight(1).textAlign(TextAlign.End)
            Text(r[4]).fontSize(11).fontColor('#c3ceda').layoutWeight(1).textAlign(TextAlign.End)
          }
          .width('100%')
          .padding({ left: 10, right: 10 })
        }, (r: string[], idx: number) => `${idx}_${r[0]}`)
      }
      .padding(8)
      .borderRadius(8)
      .backgroundColor('rgba(16,24,36,0.8)')
      .constraintSize({ maxHeight: 220 })
      Row({ space: 12 }) {
        Button('再 来 一 局')
          .width(150)
          .height(42)
          .backgroundColor('#f5b321')
          .fontColor('#1c2530')
          .onClick(() => {
            this.game.startMatch();
          })
        Button('主菜单')
          .width(120)
          .height(42)
          .backgroundColor('#2a3646')
          .fontColor('#e8eef4')
          .onClick(() => {
            this.game.quitToMenu();
          })
      }
      .margin({ top: 6 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(8,12,20,0.72)')
  }
}
