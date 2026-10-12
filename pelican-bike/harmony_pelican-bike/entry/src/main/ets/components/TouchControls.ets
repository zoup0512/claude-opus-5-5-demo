import { ControlKey, GameAction } from '../model/GameModels';
import { PelicanColors } from '../theme/PelicanTheme';

@Component
export struct TouchControls {
  compact: boolean = false;
  safeLeft: number = 0;
  safeRight: number = 0;
  safeBottom: number = 0;
  bottomOffset: number = 0;
  onControl: (key: ControlKey, pressed: boolean) => void = (_key: ControlKey, _pressed: boolean): void => {};
  onAction: (action: GameAction) => void = (_action: GameAction): void => {};

  @State private thumbX: number = 0;
  @State private thumbY: number = 0;
  private leftHeld: boolean = false;
  private rightHeld: boolean = false;
  private accelHeld: boolean = false;
  private brakeHeld: boolean = false;

  build() {
    Stack() {
      Stack({ alignContent: Alignment.BottomStart }) {
        this.joystick()
      }
      .width('100%')
      .height('100%')
      .padding({
        left: Math.max(20, this.safeLeft + 12),
        bottom: Math.max(12, this.safeBottom + 8)
      })
      .hitTestBehavior(HitTestMode.Transparent)

      Stack({ alignContent: Alignment.BottomEnd }) {
        Stack() {
          this.skill('♬', '按铃', GameAction.BELL, false, this.bellX(), 0)
          this.skill('✦', '展翅', GameAction.TRICK, false, this.trickX(), this.trickY())
          this.skill('↑', '跳跃', GameAction.JUMP, true, this.jumpX(), this.jumpY())
        }
        .width(this.areaWidth())
        .height(this.areaHeight())
      }
      .width('100%')
      .height('100%')
      .padding({
        right: Math.max(18, this.safeRight + 12),
        bottom: Math.max(10, this.safeBottom + 8)
      })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private joystick() {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Top }) {
        this.axisMark('▲')
      }
      .width('100%')
      .height('100%')
      .padding({ top: 5 })
      .hitTestBehavior(HitTestMode.None)

      Stack({ alignContent: Alignment.Bottom }) {
        this.axisMark('▼')
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: 5 })
      .hitTestBehavior(HitTestMode.None)

      Stack({ alignContent: Alignment.Start }) {
        this.axisMark('◀')
      }
      .width('100%')
      .height('100%')
      .padding({ left: 5 })
      .hitTestBehavior(HitTestMode.None)

      Stack({ alignContent: Alignment.End }) {
        this.axisMark('▶')
      }
      .width('100%')
      .height('100%')
      .padding({ right: 5 })
      .hitTestBehavior(HitTestMode.None)

      Circle()
        .width(this.stickSize() * 0.78)
        .height(this.stickSize() * 0.78)
        .fill('#132B39')
        .opacity(0.42)
        .stroke('#536E78')
        .strokeWidth(1)
        .hitTestBehavior(HitTestMode.None)
      Circle()
        .width(this.stickSize() * 0.43)
        .height(this.stickSize() * 0.43)
        .fill('#348F99')
        .stroke('#DFFFFB')
        .strokeWidth(3)
        .shadow({ radius: 12, color: '#993FD0C9', offsetX: 0, offsetY: 3 })
        .translate({ x: this.thumbX, y: this.thumbY })
        .hitTestBehavior(HitTestMode.None)

      // 透明命中层：Stack 自身的 onTouch 在 XComponent 之上不会触发。
      Button()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .borderRadius(this.stickSize() / 2)
        .stateEffect(false)
        .onTouch((event: TouchEvent): void => {
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.resetStick();
          } else if (event.touches.length > 0) {
            this.updateStick(event.touches[0].x, event.touches[0].y);
          }
        })
    }
    .width(this.stickSize())
    .height(this.stickSize())
    .borderRadius(this.stickSize() / 2)
    .backgroundColor('#B0143042')
    .border({ width: 2, color: '#84A1E5E8' })
    .shadow({ radius: 18, color: '#80000000', offsetX: 0, offsetY: 5 })
  }

  @Builder
  private axisMark(symbol: string) {
    Text(symbol)
      .fontSize(11)
      .fontColor('#A9E0E4')
  }

  @Builder
  private skill(symbol: string, label: string, action: GameAction, primary: boolean, x: number, y: number) {
    Button() {
      Column({ space: 1 }) {
        Text(symbol)
          .fontSize(primary ? 27 : 22)
          .fontColor(PelicanColors.TEXT)
        Text(label)
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(PelicanColors.TEXT)
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height('100%')
    }
    .width(this.skillSize(primary))
    .height(this.skillSize(primary))
    .borderRadius(999)
    .backgroundColor(primary ? '#C46B4226' : '#DD1A3446')
    .border({ width: 2, color: primary ? '#FFD28A' : '#B6E4E5' })
    .shadow({ radius: primary ? 17 : 10, color: primary ? '#80D69044' : '#99000000', offsetX: 0, offsetY: 3 })
    .stateEffect(false)
    .position({ x: x, y: y })
    .onClick((): void => { this.onAction(action); })
    .accessibilityText(label)
  }

  private stickSize(): number {
    return this.compact ? 110 : 142;
  }

  private skillSize(primary: boolean): number {
    if (primary) {
      return this.compact ? 70 : 82;
    }
    return this.compact ? 54 : 62;
  }

  private areaWidth(): number {
    return this.compact ? 178 : 208;
  }

  private areaHeight(): number {
    return this.compact ? 125 : 150;
  }

  private jumpX(): number {
    return this.areaWidth() - this.skillSize(true);
  }

  private jumpY(): number {
    return this.areaHeight() - this.skillSize(true);
  }

  private trickX(): number {
    return this.compact ? 8 : 10;
  }

  private trickY(): number {
    return this.areaHeight() - this.skillSize(false) - 44;
  }

  private bellX(): number {
    return this.areaWidth() - this.skillSize(false) - (this.compact ? 10 : 12);
  }

  private updateStick(x: number, y: number): void {
    const radius: number = this.stickSize() / 2;
    const dx: number = (x - radius) / radius;
    const dy: number = (y - radius) / radius;
    const distance: number = Math.sqrt(dx * dx + dy * dy);
    const extent: number = Math.min(distance, 0.48) * radius / (distance || 1);
    this.thumbX = dx * extent;
    this.thumbY = dy * extent;
    this.setHeld(ControlKey.LEFT, dx < -0.24);
    this.setHeld(ControlKey.RIGHT, dx > 0.24);
    this.setHeld(ControlKey.ACCELERATE, dy < -0.24);
    this.setHeld(ControlKey.BRAKE, dy > 0.24);
  }

  private setHeld(key: ControlKey, pressed: boolean): void {
    if (key === ControlKey.LEFT) {
      if (this.leftHeld === pressed) return;
      this.leftHeld = pressed;
    } else if (key === ControlKey.RIGHT) {
      if (this.rightHeld === pressed) return;
      this.rightHeld = pressed;
    } else if (key === ControlKey.ACCELERATE) {
      if (this.accelHeld === pressed) return;
      this.accelHeld = pressed;
    } else {
      if (this.brakeHeld === pressed) return;
      this.brakeHeld = pressed;
    }
    this.onControl(key, pressed);
  }

  private resetStick(): void {
    this.thumbX = 0;
    this.thumbY = 0;
    this.setHeld(ControlKey.LEFT, false);
    this.setHeld(ControlKey.RIGHT, false);
    this.setHeld(ControlKey.ACCELERATE, false);
    this.setHeld(ControlKey.BRAKE, false);
  }
}
