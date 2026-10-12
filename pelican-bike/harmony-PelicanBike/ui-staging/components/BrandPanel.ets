import { PelicanBreakpoints, PelicanColors } from '../theme/PelicanTheme';
import { GlassPanel } from './GlassPanel';

@Component
export struct BrandPanel {
  widthValue: number = 1000;
  compact: boolean = false;

  @Builder
  panelContent() {
    Row({ space: 10 }) {
      Text('P')
        .width(this.compact ? 28 : 32)
        .height(this.compact ? 28 : 32)
        .fontSize(this.compact ? 17 : 20)
        .fontWeight(FontWeight.Bolder)
        .fontColor('#1A1206')
        .textAlign(TextAlign.Center)
        .backgroundColor(PelicanColors.ACCENT_LIGHT)
        .borderRadius(999)
      if (!this.compact) {
        Column({ space: 2 }) {
          Text('鹈鹕骑单车')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .letterSpacing(0.4)
            .fontColor(PelicanColors.TEXT)
          if (this.widthValue > PelicanBreakpoints.NARROW) {
            Text('Pelican on a Bike · 实时 3D')
              .fontSize(11)
              .fontColor(PelicanColors.TEXT_MUTED)
          }
        }
        .alignItems(HorizontalAlign.Start)
      }
    }
  }

  build() {
    GlassPanel({
      radius: 16,
      paddingValue: {
        left: this.compact ? 10 : 14,
        right: this.compact ? 10 : 14,
        top: this.compact ? 8 : 10,
        bottom: this.compact ? 8 : 10
      },
      content: this.panelContent
    })
  }
}
