import { PelicanColors } from '../theme/PelicanTheme';

@Component
export struct GameSurface {
  surfaceId: string = 'pelican-game-surface';
  previewMode: boolean = false;
  onSurfaceReady: (surfaceId: string) => void = (_surfaceId: string): void => {};
  onSurfaceDestroyed: () => void = (): void => {};
  controller: XComponentController = new XComponentController();

  build() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({
        id: this.surfaceId,
        type: 'surface',
        libraryname: 'pelican',
        controller: this.controller
      })
        .width('100%')
        .height('100%')
        .backgroundColor(PelicanColors.BACKGROUND)
        .onLoad(() => {
          this.onSurfaceReady(this.surfaceId);
        })
        .onDestroy(() => {
          this.onSurfaceDestroyed();
        })

      if (this.previewMode) {
        Column({ space: 8 }) {
          Text('Native Game Surface')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#6FFFFFFF')
          Text('Preview 使用占位层；设备端由 libpelican.so 自动绑定 XComponent')
            .fontSize(12)
            .fontColor('#58FFFFFF')
            .textAlign(TextAlign.Center)
        }
        .padding(18)
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PelicanColors.BACKGROUND)
  }
}
