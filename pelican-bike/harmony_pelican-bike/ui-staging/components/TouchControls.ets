import { ControlKey, GameAction } from '../model/GameModels';
import { PelicanColors, PelicanMetrics } from '../theme/PelicanTheme';

@Component
export struct TouchControls {
  compact: boolean = false;
  safeLeft: number = 0;
  safeRight: number = 0;
  safeBottom: number = 0;
  bottomOffset: number = 150;
  onControl: (key: ControlKey, pressed: boolean) => void = (_key: ControlKey, _pressed: boolean): void => {};
  onAction: (action: GameAction) => void = (_action: GameAction): void => {};

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Row({ space: 10 }) {
        this.holdButton('◀', ControlKey.LEFT, true)
        this.holdButton('▶', ControlKey.RIGHT, true)
      }
      .translate({ x: Math.max(16, this.safeLeft + 12), y: 0 })

      Column({ space: 10 }) {
        Row({ space: 10 }) {
          this.actionButton('铃', GameAction.BELL, false)
          this.actionButton('翼', GameAction.TRICK, false)
          this.actionButton('跃', GameAction.JUMP, false)
        }
        Row({ space: 10 }) {
          this.holdButton('▼', ControlKey.BRAKE, true)
          this.holdButton('▲', ControlKey.ACCELERATE, true)
        }
      }
      .alignItems(HorizontalAlign.End)
      .position({ x: '100%', y: 0 })
      .translate({ x: this.windowWidthForRightPad() - this.rightPadWidth(), y: 0 })
    }
    .width('100%')
    .height(this.controlHeight())
    .padding({ bottom: Math.max(0, this.safeBottom) })
    .translate({ y: -this.bottomOffset })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  holdButton(label: string, key: ControlKey, big: boolean) {
    Button(label)
      .width(this.buttonSize(big))
      .height(this.buttonSize(big))
      .fontSize(label.length > 1 ? 18 : 22)
      .fontColor(PelicanColors.TEXT)
      .backgroundColor(PelicanColors.GLASS)
      .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
      .border({ width: 1, color: PelicanColors.STROKE, radius: 999 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.onControl(key, true);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.onControl(key, false);
        }
      })
  }

  @Builder
  actionButton(label: string, action: GameAction, big: boolean) {
    Button(label)
      .width(this.buttonSize(big))
      .height(this.buttonSize(big))
      .fontSize(label.length > 1 ? 18 : 22)
      .fontColor(PelicanColors.TEXT)
      .backgroundColor(PelicanColors.GLASS)
      .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
      .border({ width: 1, color: PelicanColors.STROKE, radius: 999 })
      .onClick(() => {
        this.onAction(action);
      })
  }

  buttonSize(big: boolean): number {
    if (this.compact) {
      return big ? PelicanMetrics.TOUCH_BUTTON_BIG_COMPACT : PelicanMetrics.TOUCH_BUTTON_COMPACT;
    }
    return big ? PelicanMetrics.TOUCH_BUTTON_BIG : PelicanMetrics.TOUCH_BUTTON;
  }

  controlHeight(): number {
    return this.buttonSize(true) * 2 + 24 + Math.max(0, this.safeBottom);
  }

  windowWidthForRightPad(): number {
    return -Math.max(16, this.safeRight + 12);
  }

  rightPadWidth(): number {
    return this.buttonSize(true) * 2 + 10;
  }
}
