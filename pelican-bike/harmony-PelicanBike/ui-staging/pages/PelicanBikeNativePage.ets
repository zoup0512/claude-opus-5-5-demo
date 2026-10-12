import { common } from '@kit.AbilityKit';
import { NativeGameBridgeAdapter } from '../bridge/NativeGameBridgeAdapter';
import { LibPelicanApiAdapter } from '../bridge/LibPelicanApiAdapter';
import { LibPelicanPort } from '../bridge/LibPelicanPort';
import { HarmonySystemCapabilityAdapter } from '../bridge/HarmonySystemCapabilityAdapter';
import { PngScreenshotSaver } from '../bridge/PngScreenshotSaver';
import { WindowMetricsBinder } from '../bridge/WindowMetricsBinder';
import { PelicanBikePage } from './PelicanBikePage';

@Entry
@Component
struct PelicanBikeNativePage {
  private readonly context: common.UIAbilityContext =
    this.getUIContext().getHostContext() as common.UIAbilityContext;
  private readonly nativeApi: LibPelicanApiAdapter = new LibPelicanApiAdapter();
  private readonly gameBridge: NativeGameBridgeAdapter = new NativeGameBridgeAdapter(
    new LibPelicanPort(this.nativeApi, this.context.resourceManager)
  );
  private readonly systemAdapter: HarmonySystemCapabilityAdapter = new HarmonySystemCapabilityAdapter(
    this.context,
    new PngScreenshotSaver(this.context)
  );
  private readonly metricsBinder: WindowMetricsBinder = new WindowMetricsBinder(this.context);

  aboutToAppear(): void {
    AppStorage.setOrCreate('pelicanAppForeground', true);
    AppStorage.setOrCreate('pelicanPendingHour', -1);
    AppStorage.setOrCreate('pelicanPendingCamera', '');
    this.metricsBinder.bind();
  }

  aboutToDisappear(): void {
    this.metricsBinder.unbind();
  }

  build() {
    PelicanBikePage({
      previewMode: false,
      gameBridge: this.gameBridge,
      systemAdapter: this.systemAdapter
    })
  }
}
