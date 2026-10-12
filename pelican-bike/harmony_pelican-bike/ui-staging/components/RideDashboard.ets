import { GameTelemetry } from '../model/GameModels';
import { PelicanColors } from '../theme/PelicanTheme';
import { GlassPanel } from './GlassPanel';

@Component
export struct RideDashboard {
  telemetry: GameTelemetry = new GameTelemetry();
  compact: boolean = false;
  showStats: boolean = true;

  @Builder
  statLabel(label: string) {
    Text(label)
      .fontSize(this.compact ? 11.5 : 12.5)
      .fontColor(PelicanColors.TEXT_MUTED)
      .textAlign(TextAlign.Start)
  }

  @Builder
  statValue(value: string) {
    Text(value)
      .fontSize(this.compact ? 13 : 15)
      .fontWeight(FontWeight.Bold)
      .fontColor(PelicanColors.TEXT)
      .textAlign(TextAlign.End)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  panelContent() {
    Row({ space: this.compact ? 8 : 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        Gauge({ value: Math.min(55, Math.max(0, this.telemetry.speedKmh)), min: 0, max: 55 })
          .width(this.compact ? 96 : 124)
          .height(this.compact ? 96 : 124)
          .startAngle(135)
          .endAngle(405)
          .colors({
            angle: 135,
            colors: [
              [PelicanColors.CYAN, 0.0],
              ['#FFC27A', 0.60],
              [PelicanColors.DANGER, 1.0]
            ]
          })
          .strokeWidth(this.compact ? 7 : 9)
        Column({ space: 3 }) {
          Text(Math.round(this.telemetry.speedKmh).toString())
            .fontSize(this.compact ? 28 : 36)
            .fontWeight(FontWeight.Bold)
            .fontColor(PelicanColors.TEXT)
          Text('KM/H')
            .fontSize(11)
            .letterSpacing(1)
            .fontColor(PelicanColors.TEXT_MUTED)
        }
      }

      if (this.showStats) {
        Grid() {
          GridItem() { this.statLabel('踏频') }
          GridItem() { this.statValue(Math.round(this.telemetry.cadence).toString() + ' rpm') }
          GridItem() { this.statLabel('档位') }
          GridItem() { this.statValue(this.telemetry.gear.toString() + '/' + this.telemetry.gearCount.toString()) }
          GridItem() { this.statLabel('里程') }
          GridItem() { this.statValue(this.telemetry.distanceKm.toFixed(2) + ' km') }
          GridItem() { this.statLabel('镜头') }
          GridItem() { this.statValue(this.telemetry.cameraLabel) }
        }
        .columnsTemplate('auto auto')
        .rowsGap(5)
        .columnsGap(14)
      }
    }
  }

  build() {
    GlassPanel({
      radius: 16,
      paddingValue: {
        left: this.compact ? 8 : 12,
        right: this.compact ? 10 : 16,
        top: this.compact ? 8 : 12,
        bottom: this.compact ? 8 : 12
      },
      content: this.panelContent
    })
  }
}
