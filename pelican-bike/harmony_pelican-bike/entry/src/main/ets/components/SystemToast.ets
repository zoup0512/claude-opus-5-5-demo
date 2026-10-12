import { PelicanColors } from '../theme/PelicanTheme';
import { GlassPanel } from './GlassPanel';

@Component
export struct SystemToast {
  message: string = '';
  safeTop: number = 0;

  @Builder
  panelContent() {
    Text(this.message)
      .fontSize(13)
      .fontColor(PelicanColors.TEXT)
      .textAlign(TextAlign.Center)
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.message.length > 0) {
        Column() {
          GlassPanel({
            strong: true,
            radius: 14,
            paddingValue: { left: 14, right: 14, top: 9, bottom: 9 }
          }) {
            this.panelContent()
          }
        }
        .constraintSize({ maxWidth: 320 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: Math.max(56, this.safeTop + 46) })
    .hitTestBehavior(HitTestMode.None)
  }
}
