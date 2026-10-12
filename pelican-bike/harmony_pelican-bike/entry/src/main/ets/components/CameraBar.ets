import { CameraMode } from '../model/GameModels';
import { PelicanColors } from '../theme/PelicanTheme';
import { GlassPanel } from './GlassPanel';

@Component
export struct CameraBar {
  @Prop activeCamera: CameraMode = CameraMode.CINE;
  @Prop compact: boolean = false;
  maxWidth: number = 520;
  onSelect: (mode: CameraMode) => void = (_mode: CameraMode): void => {};

  @Builder
  cameraButton(label: string, mode: CameraMode) {
    Button(label)
      .height(this.compact ? 32 : 36)
      .padding({ left: this.compact ? 9 : 12, right: this.compact ? 9 : 12 })
      .fontSize(this.compact ? 12 : 13)
      .fontColor(this.activeCamera === mode ? '#1A1206' : PelicanColors.TEXT_MUTED)
      .fontWeight(this.activeCamera === mode ? FontWeight.Bold : FontWeight.Regular)
      .backgroundColor(this.activeCamera === mode ? PelicanColors.ACCENT : PelicanColors.TRANSPARENT)
      .borderRadius(10)
      .onClick((): void => {
        this.onSelect(mode);
      })
  }

  @Builder
  panelContent() {
    Scroll() {
      Row({ space: 4 }) {
        this.cameraButton('自由环绕', CameraMode.ORBIT)
        this.cameraButton('追随', CameraMode.CHASE)
        this.cameraButton('侧面跟拍', CameraMode.SIDE)
        this.cameraButton('电影运镜', CameraMode.CINE)
        this.cameraButton('鹈鹕视角', CameraMode.POV)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  build() {
    Stack() {
      GlassPanel({
        radius: 14,
        paddingValue: 5
      }) {
        this.panelContent()
      }
    }
    .width(this.maxWidth)
  }
}
