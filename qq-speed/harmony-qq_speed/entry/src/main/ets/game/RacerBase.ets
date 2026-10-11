// 车手公共状态基类：玩家车 / AI 车共用（碰撞、道具、排名通用逻辑）

export class CarStats {
  drift: number = 0;
  small: number = 0;
  perfect: number = 0;
  double: number = 0;
  nitro: number = 0;
  crash: number = 0;
  top: number = 0;
  land: number = 0;
}

export class RacerBase {
  isPlayer: boolean = false;
  name: string = '';
  // 位姿
  x: number = 0;
  y: number = 0;
  z: number = 0;
  h: number = 0; // 车头朝向
  m: number = 0; // 速度方向
  s: number = 0; // 速率
  vy: number = 0;
  airborne: boolean = false;
  drifting: boolean = false;
  // 道具/异常状态
  spin: number = 0;
  shield: number = 0;
  slowTime: number = 0;
  magnet: number = 0;
  nitroTime: number = 0;
  // 玩家侧加速状态（AI 不用，统一字段方便特效/相机读取）
  smallBoost: number = 0;
  padTime: number = 0;
  startBoost: number = 0;
  gauge: number = 0;
  throttle: number = 0;
  // 赛道坐标
  d: number = 0;
  lat: number = 0;
  hint: number = -1;
  dist: number = 0;
  latV: number = 0;
  pushD: number = 0;
  spinAng: number = 0;
  magnetTarget: RacerBase | null = null;
  // 比赛进度
  progress: number = 0;
  lapsDone: number = 0;
  lapTimes: number[] = [];
  lapStart: number = 0;
  finished: boolean = false;
  finishTime: number = 0;
  slot: number = 0;
  items: string[] = [];
  itemTimer: number = 2;
  stats: CarStats = new CarStats();
  skinIndex: number = 0;

  get speedKmh(): number {
    return Math.abs(this.s) * 3.6;
  }
}
