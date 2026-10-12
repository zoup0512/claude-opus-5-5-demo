import { GameTelemetry, formatClock } from '../model/GameModels';
import { PelicanColors } from '../theme/PelicanTheme';
import { GlassPanel } from './GlassPanel';

@Component
export struct ScorePanel {
  telemetry: GameTelemetry = new GameTelemetry();
  compact: boolean = false;
  showTime: boolean = true;
  onHourChange: (hour: number) => void = (_hour: number): void => {};
  onToggleFlow: () => void = (): void => {};
  timeFlow: boolean = true;

  @Builder
  panelContent() {
    Column({ space: this.showTime ? 10 : 0 }) {
      Row() {
        Row({ space: 8 }) {
          Text('鱼')
            .fontSize(this.compact ? 18 : 22)
            .fontWeight(FontWeight.Bold)
            .fontColor(PelicanColors.CYAN)
          Text(this.telemetry.fishCount.toString())
            .fontSize(this.compact ? 28 : 34)
            .fontWeight(FontWeight.Bolder)
            .fontColor(PelicanColors.ACCENT)
        }
        .layoutWeight(1)
        Column({ space: 2 }) {
          Text('成就')
            .fontSize(12)
            .fontColor(PelicanColors.TEXT_MUTED)
          Text(this.telemetry.achievementCount.toString() + '/' + this.telemetry.achievementTotal.toString())
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(PelicanColors.TEXT)
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')

      if (this.showTime) {
        Row({ space: 8 }) {
          Text(this.telemetry.isNight ? '夜' : (this.telemetry.hour < 8 || this.telemetry.hour > 17 ? '昏' : '昼'))
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.telemetry.isNight ? '#B9C8FF' : PelicanColors.ACCENT_LIGHT)
          Slider({ value: this.telemetry.hour, min: 0, max: 24, step: 0.01, style: SliderStyle.OutSet })
            .layoutWeight(1)
            .selectedColor(PelicanColors.ACCENT)
            .trackColor('#24FFFFFF')
            .blockColor(PelicanColors.ACCENT_LIGHT)
            .onChange((value: number, _mode: SliderChangeMode): void => {
              this.onHourChange(value);
            })
          Text(formatClock(this.telemetry.hour))
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(PelicanColors.TEXT)
            .width(46)
          Button(this.timeFlow ? 'Ⅱ' : '▶')
            .width(32)
            .height(32)
            .fontSize(13)
            .fontColor(PelicanColors.TEXT)
            .backgroundColor('#383FD0C9')
            .borderRadius(10)
            .onClick((): void => {
              this.onToggleFlow();
            })
        }
        .width('100%')
      }
    }
  }

  build() {
    GlassPanel({
      radius: 16,
      paddingValue: {
        left: this.compact ? 12 : 16,
        right: this.compact ? 12 : 16,
        top: this.compact ? 10 : 12,
        bottom: this.compact ? 10 : 12
      },
      content: this.panelContent
    })
    .width(this.compact ? 172 : 230)
  }
}
