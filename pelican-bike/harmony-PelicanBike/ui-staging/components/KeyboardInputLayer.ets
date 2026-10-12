import { KeyCode } from '@kit.InputKit';
import { ControlKey, GameAction } from '../model/GameModels';

@Component
export struct KeyboardInputLayer {
  enabled: boolean = true;
  onControl: (key: ControlKey, pressed: boolean) => void = (_key: ControlKey, _pressed: boolean): void => {};
  onAction: (action: GameAction) => void = (_action: GameAction): void => {};
  onCycleCamera: () => void = (): void => {};
  onMusic: () => void = (): void => {};
  onScreenshot: () => void = (): void => {};
  onImmersive: () => void = (): void => {};
  onToggleHud: () => void = (): void => {};

  build() {
    Stack()
      .width('100%')
      .height('100%')
      .focusable(true)
      .defaultFocus(true)
      .hitTestBehavior(HitTestMode.None)
      .onKeyEvent((event: KeyEvent): boolean => {
        if (!this.enabled) {
          return false;
        }
        const isDown: boolean = event.type === KeyType.Down;
        const control: ControlKey | undefined = this.mapControl(event);
        if (control !== undefined) {
          this.onControl(control, isDown);
          return true;
        }
        if (!isDown) {
          return false;
        }
        return this.handleAction(event);
      })
  }

  mapControl(event: KeyEvent): ControlKey | undefined {
    if (event.keyCode === KeyCode.KEYCODE_W || event.keyCode === KeyCode.KEYCODE_DPAD_UP) {
      return ControlKey.ACCELERATE;
    }
    if (event.keyCode === KeyCode.KEYCODE_S || event.keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
      return ControlKey.BRAKE;
    }
    if (event.keyCode === KeyCode.KEYCODE_A || event.keyCode === KeyCode.KEYCODE_DPAD_LEFT) {
      return ControlKey.LEFT;
    }
    if (event.keyCode === KeyCode.KEYCODE_D || event.keyCode === KeyCode.KEYCODE_DPAD_RIGHT) {
      return ControlKey.RIGHT;
    }
    return undefined;
  }

  handleAction(event: KeyEvent): boolean {
    if (event.keyCode === KeyCode.KEYCODE_SPACE) {
      this.onAction(GameAction.JUMP);
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_B) {
      this.onAction(GameAction.BELL);
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_T) {
      this.onAction(GameAction.TRICK);
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_H) {
      this.onAction(GameAction.HONK);
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_C) {
      this.onCycleCamera();
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_N) {
      this.onAction(GameAction.NEXT_TIME);
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_M) {
      this.onMusic();
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_K) {
      this.onScreenshot();
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_F) {
      this.onImmersive();
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_U) {
      this.onToggleHud();
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_P) {
      this.onAction(GameAction.TOGGLE_PAUSE);
      return true;
    }
    return false;
  }
}
