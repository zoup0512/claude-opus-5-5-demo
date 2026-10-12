import { GameBridge } from './GameBridge';
import { MockGameBridge } from './MockGameBridge';
import { PreviewSystemCapabilityAdapter, SystemCapabilityAdapter } from './SystemCapabilityAdapter';

export class BridgeFactory {
  static createGameBridge(): GameBridge {
    return new MockGameBridge();
  }

  static createSystemAdapter(): SystemCapabilityAdapter {
    return new PreviewSystemCapabilityAdapter();
  }
}
