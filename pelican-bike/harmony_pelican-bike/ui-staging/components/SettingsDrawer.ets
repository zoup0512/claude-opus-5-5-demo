import { GameSettings, GlassesMode, QualityLevel } from '../model/GameModels';
import { PelicanColors, PelicanMetrics } from '../theme/PelicanTheme';
import { GlassPanel } from './GlassPanel';

@Component
export struct SettingsDrawer {
  settings: GameSettings = new GameSettings();
  widthValue: number = 720;
  heightValue: number = 1280;
  safeTop: number = 0;
  safeBottom: number = 0;
  onSettingsChange: (settings: GameSettings) => void = (_settings: GameSettings): void => {};
  onClose: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.CenterEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.onClose();
        })

      GlassPanel({
        strong: true,
        radius: 16,
        paddingValue: 0,
        content: () => {
          Column() {
            Row() {
              Column({ space: 2 }) {
                Text('参数面板')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFE3B3')
                Text('原 Web lil-gui 参数完整映射')
                  .fontSize(11)
                  .fontColor(PelicanColors.TEXT_MUTED)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Button('×')
                .width(36)
                .height(36)
                .fontSize(22)
                .fontColor(PelicanColors.TEXT)
                .backgroundColor('#14FFFFFF')
                .borderRadius(11)
                .onClick(() => {
                  this.onClose();
                })
            }
            .width('100%')
            .padding({ left: 16, right: 12, top: 12, bottom: 12 })
            .backgroundColor('#29FFB547')

            Scroll() {
              Column({ space: 8 }) {
                this.sectionTitle('骑行')
                this.sliderRow('巡航速度', this.settings.cruise, 0, 14, 0.5,
                  this.settings.cruise.toFixed(1) + ' m/s', (value: number): void => {
                    const next: GameSettings = this.settings.copy();
                    next.cruise = value;
                    this.onSettingsChange(next);
                  })
                this.toggleRow('自动驾驶（追鱼）', this.settings.autopilot, (value: boolean): void => {
                  const next: GameSettings = this.settings.copy();
                  next.autopilot = value;
                  this.onSettingsChange(next);
                })
                this.toggleRow('自动变速', this.settings.autoGear, (value: boolean): void => {
                  const next: GameSettings = this.settings.copy();
                  next.autoGear = value;
                  this.onSettingsChange(next);
                })

                this.sectionTitle('时间与天气')
                this.sliderRow('时刻', this.settings.hour, 0, 24, 0.01,
                  this.settings.hour.toFixed(2), (value: number): void => {
                    const next: GameSettings = this.settings.copy();
                    next.hour = value;
                    this.onSettingsChange(next);
                  })
                this.toggleRow('时间流动', this.settings.timeFlow, (value: boolean): void => {
                  const next: GameSettings = this.settings.copy();
                  next.timeFlow = value;
                  this.onSettingsChange(next);
                })
                this.sliderRow('流速', this.settings.dayRate, 0, 0.5, 0.005,
                  this.settings.dayRate.toFixed(3) + ' 时/秒', (value: number): void => {
                    const next: GameSettings = this.settings.copy();
                    next.dayRate = value;
                    this.onSettingsChange(next);
                  })
                this.sliderRow('云量', this.settings.cloud, 0, 0.9, 0.01,
                  this.settings.cloud.toFixed(2), (value: number): void => {
                    const next: GameSettings = this.settings.copy();
                    next.cloud = value;
                    this.onSettingsChange(next);
                  })
                this.sliderRow('浪高', this.settings.waveAmp, 0, 2.2, 0.05,
                  this.settings.waveAmp.toFixed(2), (value: number): void => {
                    const next: GameSettings = this.settings.copy();
                    next.waveAmp = value;
                    this.onSettingsChange(next);
                  })
                this.sliderRow('雾浓度', this.settings.fog, 0.6, 3, 0.05,
                  this.settings.fog.toFixed(2), (value: number): void => {
                    const next: GameSettings = this.settings.copy();
                    next.fog = value;
                    this.onSettingsChange(next);
                  })

                this.sectionTitle('画面')
                this.qualityChooser()
                this.toggleRow('泛光', this.settings.bloom, (value: boolean): void => {
                  const next: GameSettings = this.settings.copy();
                  next.bloom = value;
                  this.onSettingsChange(next);
                })
                this.sliderRow('泛光强度', this.settings.bloomBoost, 0, 3, 0.05,
                  this.settings.bloomBoost.toFixed(2), (value: number): void => {
                    const next: GameSettings = this.settings.copy();
                    next.bloomBoost = value;
                    this.onSettingsChange(next);
                  })
                this.sliderRow('曝光', this.settings.exposure, 0.4, 2, 0.01,
                  this.settings.exposure.toFixed(2), (value: number): void => {
                    const next: GameSettings = this.settings.copy();
                    next.exposure = value;
                    this.onSettingsChange(next);
                  })
                this.toggleRow('显示帧率', this.settings.showFps, (value: boolean): void => {
                  const next: GameSettings = this.settings.copy();
                  next.showFps = value;
                  this.onSettingsChange(next);
                })

                this.sectionTitle('鹈鹕')
                this.toggleRow('头盔', this.settings.helmet, (value: boolean): void => {
                  const next: GameSettings = this.settings.copy();
                  next.helmet = value;
                  this.onSettingsChange(next);
                })
                this.glassesChooser()
                this.toggleRow('围巾', this.settings.scarf, (value: boolean): void => {
                  const next: GameSettings = this.settings.copy();
                  next.scarf = value;
                  this.onSettingsChange(next);
                })
                this.toggleRow('目光跟随指针', this.settings.lookMouse, (value: boolean): void => {
                  const next: GameSettings = this.settings.copy();
                  next.lookMouse = value;
                  this.onSettingsChange(next);
                })

                this.sectionTitle('声音')
                this.sliderRow('主音量', this.settings.volume, 0, 1, 0.01,
                  Math.round(this.settings.volume * 100).toString() + '%', (value: number): void => {
                    const next: GameSettings = this.settings.copy();
                    next.volume = value;
                    this.onSettingsChange(next);
                  })
                this.toggleRow('生成式音乐', this.settings.music, (value: boolean): void => {
                  const next: GameSettings = this.settings.copy();
                  next.music = value;
                  this.onSettingsChange(next);
                })
                this.sliderRow('音乐音量', this.settings.musicVolume, 0, 1, 0.01,
                  Math.round(this.settings.musicVolume * 100).toString() + '%', (value: number): void => {
                    const next: GameSettings = this.settings.copy();
                    next.musicVolume = value;
                    this.onSettingsChange(next);
                  })
              }
              .padding({ left: 14, right: 14, top: 10, bottom: Math.max(18, this.safeBottom + 12) })
            }
            .scrollable(ScrollDirection.Vertical)
            .scrollBar(BarState.Auto)
            .layoutWeight(1)
          }
          .height('100%')
        }
      })
      .width(this.drawerWidth())
      .height('100%')
      .padding({ top: Math.max(0, this.safeTop), bottom: 0 })
      .onClick((event: ClickEvent) => {
        event.stopPropagation();
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Bold)
      .fontColor('#FFE3B3')
      .width('100%')
      .padding({ top: 10, bottom: 6 })
      .border({ width: { bottom: 1 }, color: { bottom: '#22FFFFFF' } })
  }

  @Builder
  sliderRow(label: string, value: number, minValue: number, maxValue: number,
    stepValue: number, display: string, onChange: (value: number) => void) {
    Column({ space: 4 }) {
      Row() {
        Text(label)
          .fontSize(12)
          .fontColor(PelicanColors.TEXT_MUTED)
          .layoutWeight(1)
        Text(display)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFC27A')
      }
      Slider({ value: value, min: minValue, max: maxValue, step: stepValue, style: SliderStyle.OutSet })
        .width('100%')
        .selectedColor(PelicanColors.ACCENT)
        .trackColor('#24FFFFFF')
        .blockColor(PelicanColors.ACCENT_LIGHT)
        .onChange((nextValue: number, _mode: SliderChangeMode) => {
          onChange(nextValue);
        })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  toggleRow(label: string, value: boolean, onChange: (value: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(12.5)
        .fontColor(PelicanColors.TEXT_MUTED)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(PelicanColors.CYAN)
        .onChange((nextValue: boolean) => {
          onChange(nextValue);
        })
    }
    .width('100%')
    .height(42)
  }

  @Builder
  qualityChooser() {
    Column({ space: 6 }) {
      Text('画质')
        .fontSize(12.5)
        .fontColor(PelicanColors.TEXT_MUTED)
        .width('100%')
      Row({ space: 4 }) {
        this.qualityButton('流畅', QualityLevel.LOW)
        this.qualityButton('均衡', QualityLevel.MEDIUM)
        this.qualityButton('精美', QualityLevel.HIGH)
        this.qualityButton('极致', QualityLevel.ULTRA)
      }
      .width('100%')
    }
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  qualityButton(label: string, value: QualityLevel) {
    Button(label)
      .height(34)
      .layoutWeight(1)
      .fontSize(11)
      .fontColor(this.settings.quality === value ? '#1A1206' : PelicanColors.TEXT_MUTED)
      .fontWeight(this.settings.quality === value ? FontWeight.Bold : FontWeight.Regular)
      .backgroundColor(this.settings.quality === value ? PelicanColors.ACCENT : '#12FFFFFF')
      .borderRadius(8)
      .onClick(() => {
        const next: GameSettings = this.settings.copy();
        next.quality = value;
        this.onSettingsChange(next);
      })
  }

  @Builder
  glassesChooser() {
    Column({ space: 6 }) {
      Text('墨镜')
        .fontSize(12.5)
        .fontColor(PelicanColors.TEXT_MUTED)
        .width('100%')
      Row({ space: 4 }) {
        this.glassesButton('自动', GlassesMode.AUTO)
        this.glassesButton('戴上', GlassesMode.ON)
        this.glassesButton('摘下', GlassesMode.OFF)
      }
      .width('100%')
    }
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  glassesButton(label: string, value: GlassesMode) {
    Button(label)
      .height(34)
      .layoutWeight(1)
      .fontSize(11)
      .fontColor(this.settings.glasses === value ? '#082020' : PelicanColors.TEXT_MUTED)
      .fontWeight(this.settings.glasses === value ? FontWeight.Bold : FontWeight.Regular)
      .backgroundColor(this.settings.glasses === value ? PelicanColors.CYAN : '#12FFFFFF')
      .borderRadius(8)
      .onClick(() => {
        const next: GameSettings = this.settings.copy();
        next.glasses = value;
        this.onSettingsChange(next);
      })
  }

  drawerWidth(): number {
    return Math.min(PelicanMetrics.DRAWER_WIDTH, Math.max(280, this.widthValue - 24));
  }
}
