import { PelicanColors, PelicanMetrics, panelShadow } from '../theme/PelicanTheme';

@Component
export struct GlassPanel {
  @BuilderParam content: () => void = this.emptyContent;
  radius: number = PelicanMetrics.PANEL_RADIUS;
  paddingValue: Padding | Length = 0;
  strong: boolean = false;

  @Builder
  emptyContent() {
  }

  build() {
    Column() {
      this.content();
    }
    .padding(this.paddingValue)
    .backgroundColor(this.strong ? PelicanColors.GLASS_STRONG : PelicanColors.GLASS)
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
    .border({
      width: 1,
      color: PelicanColors.STROKE,
      radius: this.radius
    })
    .shadow(panelShadow())
    .clip(true)
  }
}
